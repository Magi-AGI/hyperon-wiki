#!/usr/bin/env ruby
# Apply a frozen transcript delta manifest: planned CREATES and UPDATES only.
#
# This is the write counterpart to the delta planner in
# scripts/ingest_transcripts.rb. The planner compares every rendered transcript
# card against the live deck and emits a manifest; this file executes that
# manifest, one row at a time, and nothing else.
#
# WHAT IT CAN DO
#   * Card.create!  a card the manifest marked `create` and that is absent live
#   * card.update!  a card the manifest marked `update` whose live content
#                   still hashes to the manifest's live_hash
#
# WHAT IT CANNOT DO - there is no code path to any of these in this file:
#   * delete, destroy, trash or prune a card
#   * rename or re-file a card
#   * touch an orphan, a stale chunk card, or a foreign-corpus card
#   * touch a protected card
#   * touch anything that is not a descendant of the configured parent card
#   * contact production, or any host at all (no network client is required)
#   * run raw SQL (no execute / exec_query / select_all / find_by_sql)
#
# DEFAULT IS DRY RUN. A mutating run requires ALL FOUR of:
#   TRANSCRIPT_DELTA_WRITE=1
#   TRANSCRIPT_DELTA_MANIFEST_SHA=<sha256 of the manifest file>
#   TRANSCRIPT_DELTA_CONFIRM=APPLY-TRANSCRIPT-DELTA-LOCAL
#   a loopback deck origin (DECK_ORIGIN / Card.config.deck_origin)
# Any missing or wrong gate refuses with ZERO writes.
#
# Usage, from the deck root inside the local container:
#   TRANSCRIPT_DELTA_MANIFEST=/tmp/transcript_delta_manifest.json \
#   TRANSCRIPT_EXPORT_DIR=/tmp/tdelta \
#   TRANSCRIPT_DELTA_REPORT=/tmp/delta_apply_report.json \
#     bundle exec decko runner /src/scripts/apply_transcript_delta.rb
#
# Use the ABSOLUTE script path. A relative path can load a stale copy that
# happens to sit in the runner's cwd.
#
# WHY THE BODY IS RE-RENDERED RATHER THAN EMBEDDED
#   The write set is ~314 cards and ~10MB of transcript text; embedding it
#   would make the manifest unreviewable. Instead each row pins three hashes -
#   the export file's sha256, the live content sha256 at plan time, and the
#   desired content sha256 - and this file re-renders through the planner's own
#   render_transcript_cards_from_data. A write happens only when the re-render
#   hashes to exactly the manifest's desired_hash, so the bytes written are
#   provably the bytes planned, and any drift on either side halts the run.
#
# THE MANIFEST IS AN UNTRUSTED INPUT
#   A manifest is a reviewable plan, not an authorization, and it is not
#   evidence about the deck. Every write-scope invariant below is RE-DERIVED
#   here at apply time from
#     (a) this file's own env/config - TRANSCRIPT_DELTA_PARENT,
#         TRANSCRIPT_DELTA_PROTECTED, TRANSCRIPT_FOREIGN_CORPORA, and
#     (b) live Card names and live left-id ancestry,
#   never from the manifest's own `scope` booleans. The manifest's assertions
#   are still read, but only as extra FAIL-CLOSED conditions: a manifest
#   claiming `all_rows_under_parent=false` is refused, while one claiming
#   `true` earns nothing. Without this, a stale or hand-edited manifest row
#   (for instance base_card="*all" with a matching desired_hash) could name a
#   card outside the transcript subtree and be written on the strength of its
#   own say-so.
#
# IDEMPOTENT RESUME
#   A row whose live content already hashes to desired_hash is `already_applied`
#   and is skipped, not rewritten. That makes an interrupted apply resumable
#   with the same command. A row that matches neither live_hash nor
#   desired_hash is `drift` and halts the run even in resume mode. A row whose
#   live card is no longer RawData is `type_drift` and also halts.
#
# CARDS DECKO INVENTS
#   Creating "<parent>+Series+2026-01-02" can bring more than one card into
#   existence: Decko also materialises the missing compound left card
#   "<parent>+Series" AND an empty card for each simple name part it has never
#   seen ("Series", "2026-01-02"). The simple ones have no left card at all, so
#   they are not descendants of the write parent and no ancestry check
#   describes them.
#
#   Those cards are enumerated BEFORE the first write from the rows alone
#   (apply_expected_autocreated_names), and each one that actually appears is
#   then verified individually (apply_autocreated_refusal): it must be a name
#   part a planned row needed, empty, of an empty structural type, not RawData,
#   not protected, not in a foreign corpus and not trashed. Only verified cards
#   are added to the explained card-count growth and to the act-log allow-list.
#   The invariant is an EXACT equality against that verified set - never a
#   tolerance band on a count - so an unexplained card refuses even when the
#   arithmetic happens to work out.
#
# TESTABILITY
#   With TRANSCRIPT_DELTA_APPLIER_LIB=1 this file defines its gates,
#   classifier and scope functions and then does NOTHING ELSE: no manifest is
#   read and no run happens. The offline suite loads it that way and drives the
#   real functions against a stub Card plus a mutation recorder, so the
#   decision table under test is this file's, not a copy of it.

require "json"
require "digest"
require "set"

# ------------------------------------------------------------
# Gates, read before anything else happens
# ------------------------------------------------------------
APPLY_MANIFEST_PATH = ENV.fetch("TRANSCRIPT_DELTA_MANIFEST", "")

# NOTE THE PREFIX. This file `load`s the planner for its renderer, and `load`
# evaluates the planner's top level in THIS process, redefining every constant
# it declares. The planner declares REPORT_PATH (its own, from
# TRANSCRIPT_INGEST_REPORT), so an unprefixed REPORT_PATH here would be
# silently overwritten - with nil, since this file scrubs that variable - and
# the applier would then fail to write its report in the ensure block, i.e.
# lose the evidence of whatever it just did. Every constant in this file is
# prefixed for that reason, and a collision check runs right after the load.
APPLY_REPORT_PATH = ENV.fetch("TRANSCRIPT_DELTA_REPORT",
                              "/tmp/transcript_delta_apply_report.json")

# The write gate. Exactly "1"; no truthy-spelling leniency, because every other
# spelling someone might try should fail closed rather than write.
APPLY_WRITE = ENV["TRANSCRIPT_DELTA_WRITE"] == "1"

APPLY_EXPECT_SHA     = ENV["TRANSCRIPT_DELTA_MANIFEST_SHA"].to_s
APPLY_CONFIRM        = ENV["TRANSCRIPT_DELTA_CONFIRM"].to_s
APPLY_CONFIRM_TOKEN  = "APPLY-TRANSCRIPT-DELTA-LOCAL"
APPLY_MANIFEST_VERSION = 1

# Load-only mode for the offline test suite: define everything, run nothing.
APPLY_LIB_ONLY = ENV["TRANSCRIPT_DELTA_APPLIER_LIB"] == "1"

# Where the export JSONs live in THIS process. Defaults to the manifest's
# recorded export_dir, because the planner usually ran in the same container.
APPLY_EXPORT_DIR_OVERRIDE = ENV["TRANSCRIPT_EXPORT_DIR"]

# ------------------------------------------------------------
# Write scope: configuration, NOT manifest content
# ------------------------------------------------------------
# The only subtree this file may write into. Every row's card name, every
# row's base card and every card actually written is checked against this,
# both as a name and - once a deck is reachable - as live left-id ancestry.
# The manifest must agree with it; disagreement refuses.
APPLY_PARENT_CARD = ENV.fetch("TRANSCRIPT_DELTA_PARENT", "Raw Data+transcripts")

# Cards that must never be written whatever a manifest says. Same default and
# same semicolon-separated spelling as the planner's TRANSCRIPT_DELTA_PROTECTED
# (real meeting titles contain commas). Compared through name keys.
APPLY_PROTECTED_NAMES = ENV.fetch(
  "TRANSCRIPT_DELTA_PROTECTED",
  "Raw Data+transcripts+Elowyn AI Meeting - Frag, EARTHwise, Magi+2026-03-03"
).split(";").map(&:strip).reject(&:empty?).freeze

# Corpora under the parent that a different pipeline owns. Nothing whose first
# relative name part names one of these may be written here.
APPLY_FOREIGN_CORPORA = ENV.fetch("TRANSCRIPT_FOREIGN_CORPORA", "AGI 26")
                           .split(";").map(&:strip).reject(&:empty?).freeze

# The two card-name shapes the renderer can produce for a transcript: the base
# card itself, and base+chunk-N. A row naming anything else - a sibling, a
# parent, a differently-suffixed card - is out of scope even if its hashes
# line up.
APPLY_CHUNK_SUFFIX_RE = /\Achunk[-_](\d+)\z/.freeze

# Name parts Decko treats as structural rather than as content. A leading "*"
# is a set/configuration card ("*all", "*account"), a leading "~" is an id
# reference. Neither can ever be a transcript card, so any row containing one
# is refused outright.
APPLY_RESERVED_PART_PREFIXES = %w[* ~].freeze

# Hosts that must never be reachable from an apply. Deny-list in addition to
# the loopback allow-list below, because "not obviously prod" is not the same
# as "proven local".
APPLY_FORBIDDEN_ORIGINS = %w[
  hyperon.dev
  rds.amazonaws.com
  amazonaws.com
].freeze

# The planner, loaded for its renderer and its naming/hashing functions.
APPLY_PLANNER = File.expand_path("ingest_transcripts.rb", __dir__)

APPLY_REPORT = {
  mode: (APPLY_WRITE ? "apply" : "dry_run"),
  script: "scripts/apply_transcript_delta.rb",
  started_utc: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
  manifest_path: APPLY_MANIFEST_PATH,
  parent_card: APPLY_PARENT_CARD,
  gates: {}, baseline: nil, plan_summary: {}, rows: [],
  derived_scope: {},
  creates_performed: 0, updates_performed: 0, writes_performed: 0,
  skipped_already_applied: 0, verified: 0,
  deletes_performed: 0, renames_performed: 0, trashes_performed: 0,
  preserve_checked: 0, preserve_changed: 0,
  failures: [], halted: false, halt_reason: nil
}

def die!(msg)
  APPLY_REPORT[:halted] = true
  APPLY_REPORT[:halt_reason] ||= msg
  raise msg
end

# ------------------------------------------------------------
# Load the planner WITHOUT letting it run or abort
# ------------------------------------------------------------
# ingest_transcripts.rb runs an ingest when TRANSCRIPT_INGEST=1, and aborts at
# load time if TRANSCRIPT_INGEST_DELTA is set without a dry run. Both would be
# catastrophic here (the first writes every card unconditionally), so the
# planner's own env surface is scrubbed for the duration of the load and
# restored afterwards. Nothing in this file ever sets TRANSCRIPT_INGEST=1.
def load_planner!
  saved = {}
  %w[TRANSCRIPT_INGEST TRANSCRIPT_INGEST_DELTA TRANSCRIPT_DELTA_MANIFEST
     TRANSCRIPT_INGEST_REPORT].each do |k|
    saved[k] = ENV[k]
    ENV.delete(k)
  end
  ENV["TRANSCRIPT_INGEST_DRY_RUN"] = "1"
  begin
    load APPLY_PLANNER
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end

# ============================================================
# Name and hash helpers - self-contained on purpose
# ============================================================
# These duplicate the planner's logic rather than borrowing it. The planner is
# `load`ed later in the run, so borrowing would mean this file's scope checks
# depended on code that arrives after the checks are written, and a planner
# edit could silently change what "under the parent" means. Both definitions
# are cross-checked against each other right after the load
# (apply_cross_check_planner!), so a divergence refuses instead of drifting.

def apply_name_key(full_name)
  return full_name.to_name.key if defined?(Cardname)

  full_name.to_s.split("+").map do |part|
    part.gsub(/([a-z0-9])([A-Z])/, '\1_\2')
        .downcase
        .gsub(/[^a-z0-9]+/, "_")
        .gsub(/\A_+|_+\z/, "")
  end.join("+")
end

def apply_name_parts(full_name)
  full_name.to_s.split("+")
end

# The planner's normalization is the identity function (transcript cards carry
# no per-run timestamp), so this is a plain sha256 of the content.
def apply_content_hash(content)
  Digest::SHA256.hexdigest(content.to_s)
end

def apply_raw_data_type?(type_name)
  type_name.to_s.downcase.tr(" ", "") == "rawdata"
end

def apply_reserved_name?(full_name)
  parts = apply_name_parts(full_name)
  return true if parts.empty?

  parts.any? do |part|
    stripped = part.to_s.strip
    stripped.empty? ||
      APPLY_RESERVED_PART_PREFIXES.any? { |p| stripped.start_with?(p) }
  end
end

# Strictly below the parent: same key prefix AND more name parts. Compared on
# keys, not on the display string, so "RawData+transcripts+x" and
# "Raw Data+transcripts+x" cannot disagree.
def apply_under_parent?(full_name, parent: APPLY_PARENT_CARD)
  parent_key = apply_name_key(parent)
  name_key = apply_name_key(full_name)
  return false if parent_key.empty? || name_key.empty?

  name_key.start_with?("#{parent_key}+") &&
    apply_name_parts(full_name).length > apply_name_parts(parent).length
end

def apply_left_name(full_name)
  parts = apply_name_parts(full_name)
  parts.length > 1 ? parts[0..-2].join("+") : nil
end

def apply_protected?(full_name, protected_names: APPLY_PROTECTED_NAMES)
  key = apply_name_key(full_name)
  protected_names.any? { |n| apply_name_key(n) == key }
end

# Which enumerated foreign corpus a name belongs to, by its FIRST relative
# part - the same anchoring the planner uses, so "AGI 26" deeper in a name is
# not a corpus match and a real series like "AGI Strategy Biweekly" never is.
def apply_foreign_corpus_of(full_name, parent: APPLY_PARENT_CARD,
                            corpora: APPLY_FOREIGN_CORPORA)
  relative = apply_name_parts(full_name).drop(apply_name_parts(parent).length)
  return nil if relative.empty?

  key = apply_name_key(relative.first)
  corpora.find { |c| apply_name_key(c) == key }
end

# "base" | "chunk" | nil. nil means the row names a card the renderer could
# not have produced from that base card.
def apply_row_shape(card_name, base_card)
  return nil if card_name.to_s.empty? || base_card.to_s.empty?
  return "base" if apply_name_key(card_name) == apply_name_key(base_card)

  left = apply_left_name(card_name)
  last = apply_name_parts(card_name).last.to_s
  if left && apply_name_key(left) == apply_name_key(base_card) &&
     APPLY_CHUNK_SUFFIX_RE.match?(last)
    return "chunk"
  end

  nil
end

# Ancestor names strictly between the parent and this card, i.e. the
# intermediate cards that must exist for this card to be filed where the plan
# says. Decko creates a missing left card implicitly when a "+child" is
# created, so these are enumerated up front rather than discovered as a
# surprise in the card-count invariant.
def apply_ancestor_chain(full_name, parent: APPLY_PARENT_CARD)
  parts = apply_name_parts(full_name)
  first = apply_name_parts(parent).length
  return [] if parts.length <= first

  (first...(parts.length - 1)).map { |i| parts[0..i].join("+") }
end

# ============================================================
# Derived scope: the invariants, re-computed from rows + config
# ============================================================
# Pure: no Card, no IO. Returns one entry per violation rather than raising,
# so a refusal can name every bad row instead of only the first.
def apply_scope_violations(rows, parent: APPLY_PARENT_CARD,
                           protected_names: APPLY_PROTECTED_NAMES,
                           corpora: APPLY_FOREIGN_CORPORA)
  violations = []
  seen_keys = {}

  Array(rows).each_with_index do |row, index|
    name = row["card_name"].to_s
    base = row["base_card"].to_s
    add = lambda do |reason|
      violations << { index: index, card_name: name, reason: reason }
    end

    if name.empty?
      add.call("row has no card_name")
      next
    end
    add.call("row has no base_card") if base.empty?
    add.call("card_name contains a reserved name part") if apply_reserved_name?(name)
    if !base.empty? && apply_reserved_name?(base)
      add.call("base_card contains a reserved name part")
    end
    unless apply_under_parent?(name, parent: parent)
      add.call("card_name is not a descendant of #{parent}")
    end
    if !base.empty? && !apply_under_parent?(base, parent: parent)
      add.call("base_card is not a descendant of #{parent}")
    end
    if !base.empty? && apply_row_shape(name, base).nil?
      add.call("card_name is neither base_card nor base_card+chunk-N")
    end
    if apply_protected?(name, protected_names: protected_names)
      add.call("card_name is a protected card")
    end
    corpus = apply_foreign_corpus_of(name, parent: parent, corpora: corpora)
    add.call("card_name belongs to foreign corpus #{corpus}") if corpus

    key = apply_name_key(name)
    add.call("duplicate card name key #{key}") if seen_keys[key]
    seen_keys[key] = true
  end

  violations
end

# ============================================================
# Phase-1 classifier
# ============================================================
# The single decision point for skip vs write vs halt. Exercised directly by
# the offline suite so the table under test is this one.
#
#   create, absent                        -> pending_create
#   create, present and already desired   -> already_applied   (resume)
#   create, present and something else    -> collision_create  (halt)
#   update, absent                        -> vanished_update   (halt)
#   update, live == manifest live_hash    -> pending_update
#   update, live == desired_hash          -> already_applied   (resume)
#   update, live is neither               -> drift_update      (halt)
#   any row whose live card is not RawData-> type_drift        (halt)
def apply_classify_row(action:, live_present:, live_hash:, manifest_live_hash:,
                       desired_hash:, live_type_name: nil)
  state =
    case action
    when "create"
      if !live_present then "pending_create"
      elsif live_hash == desired_hash then "already_applied"
      else "collision_create"
      end
    when "update"
      if !live_present then "vanished_update"
      elsif live_hash == manifest_live_hash then "pending_update"
      elsif live_hash == desired_hash then "already_applied"
      else "drift_update"
      end
    else
      return "unknown_action"
    end

  # A card that stopped being RawData is never safe to write through, even
  # when its content hash still matches: the type change is someone else's
  # edit and the write would silently revert part of it.
  if live_present && %w[pending_update already_applied].include?(state) &&
     !apply_raw_data_type?(live_type_name)
    state = "type_drift"
  end

  state
end

APPLY_SAFE_STATES = %w[pending_create pending_update already_applied].freeze

# ============================================================
# Read-only live helpers
# ============================================================
def apply_live_card(name)
  card = begin
    Card.fetch(name)
  rescue StandardError
    nil
  end
  return nil if card.nil? || card.trash

  card
end

def apply_live_card_by_id(id)
  return nil if id.nil?

  begin
    Card.fetch(id)
  rescue StandardError
    nil
  end
end

def apply_live_hash_of(name)
  card = apply_live_card(name)
  card && apply_content_hash(card.content.to_s)
end

# Every live, non-trashed descendant of the parent, as name key => id.
# Breadth-first over left_id, which is Decko's actual "is filed under"
# relation - the one a name string can only claim to describe.
def apply_live_descendant_ids(parent_name)
  parent = apply_live_card(parent_name)
  return nil unless parent

  found = {}
  frontier = [parent.id]
  seen = {}
  until frontier.empty?
    batch = Card.where(left_id: frontier).to_a
    frontier = []
    batch.each do |card|
      next if seen[card.id]

      seen[card.id] = true
      frontier << card.id
      next if card.trash

      found[apply_name_key(card.name.to_s)] = card.id
    end
  end
  found
end

# The live left-id chain above a card, nearest ancestor first.
def apply_live_ancestor_ids(card, limit: 32)
  ids = []
  current = card
  limit.times do
    left_id = current.respond_to?(:left_id) ? current.left_id : nil
    break if left_id.nil? || ids.include?(left_id)

    ids << left_id
    current = apply_live_card_by_id(left_id)
    break if current.nil?
  end
  ids
end

# Does this card sit under the parent according to the live deck, not
# according to its name? This is what catches a card whose name looks right
# but whose left_id points somewhere else entirely.
def apply_live_under_parent?(card, parent_id)
  return false if card.nil? || parent_id.nil?

  apply_live_ancestor_ids(card).include?(parent_id)
end

# Live-side scope check. descendant_ids is the map above; a nil entry means
# the card is not currently filed under the parent.
def apply_live_scope_violations(rows, descendant_ids, parent: APPLY_PARENT_CARD)
  violations = []
  Array(rows).each_with_index do |row, index|
    name = row["card_name"].to_s
    key = apply_name_key(name)
    next unless row["action"] == "update"

    next if descendant_ids.key?(key)

    violations << { index: index, card_name: name,
                    reason: "update target is not a live descendant of #{parent}" }
  end
  violations
end

# Intermediate cards that do not exist live and are not themselves rows -
# the ones Decko would create implicitly to file a planned create. Returned
# sorted, shallowest first, so the report reads as a tree.
def apply_implicit_ancestors(rows, descendant_ids, parent: APPLY_PARENT_CARD)
  planned = Array(rows).map { |r| apply_name_key(r["card_name"].to_s) }.to_set
  pending = {}
  Array(rows).each do |row|
    next unless row["action"] == "create"

    apply_ancestor_chain(row["card_name"].to_s, parent: parent).each do |ancestor|
      key = apply_name_key(ancestor)
      next if descendant_ids.key?(key) || planned.include?(key)

      pending[key] = ancestor
    end
  end
  pending.values.sort_by { |n| [apply_name_parts(n).length, n] }
end

# ------------------------------------------------------------
# Cards Decko invents on this applier's behalf
# ------------------------------------------------------------
# A Decko compound card is filed under BOTH of its name parts, and a missing
# part is created as an empty structural card rather than refused. Creating
# "<parent>+Standup+2026-01-02" therefore brings up to three cards into
# existence: the row itself, the compound left card "<parent>+Standup", and
# the SIMPLE cards "Standup" and "2026-01-02".
#
# The simple ones are not descendants of the write parent - a simple card has
# no left card at all - so none of the ancestry gates above can describe them,
# and the aggregate card-count invariant used to read them as unexplained
# growth. They are enumerated here, up front and from the rows alone, so the
# invariant can check each one on its own properties instead of tolerating a
# count.
#
# The empty structural types Decko may use for a name part it invents. RawData
# is deliberately absent: a transcript card is never a side effect.
APPLY_AUTOCREATED_TYPES = ENV.fetch(
  "TRANSCRIPT_DELTA_AUTOCREATED_TYPES", "Basic;RichText"
).split(";").map { |t| t.strip.downcase.tr(" ", "") }.reject(&:empty?).freeze

def apply_autocreatable_type?(type_name)
  APPLY_AUTOCREATED_TYPES.include?(type_name.to_s.downcase.tr(" ", ""))
end

# Every name Decko could legitimately invent to file these rows: the missing
# compound ancestors, plus every simple name part the rows and those ancestors
# are built from, minus the parts the parent card itself is built from (those
# must already exist, since the parent does). Returned sorted, simple names
# first, so the report reads as a tree.
def apply_expected_autocreated_names(rows, implicit_ancestors,
                                     parent: APPLY_PARENT_CARD)
  planned = Array(rows).map { |r| r["card_name"].to_s }.reject(&:empty?)
  compound = Array(implicit_ancestors).map(&:to_s)
  parent_part_keys = apply_name_parts(parent).map { |p| apply_name_key(p) }.to_set

  simple = {}
  (planned + compound).each do |full|
    apply_name_parts(full).each do |part|
      key = apply_name_key(part)
      next if key.empty? || parent_part_keys.include?(key)

      simple[key] ||= part
    end
  end

  (simple.values + compound).uniq { |n| apply_name_key(n) }
                            .sort_by { |n| [apply_name_parts(n).length, n] }
end

# Pure: why this card may NOT be treated as a Decko-invented name part, or nil
# if it may. Every condition is a property of the card itself - its content,
# its type, its name, the plan that was running - never a count and never the
# manifest's say-so.
def apply_autocreated_refusal(name:, content:, type_name:, trash:,
                              expected_names:,
                              protected_names: APPLY_PROTECTED_NAMES,
                              corpora: APPLY_FOREIGN_CORPORA,
                              parent: APPLY_PARENT_CARD)
  key = apply_name_key(name.to_s)
  return "has no usable name" if key.empty?
  return "is a reserved/structural name" if apply_reserved_name?(name.to_s)

  unless Array(expected_names).any? { |n| apply_name_key(n) == key }
    return "is not a name part any planned row needed"
  end
  return "is trashed" if trash
  unless content.to_s.empty?
    return "has #{content.to_s.length} char(s) of content, so it is not an " \
           "empty card Decko invented"
  end
  return "is RawData, which this applier only ever writes as a planned row" if
    apply_raw_data_type?(type_name)
  unless apply_autocreatable_type?(type_name)
    return "has type #{type_name.inspect}, which is not an empty structural type"
  end
  return "is a protected card" if
    apply_protected?(name.to_s, protected_names: protected_names)

  # Foreign-corpus check, both ways round: as a descendant name ("<parent>+AGI
  # 26+...") and as a bare part that simply IS a corpus root.
  corpus = apply_foreign_corpus_of(name.to_s, parent: parent, corpora: corpora) ||
           corpora.find { |c| apply_name_key(c) == key }
  return "belongs to foreign corpus #{corpus}" if corpus

  nil
end

# ============================================================
# Gates
# ============================================================
def apply_gate_origin!(origin)
  APPLY_REPORT[:deck_origin] = origin
  forbidden = APPLY_FORBIDDEN_ORIGINS.select { |m| origin.include?(m) }
  die! "refusing: deck origin names a forbidden host (#{forbidden.join(', ')})" if
    forbidden.any?
  unless origin.include?("127.0.0.1") || origin.include?("localhost") ||
         origin.include?("[::1]")
    die! "refusing: deck origin #{origin.inspect} is not loopback"
  end
  APPLY_REPORT[:gates][:loopback_origin] = true
end

def apply_gate_db_host!
  return unless defined?(ActiveRecord::Base)

  # The DB host is the real discriminator: dev and prod can share an origin
  # string but never a database host. Refuse any non-local-looking host.
  db_host = begin
    ActiveRecord::Base.connection_db_config.configuration_hash[:host].to_s
  rescue StandardError
    ""
  end
  bad_db = APPLY_FORBIDDEN_ORIGINS.select { |m| db_host.include?(m) }
  die! "refusing: database host names a forbidden host" if bad_db.any?
  APPLY_REPORT[:gates][:db_host_local] = true
end

def apply_gate_manifest_identity!(manifest)
  die! "wrong manifest_version #{manifest['manifest_version'].inspect}" unless
    manifest["manifest_version"] == APPLY_MANIFEST_VERSION
  die! "manifest is not local-only" unless
    manifest["target_environment"] == "local_loopback_only"
  die! "manifest declares production contact" if manifest["production_contacted"]
  die! "manifest confirm token does not match this applier" unless
    manifest["confirm_token"] == APPLY_CONFIRM_TOKEN
  die! "manifest has no live baseline - nothing was compared" unless
    manifest["baseline_available"] && manifest["baseline"] == "live-content-hash"
  die! "manifest hash algorithm is not sha256" unless
    manifest["hash_algorithm"] == "sha256"

  # The manifest must target the subtree THIS file is configured for. Checked
  # against the applier's own constant, not against the planner's (which is
  # only loaded later, and only for rendering).
  die! "manifest parent_card #{manifest['parent_card'].inspect} is not the " \
       "configured write parent #{APPLY_PARENT_CARD.inspect}" unless
    apply_name_key(manifest["parent_card"].to_s) == apply_name_key(APPLY_PARENT_CARD)

  %w[deletes_in_scope trashes_in_scope renames_in_scope
     orphan_cleanup_in_scope stale_chunk_prunes_in_scope].each do |k|
    die! "manifest declares #{k}=#{manifest[k].inspect}" unless manifest[k].to_i.zero?
  end
  die! "manifest claims a destructive path exists" if manifest["destructive_path_exists"]
end

# Counter and assertion checks on the manifest's own claims. These are
# FAIL-CLOSED ONLY: a false assertion refuses, a true one proves nothing and
# is re-derived in apply_gate_derived_scope! below.
def apply_gate_manifest_claims!(manifest, rows)
  write_set = manifest["write_set"] || {}
  die! "write_set.total #{write_set['total'].inspect} != #{rows.length} rows" unless
    write_set["total"] == rows.length
  die! "write_set.creates mismatch" unless
    write_set["creates"] == rows.count { |r| r["action"] == "create" }
  die! "write_set.updates mismatch" unless
    write_set["updates"] == rows.count { |r| r["action"] == "update" }

  scope = manifest["scope"] || {}
  die! "manifest allows actions beyond create/update" unless
    scope["actions_allowed"] == %w[create update]
  %w[all_rows_under_parent unique_card_names every_row_has_desired_hash
     every_update_has_live_hash every_create_has_no_live_hash].each do |k|
    die! "manifest scope assertion #{k} is not true" unless scope[k] == true
  end
  die! "manifest puts protected card(s) in the write set: " \
       "#{scope['protected_rows_in_write_set'].inspect}" unless
    Array(scope["protected_rows_in_write_set"]).empty?
  die! "manifest puts foreign-corpus card(s) in the write set: " \
       "#{scope['foreign_corpus_rows_in_write_set'].inspect}" unless
    Array(scope["foreign_corpus_rows_in_write_set"]).empty?

  blocking = (manifest["blocking"] || {}).reject { |_k, v| v.nil? || v.to_i.zero? }
  die! "manifest reports blockers: #{blocking.inspect}" if blocking.any?
end

def apply_gate_rows_static!(manifest, rows)
  preserve = manifest["preserve"] || {}
  manifest_protected = Array(preserve["protected_names"])
  stale_chunks = Array(preserve["stale_chunk_cards"])

  rows.each do |r|
    nm = r["card_name"].to_s
    die! "row has no card_name" if nm.empty?
    die! "row action #{r['action'].inspect} not in create/update" unless
      %w[create update].include?(r["action"])
    die! "row #{nm} has no desired_hash" if r["desired_hash"].to_s.empty?
    die! "row #{nm} desired_hash is not a sha256" unless
      r["desired_hash"].to_s.match?(/\A[0-9a-f]{64}\z/)
    die! "row #{nm} source_sha256 is not a sha256" unless
      r["source_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
    die! "row #{nm} has an unexpected type_code" unless r["type_code"] == "raw_data"
    if r["action"] == "update"
      die! "update row #{nm} has no live_hash" if r["live_hash"].to_s.empty?
      die! "update row #{nm} live_hash equals desired_hash (would be a no-op)" if
        r["live_hash"] == r["desired_hash"]
    else
      die! "create row #{nm} carries a live_hash" unless r["live_hash"].nil?
    end
    # The manifest's own preserve list, in addition to this file's configured
    # protected names (re-derived in apply_gate_derived_scope!).
    die! "row #{nm} is a protected card" if
      manifest_protected.any? { |n| apply_name_key(n) == apply_name_key(nm) }
    die! "row #{nm} is in the preserve set" if
      stale_chunks.any? { |n| apply_name_key(n) == apply_name_key(nm) }
  end
end

# The invariants that matter, derived here rather than read from the manifest.
def apply_gate_derived_scope!(rows)
  violations = apply_scope_violations(rows)
  APPLY_REPORT[:derived_scope] = {
    parent_card: APPLY_PARENT_CARD,
    protected_names: APPLY_PROTECTED_NAMES,
    foreign_corpora: APPLY_FOREIGN_CORPORA,
    rows_checked: rows.length,
    violations: violations.first(20),
    violation_count: violations.length,
    source: "re-derived from env config and row names, not from manifest.scope"
  }
  die! "#{violations.length} row(s) fail this applier's own write-scope " \
       "check: #{violations.first(5).map { |v| [v[:card_name], v[:reason]] }.inspect}" if
    violations.any?
  APPLY_REPORT[:gates][:derived_scope_valid] = true
end

def apply_gate_write_authorization!(actual_sha)
  APPLY_REPORT[:gates][:write_requested] = APPLY_WRITE
  return unless APPLY_WRITE

  die! "TRANSCRIPT_DELTA_MANIFEST_SHA is required for a write" if
    APPLY_EXPECT_SHA.empty?
  die! "TRANSCRIPT_DELTA_MANIFEST_SHA does not match the manifest on disk" unless
    APPLY_EXPECT_SHA == actual_sha
  die! "TRANSCRIPT_DELTA_CONFIRM is required for a write" if APPLY_CONFIRM.empty?
  die! "TRANSCRIPT_DELTA_CONFIRM token is wrong" unless APPLY_CONFIRM == APPLY_CONFIRM_TOKEN
  APPLY_REPORT[:gates][:manifest_sha_matched] = true
  APPLY_REPORT[:gates][:confirm_token_matched] = true
end

# After the planner load: prove the two files still agree about the things
# this file re-implemented, and about the subtree being written.
def apply_cross_check_planner!(manifest)
  die! "planner did not provide render_transcript_cards_from_data" unless
    respond_to?(:render_transcript_cards_from_data, true)
  die! "the planner's confirm token disagrees with this applier" unless
    DELTA_CONFIRM_TOKEN == APPLY_CONFIRM_TOKEN
  die! "planner parent card #{PARENT_CARD.inspect} disagrees with the " \
       "configured write parent #{APPLY_PARENT_CARD.inspect}" unless
    apply_name_key(PARENT_CARD) == apply_name_key(APPLY_PARENT_CARD)
  die! "planner parent card changed" unless PARENT_CARD == manifest["parent_card"]
  die! "planner MAX_CARD_CHARS changed" unless MAX_CARD_CHARS == manifest["max_card_chars"]

  sample = "a\nb\r\n  c  \n"
  die! "this applier and the planner no longer hash content the same way" unless
    apply_content_hash(sample) == content_hash(sample)
  die! "this applier and the planner no longer agree on name keys" unless
    apply_name_key(APPLY_PARENT_CARD) == name_key(APPLY_PARENT_CARD)
end

# ============================================================
# Run
# ============================================================
unless APPLY_LIB_ONLY
  begin
    # ---- gate 0: a manifest path at all ----------------------------------
    die! "TRANSCRIPT_DELTA_MANIFEST is required" if APPLY_MANIFEST_PATH.empty?
    die! "manifest not found: #{APPLY_MANIFEST_PATH}" unless File.file?(APPLY_MANIFEST_PATH)

    raw_manifest = File.binread(APPLY_MANIFEST_PATH)
    actual_sha = Digest::SHA256.hexdigest(raw_manifest)
    APPLY_REPORT[:manifest_sha256] = actual_sha
    manifest = JSON.parse(raw_manifest)

    # ---- gate 1: loopback-only target ------------------------------------
    # Evaluated before the manifest's own assertions so that pointing this file
    # at production refuses even with a perfectly valid manifest.
    apply_gate_origin!((ENV["DECK_ORIGIN"] ||
                        (defined?(Card) ? Card.config.try(:deck_origin) : nil)).to_s)
    apply_gate_db_host!

    # ---- gate 2: manifest identity and declared scope --------------------
    apply_gate_manifest_identity!(manifest)

    rows = manifest["rows"]
    die! "manifest has no rows" unless rows.is_a?(Array) && rows.any?

    apply_gate_manifest_claims!(manifest, rows)

    # ---- gate 3: per-row static validation (no DB, no files yet) ---------
    preserve = manifest["preserve"] || {}
    # Union of what the manifest says to preserve and what this file is
    # configured to protect: a manifest that forgot a protected card cannot
    # shrink the set that gets verified afterwards.
    preserve_names = (Array(preserve["stale_chunk_cards"]) +
                      Array(preserve["protected_names"]) +
                      APPLY_PROTECTED_NAMES).uniq

    apply_gate_rows_static!(manifest, rows)
    APPLY_REPORT[:gates][:manifest_static_valid] = true

    # ---- gate 3b: the same invariants, DERIVED not read ------------------
    apply_gate_derived_scope!(rows)

    # ---- gate 4: write authorization ------------------------------------
    # Dry run needs none of this; a write needs all of it.
    apply_gate_write_authorization!(actual_sha)

    # ---- the renderer ----------------------------------------------------
    # Snapshot the values the load could clobber, then prove it did not. Ruby
    # prints a warning on constant reassignment but does not raise, so a silent
    # collision here would be a lost report or a wrong gate rather than an error.
    gate_fingerprint = [APPLY_WRITE, APPLY_REPORT_PATH, APPLY_CONFIRM_TOKEN,
                        APPLY_MANIFEST_PATH, APPLY_MANIFEST_VERSION,
                        APPLY_PARENT_CARD, APPLY_PROTECTED_NAMES]
    load_planner!
    die! "loading the planner changed this applier's gate constants" unless
      gate_fingerprint == [APPLY_WRITE, APPLY_REPORT_PATH, APPLY_CONFIRM_TOKEN,
                           APPLY_MANIFEST_PATH, APPLY_MANIFEST_VERSION,
                           APPLY_PARENT_CARD, APPLY_PROTECTED_NAMES]
    apply_cross_check_planner!(manifest)

    export_dir = APPLY_EXPORT_DIR_OVERRIDE || manifest["export_dir"]
    die! "export dir not found: #{export_dir}" unless Dir.exist?(export_dir.to_s)
    APPLY_REPORT[:export_dir] = export_dir

    # ---- re-render every row and prove it matches the manifest ----------
    # Done for ALL rows before any write: a single stale export or changed
    # renderer must halt the run while zero cards have been touched.
    rendered_by_name = {}
    source_checked = {}

    rows.group_by { |r| r["source_basename"] }.each do |basename, group|
      path = File.join(export_dir, basename)
      die! "export file missing for #{group.length} row(s): #{basename}" unless
        File.file?(path)
      sha = Digest::SHA256.hexdigest(File.binread(path))
      expected = group.map { |r| r["source_sha256"] }.uniq
      die! "manifest disagrees with itself on #{basename}" unless expected.length == 1
      die! "export file changed since planning: #{basename}" unless sha == expected.first
      source_checked[basename] = sha

      base = group.map { |r| r["base_card"] }.uniq
      die! "manifest disagrees on base card for #{basename}" unless base.length == 1

      render_transcript_cards_from_data(JSON.parse(File.read(path)), base.first)
        .each { |c| rendered_by_name[c[:name]] = c[:content] }
    end
    APPLY_REPORT[:export_files_verified] = source_checked.length

    rows.each do |r|
      body = rendered_by_name[r["card_name"]]
      die! "re-render produced no card named #{r['card_name']}" if body.nil?
      got = apply_content_hash(body)
      die! "re-render hash mismatch for #{r['card_name']}: the renderer or the " \
           "export has changed since this manifest was planned" unless
        got == r["desired_hash"]
      die! "re-render length mismatch for #{r['card_name']}" unless
        body.length == r["desired_chars"]
    end
    APPLY_REPORT[:gates][:rerender_matches_manifest] = true

    # ---- gate 5: a live Card API must actually be reachable -------------
    # Outside a Decko runner there is no deck to compare against, so every row
    # would look like a pending create and the preserve set would trivially
    # verify. Refuse rather than produce a reassuring report about nothing.
    unless defined?(Card) && defined?(Card::Auth)
      die! "no Card API in this process: run it under bundle exec decko " \
           "runner with an absolute script path. Nothing was read or written."
    end
    APPLY_REPORT[:gates][:card_api_available] = true

    # ------------------------------------------------------------
    # Live phases
    # ------------------------------------------------------------
    Card::Auth.as_bot do
      cards_live_before = Card.where(trash: false).count
      acts_before       = Card::Act.count
      trash_before      = Card.where(trash: true).count
      max_act_before    = begin
        Card::Act.maximum(:id).to_i
      rescue StandardError
        nil
      end
      APPLY_REPORT[:baseline] = { cards_live: cards_live_before, acts: acts_before,
                            trashed: trash_before, max_act_id: max_act_before }

      # ---- gate 6: the live write target, re-derived -------------------
      # Name-level scope passed in gate 3b. This is the deck-level version of
      # the same question: the parent must exist, and every update target must
      # actually be filed under it by left_id.
      parent_card = apply_live_card(APPLY_PARENT_CARD)
      die! "the configured write parent #{APPLY_PARENT_CARD.inspect} does not " \
           "exist live - refusing to create it or to write beside it" if parent_card.nil?
      descendant_ids = apply_live_descendant_ids(APPLY_PARENT_CARD) || {}
      live_violations = apply_live_scope_violations(rows, descendant_ids)
      implicit_ancestors = apply_implicit_ancestors(rows, descendant_ids)
      bad_implicit = implicit_ancestors.reject do |n|
        apply_under_parent?(n) && !apply_reserved_name?(n)
      end

      # Every name Decko may invent for these rows, enumerated BEFORE the
      # first write so the post-write invariant checks an expectation rather
      # than rationalising whatever it finds. Snapshot which of them already
      # exist, so "this card appeared during the apply" is a fact rather than
      # an inference.
      expected_autocreated = apply_expected_autocreated_names(rows,
                                                              implicit_ancestors)
      autocreatable_absent = expected_autocreated.reject { |n| apply_live_card(n) }

      APPLY_REPORT[:derived_scope][:parent_card_id] = parent_card.id
      APPLY_REPORT[:derived_scope][:live_descendants] = descendant_ids.length
      APPLY_REPORT[:derived_scope][:live_violations] = live_violations.first(20)
      APPLY_REPORT[:derived_scope][:live_violation_count] = live_violations.length
      APPLY_REPORT[:derived_scope][:expected_implicit_ancestors] = implicit_ancestors
      APPLY_REPORT[:derived_scope][:expected_autocreated_names] = expected_autocreated
      APPLY_REPORT[:derived_scope][:expected_autocreated_absent] =
        autocreatable_absent.length

      die! "#{live_violations.length} row(s) name a card that is not live-filed " \
           "under #{APPLY_PARENT_CARD}: " \
           "#{live_violations.first(5).map { |v| v[:card_name] }.inspect}" if
        live_violations.any?
      die! "implicit ancestor(s) outside the write scope: #{bad_implicit.inspect}" if
        bad_implicit.any?
      APPLY_REPORT[:gates][:live_scope_valid] = true

      # ---- preserve set: capture the before image ----------------------
      # Captured BEFORE the first write and re-read after the last, so
      # "nothing else moved" is evidence rather than an assurance.
      preserve_before = preserve_names.to_h do |nm|
        c = apply_live_card(nm)
        [nm, c ? { id: c.id, hash: apply_content_hash(c.content.to_s),
                   chars: c.content.to_s.length } : nil]
      end
      APPLY_REPORT[:preserve_checked] = preserve_before.length

      # ---- phase 1: read-only sweep of every row (all-or-nothing) ------
      plan = rows.map do |r|
        nm = r["card_name"]
        card = apply_live_card(nm)
        live = card && apply_content_hash(card.content.to_s)

        state = apply_classify_row(
          action: r["action"], live_present: !card.nil?, live_hash: live,
          manifest_live_hash: r["live_hash"], desired_hash: r["desired_hash"],
          live_type_name: card&.type_name
        )

        { card_name: nm, action: r["action"], state: state,
          card_id: card&.id, live_hash: live,
          manifest_live_hash: r["live_hash"], desired_hash: r["desired_hash"] }
      end

      safe_states = %w[pending_create pending_update already_applied].freeze
      die! "the safe-state list drifted from the classifier" unless
        safe_states == APPLY_SAFE_STATES
      unsafe = plan.reject { |p| safe_states.include?(p[:state]) }

      APPLY_REPORT[:plan_summary] = {
        total: plan.length,
        pending_create: plan.count { |p| p[:state] == "pending_create" },
        pending_update: plan.count { |p| p[:state] == "pending_update" },
        already_applied: plan.count { |p| p[:state] == "already_applied" },
        unsafe: unsafe.length,
        unsafe_by_state: unsafe.group_by { |p| p[:state] }.transform_values(&:length)
      }

      die! "phase-1 sweep found #{unsafe.length} unsafe row(s): " \
           "#{unsafe.first(10).map { |u| [u[:card_name], u[:state]] }.inspect}" if
        unsafe.any?

      unless APPLY_WRITE
        puts "DRY RUN (no write gate set). ZERO writes performed."
        puts "  write parent:     #{APPLY_PARENT_CARD} (id #{parent_card.id})"
        puts "  would create:     #{APPLY_REPORT[:plan_summary][:pending_create]}"
        puts "  would update:     #{APPLY_REPORT[:plan_summary][:pending_update]}"
        puts "  already applied:  #{APPLY_REPORT[:plan_summary][:already_applied]}"
        puts "  unsafe:           #{APPLY_REPORT[:plan_summary][:unsafe]}"
        puts "  implicit parents: #{implicit_ancestors.length}"
        puts "  name parts Decko may invent: #{autocreatable_absent.length} " \
             "of #{expected_autocreated.length} expected"
        puts "  preserve set read-only checked: #{preserve_before.length} card(s)"
        APPLY_REPORT[:rows] = plan
        next
      end

      # ---- phase 2: one row at a time, re-read, write, read back -------
      # Shallowest names first, so an index card is created before its chunk
      # cards and Decko is never asked to invent a left card mid-run.
      written_ids = []
      ordered_rows = rows.sort_by do |r|
        [apply_name_parts(r["card_name"]).length, r["card_name"].to_s]
      end

      ordered_rows.each do |r|
        nm = r["card_name"]
        body = rendered_by_name[nm]
        entry = { card_name: nm, action: r["action"] }

        # Per-row re-derivation of the scope checks. Gate 3b/6 already passed
        # for the whole set; repeating it here means no single row can be
        # written on the strength of a set-level check that ran minutes ago.
        die! "pre-write scope: #{nm} is not inside #{APPLY_PARENT_CARD}" unless
          apply_under_parent?(nm) && !apply_reserved_name?(nm)
        die! "pre-write scope: #{nm} is protected" if apply_protected?(nm)
        die! "pre-write scope: #{nm} is in a foreign corpus" if
          apply_foreign_corpus_of(nm)

        # immediate pre-write re-read: the phase-1 state is seconds old, and a
        # resume may have already applied this row.
        card = apply_live_card(nm)
        live = card && apply_content_hash(card.content.to_s)

        if live == r["desired_hash"]
          entry[:result] = "skip_already_applied"
          APPLY_REPORT[:skipped_already_applied] += 1
          APPLY_REPORT[:rows] << entry
          next
        end

        if r["action"] == "create"
          die! "pre-write: #{nm} already exists with unexpected content" unless card.nil?
          Card.create!(name: nm, type_code: :raw_data, content: body)
          APPLY_REPORT[:creates_performed] += 1
          APPLY_REPORT[:writes_performed] += 1
          entry[:result] = "created"
        else
          die! "pre-write: #{nm} vanished" if card.nil?
          die! "pre-write: #{nm} live hash drifted from the manifest" unless
            live == r["live_hash"]
          die! "pre-write: #{nm} is no longer filed under #{APPLY_PARENT_CARD}" unless
            apply_live_under_parent?(card, parent_card.id)
          card.update!(content: body)
          APPLY_REPORT[:updates_performed] += 1
          APPLY_REPORT[:writes_performed] += 1
          entry[:result] = "updated"
        end

        # ---- per-row readback -----------------------------------------
        back = apply_live_card(nm)
        die! "post-write: #{nm} is absent" if back.nil?
        got = apply_content_hash(back.content.to_s)
        die! "post-write: #{nm} content hash is #{got[0, 12]}, expected " \
             "#{r['desired_hash'][0, 12]}" unless got == r["desired_hash"]
        die! "post-write: #{nm} char count mismatch" unless
          back.content.to_s.length == r["desired_chars"]
        die! "post-write: #{nm} is not RawData" unless
          apply_raw_data_type?(back.type_name)
        die! "post-write: #{nm} is trashed" if back.trash
        # Where the card actually landed, by left_id rather than by name.
        die! "post-write: #{nm} is not filed under #{APPLY_PARENT_CARD}" unless
          apply_live_under_parent?(back, parent_card.id)

        written_ids << back.id
        entry[:card_id] = back.id
        entry[:post_hash] = got
        entry[:post_chars] = back.content.to_s.length
        APPLY_REPORT[:verified] += 1
        APPLY_REPORT[:rows] << entry
      end

      # ---- phase 3: aggregate invariants ------------------------------
      cards_after = Card.where(trash: false).count
      trash_after = Card.where(trash: true).count
      acts_after  = Card::Act.count

      die! "cards were trashed during apply (#{trash_before} -> #{trash_after})" unless
        trash_after == trash_before

      # Decko files a "+child" under a left card it creates implicitly when
      # that left card is missing, AND creates an empty card for each simple
      # name part it has never seen. Both are side effects of a planned
      # create, so the live count may legitimately grow by them - but each one
      # is verified on its own properties (expected name part, empty, a
      # structural type, not protected, not foreign, not trashed) rather than
      # waved through by a count.
      autocreated_verified = []
      autocreated_refused = []
      autocreatable_absent.each do |nm|
        card = apply_live_card(nm)
        next if card.nil? # Decko did not need to invent it after all

        reason = apply_autocreated_refusal(
          name: nm, content: card.content.to_s, type_name: card.type_name,
          trash: card.trash, expected_names: expected_autocreated
        )
        if reason
          autocreated_refused << { card_name: nm, card_id: card.id, reason: reason }
        else
          autocreated_verified << { card_name: nm, card_id: card.id }
        end
      end
      APPLY_REPORT[:autocreated] = {
        expected: expected_autocreated.length,
        absent_before: autocreatable_absent.length,
        verified: autocreated_verified.length,
        refused: autocreated_refused.first(20),
        names: autocreated_verified.map { |a| a[:card_name] }
      }
      die! "#{autocreated_refused.length} card(s) appeared during this apply " \
           "that are not empty name parts Decko invented: " \
           "#{autocreated_refused.first(5).map { |a| [a[:card_name], a[:reason]] }.inspect}" if
        autocreated_refused.any?

      autocreated_ids = autocreated_verified.map { |a| a[:card_id] }
      created_ancestors = autocreated_verified.map { |a| a[:card_name] }
                                              .select { |n| apply_under_parent?(n) }
      card_growth = cards_after - cards_live_before
      explained = APPLY_REPORT[:creates_performed] + autocreated_verified.length
      die! "live card count moved by #{card_growth}, but only " \
           "#{APPLY_REPORT[:creates_performed]} create(s) were performed plus " \
           "#{autocreated_verified.length} verified empty name part(s) Decko " \
           "invented (#{explained} explained)" unless card_growth == explained
      die! "this applier performed a delete/rename/trash" unless
        APPLY_REPORT[:deletes_performed].zero? && APPLY_REPORT[:renames_performed].zero? &&
        APPLY_REPORT[:trashes_performed].zero?

      # ---- which cards did the deck itself record as changed? ----------
      # The counters above are this file's own bookkeeping. The act log is the
      # deck's, so it is the one that can catch a write nobody here counted.
      act_audit = { status: "unavailable" }
      if max_act_before
        begin
          new_acts = Card::Act.where(id: (max_act_before + 1)..).to_a
          touched = new_acts.flat_map do |a|
            a.respond_to?(:actions) ? a.actions.map(&:card_id) : []
          end.compact.uniq
          allowed = (written_ids + autocreated_ids).uniq
          unexpected = touched - allowed
          act_audit = { status: "checked", new_acts: new_acts.length,
                        cards_touched: touched.length,
                        autocreated_card_ids: autocreated_ids.first(20),
                        unexpected_card_ids: unexpected.first(20) }
          die! "the deck recorded #{unexpected.length} change(s) to card(s) this " \
               "apply never planned: #{unexpected.first(10).inspect}" if unexpected.any?
        rescue StandardError => e
          act_audit = { status: "error", error: e.class.to_s }
        end
      end
      APPLY_REPORT[:act_audit] = act_audit

      # the preserve set must be byte-identical
      changed = []
      preserve_before.each do |nm, before|
        c = apply_live_card(nm)
        after = c ? { id: c.id, hash: apply_content_hash(c.content.to_s),
                      chars: c.content.to_s.length } : nil
        changed << nm unless after == before
      end
      APPLY_REPORT[:preserve_changed] = changed.length
      die! "preserve-set card(s) changed: #{changed.first(10).inspect}" if changed.any?

      APPLY_REPORT[:final] = {
        cards_live: cards_after,
        cards_live_delta: card_growth,
        implicit_parents_created: created_ancestors,
        autocreated_name_parts: autocreated_verified.length,
        acts: acts_after, acts_delta: acts_after - acts_before,
        trashed: trash_after, trashed_delta: trash_after - trash_before,
        preserve_set_unchanged: changed.empty?
      }
    end
  rescue StandardError => e
    APPLY_REPORT[:failures] << { class: e.class.to_s, message: e.message[0, 500] }
    APPLY_REPORT[:halted] = true
    APPLY_REPORT[:halt_reason] ||= e.message[0, 500]
    puts "REFUSED/HALTED: #{e.class}: #{e.message[0, 300]}"
  ensure
    APPLY_REPORT[:finished_utc] = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    begin
      File.write(APPLY_REPORT_PATH, JSON.pretty_generate(APPLY_REPORT))
      puts "report: #{APPLY_REPORT_PATH}"
    rescue StandardError => e
      puts "could not write report: #{e.class}"
    end
    puts "mode=#{APPLY_REPORT[:mode]} creates=#{APPLY_REPORT[:creates_performed]} " \
         "updates=#{APPLY_REPORT[:updates_performed]} " \
         "skipped=#{APPLY_REPORT[:skipped_already_applied]} " \
         "verified=#{APPLY_REPORT[:verified]} halted=#{APPLY_REPORT[:halted]} " \
         "#{APPLY_REPORT[:halt_reason]}"
    # A refusal must not look like a success to a wrapper.
    exit(1) if APPLY_REPORT[:halted]
  end
end
