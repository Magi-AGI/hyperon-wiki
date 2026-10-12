#!/usr/bin/env ruby
# Ingest transcript exports into the Hyperon Wiki as RawData cards.
#
# Reads JSON exports produced by export_transcripts.py (Fireflies), the Otter
# export converter, or the Read.ai report parser, and creates RawData cards in
# the Decko database with the full transcript text.
#
# Run via:
#   cat scripts/ingest_transcripts.rb | ssh -T -i <ssh-key-path> <ssh-user>@<wiki-host> \
#     'export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH" && eval "$(rbenv init -)" && \
#      cd <deck-root> && set -a && source .env.production && set +a && \
#      TRANSCRIPT_INGEST=1 RAILS_ENV=production bundle exec decko runner -'
#
# Or copy to server and run:
#   TRANSCRIPT_INGEST=1 RAILS_ENV=production bundle exec decko runner scripts/ingest_transcripts.rb
#
# TRANSCRIPT_INGEST=1 is required under `decko runner`: loading this file must
# never write cards, so the runner has to opt in explicitly. Running the file
# directly (`ruby scripts/ingest_transcripts.rb`) does not need it.
#
# DRY RUN (no database writes at all):
#   TRANSCRIPT_INGEST=1 TRANSCRIPT_INGEST_DRY_RUN=1 \
#     TRANSCRIPT_INGEST_REPORT=/tmp/transcript_plan.json \
#     bundle exec decko runner scripts/ingest_transcripts.rb
#
# DELTA PLANNER (report only, refuses to run with writes enabled):
#   TRANSCRIPT_INGEST=1 TRANSCRIPT_INGEST_DRY_RUN=1 TRANSCRIPT_INGEST_DELTA=1 \
#     TRANSCRIPT_INGEST_REPORT=/tmp/transcript_delta.json \
#     bundle exec decko runner scripts/ingest_transcripts.rb
#
#   Delta mode hashes each rendered card and compares it against the live
#   card's stored content, classifying it as skip-unchanged / update / create.
#   Unlike the Mattermost exports, a transcript card carries NO per-run export
#   timestamp, so the hash needs no normalization - the rendered content is a
#   pure function of the exported transcript. test_ingest_transcripts_delta.rb
#   guards that property, because adding a timestamp to the header would make
#   every card look dirty on every run.
#
#   There is deliberately NO delta write path: setting
#   TRANSCRIPT_INGEST_DELTA=1 without TRANSCRIPT_INGEST_DRY_RUN=1 aborts before
#   any database access.
#
#   Delta mode additionally reports, without ever deleting or re-filing:
#     - orphaned live cards, labelled (stale_chunk, superseded_by_rename,
#       relabeled_transcript, nesting_stub, vanished_transcript, ...)
#     - per-transcript chunk changes, naming the exact stale and new chunk
#       cards, so a transcript that now needs fewer chunks is explicit
#     - a name-binding manifest: which live card each export binds to
#     - report["write_readiness"], summarising what still blocks a write mode
#
#   Stale chunk cards (the shrink case) are PRESERVED by default; see
#   TRANSCRIPT_KEEP_STALE_CHUNKS below. Under the default keep policy a
#   shrink is reported but does not block a write mode.
#
# Prerequisites:
#   - Transcript JSON exports in EXPORT_DIR (produced by export_transcripts.py)
#   - The RawData cardtype must exist on the wiki

require 'json'
require 'digest'
require 'set'

# ============================================================
# Configuration
# ============================================================

EXPORT_DIR = ENV.fetch("TRANSCRIPT_EXPORT_DIR",
  File.expand_path("~/transcript_exports/latest"))

# Display spelling of the parent. The deck stores this branch as
# "RawData+transcripts" (the docs' spelling) while this constant uses
# "Raw Data+transcripts"; both resolve to the same Decko key, which is why all
# identity comparisons below go through name_key rather than raw strings.
PARENT_CARD = "Raw Data+transcripts"

# Maximum characters per card. Transcripts can be very large.
MAX_CARD_CHARS = 50_000

# When set, plan and report every card that *would* be written but never touch
# the database. Use this to verify naming/chunking before a real ingest.
DRY_RUN = %w[1 true yes on].include?(
  ENV.fetch("TRANSCRIPT_INGEST_DRY_RUN", "").strip.downcase
)

# Optional path for a machine-readable plan/result report.
REPORT_PATH = ENV["TRANSCRIPT_INGEST_REPORT"]

# ------------------------------------------------------------
# Delta planning (analysis only, no write path)
# ------------------------------------------------------------
DELTA = %w[1 true yes on].include?(
  ENV.fetch("TRANSCRIPT_INGEST_DELTA", "").strip.downcase
)

# There is no delta write path. Refusing here - before any card is fetched or
# rendered - is the whole safety story: there is no code path in which DELTA
# can reach a database write.
if DELTA && !DRY_RUN
  abort <<~MSG
    TRANSCRIPT_INGEST_DELTA=1 requires TRANSCRIPT_INGEST_DRY_RUN=1.

    The delta planner is analysis-only. No delta write path exists yet, so
    running it with writes enabled would silently fall back to the
    full-rewrite behaviour it is meant to replace. Aborting before any
    database access.
  MSG
end

# ------------------------------------------------------------
# Stale-chunk policy
# ------------------------------------------------------------
# What to do about a live chunk card that the new plan no longer covers -
# the shrink case, where a transcript that used to need 5 chunk cards now
# needs 3 and chunk-4/chunk-5 are left above the high-water mark.
#
#   TRANSCRIPT_KEEP_STALE_CHUNKS=1  (keep, THE DEFAULT)
#     Preserve every stale chunk card exactly as it is. The shrink is still
#     reported in full - every stale card is named - but it does NOT block a
#     write mode. Accepted risk: a transcript may be represented by more
#     chunk cards than it strictly needs, i.e. duplicated text.
#
#   TRANSCRIPT_KEEP_STALE_CHUNKS=0  (review)
#     Treat a shrink as a blocker and require an explicit decision before
#     any write mode. This was the previous behaviour.
#
# Keep is the default because the two failure modes are not symmetrical:
# duplicated transcript text is an annoyance a later pass can tidy up, while
# dropping a chunk card destroys the only copy of whatever was in it.
#
# IMPORTANT: this setting decides only whether a shrink BLOCKS A WRITE. It
# does not - and cannot - cause a card to be removed. There is no delete,
# destroy, trash or prune path for chunk cards in this script under either
# setting; the only database calls are Card.create! and card.update!.
KEEP_STALE_CHUNKS = !%w[0 false no off review].include?(
  ENV.fetch("TRANSCRIPT_KEEP_STALE_CHUNKS", "1").strip.downcase
)
STALE_CHUNK_POLICY = KEEP_STALE_CHUNKS ? "keep" : "review"

# Files that live in an export dir but are not transcript payloads.
NON_TRANSCRIPT_FILES = %w[export_summary.json verification_report.json].freeze

# ============================================================
# Helpers
# ============================================================

def escape_html(text)
  text.to_s
    .gsub("&", "&amp;")
    .gsub("<", "&lt;")
    .gsub(">", "&gt;")
end

# Decko uses "+" as the name joint, so a meeting title containing "+" silently
# creates extra name parts: "LLM+PLN Sync" would be filed as
# "Raw Data+transcripts+LLM+PLN Sync+<date>", i.e. a descendant of a
# "Raw Data+transcripts+LLM" card that never existed. Collapse the joint and
# the other structurally meaningful characters so a title is always one part.
#
# The previous implementation only replaced "+" and "/", which left brackets,
# nest syntax and the reserved "*"/"~" prefixes able to produce unintended
# card names.
def sanitize_name_part(text)
  cleaned = text.to_s.dup
  cleaned.tr!("+", "-")               # name joint: would split into parts
  cleaned.tr!("/", "-")               # path separator in pretty URLs
  cleaned.gsub!(/[\[\]{}|<>#"]/, "-") # nest/markup syntax
  cleaned.gsub!(/\s+/, " ")
  cleaned.gsub!(/-{2,}/, "-")
  cleaned.sub!(/\A[*~]+/, "")         # leading * and ~ are reserved prefixes
  cleaned = cleaned.gsub(/\A[-\s]+|[-\s]+\z/, "")
  cleaned.empty? ? nil : cleaned
end

# Decko's real key (handles singularization, case, punctuation) when running
# under the Decko environment. The fallback is an approximation used only by
# offline unit tests where Cardname is not loaded; it splits camelCase runs so
# that "RawData" and "Raw Data" agree offline the way they do in the deck.
def name_key(full_name)
  return full_name.to_name.key if defined?(Cardname)

  full_name.split("+").map do |part|
    part.gsub(/([a-z0-9])([A-Z])/, '\1_\2')
        .downcase
        .gsub(/[^a-z0-9]+/, "_")
        .gsub(/\A_+|_+\z/, "")
  end.join("+")
end

# Collects what happened (or would happen) for the final report.
STATS = {
  created: 0, updated: 0, errors: 0,
  planned_create: 0, planned_update: 0, skipped_unchanged: 0,
  cards: []
}

# ============================================================
# Delta hashing
# ============================================================

# A transcript card's content is a pure function of the exported transcript:
# there is no per-run "Exported:" header the way Mattermost channel cards have
# one. So normalization is the identity function, and the delta is honest
# without excluding anything.
#
# This is asserted by a test rather than assumed. If a future change adds a
# run timestamp to the rendered header, that test fails and whoever adds it
# has to decide explicitly how the hash should treat it.
def normalize_for_hash(content)
  content.to_s
end

def content_hash(content)
  Digest::SHA256.hexdigest(normalize_for_hash(content))
end

# Fetch a live card's stored content, or nil when the card does not exist.
# Read-only: never instantiates a change.
def live_content(name)
  return nil unless defined?(Card)

  card = begin
    Card::Auth.as_bot { Card.fetch(name) }
  rescue StandardError
    nil
  end
  return nil if card.nil? || card.trash

  card.content.to_s
end

def card_exists?(name)
  return false unless defined?(Card)

  card = begin
    Card::Auth.as_bot { Card.fetch(name) }
  rescue StandardError
    nil
  end
  !card.nil? && !card.trash
end

def body_after_header(content)
  i = content.to_s.index("<hr>")
  i ? content.to_s[(i + 4)..] : content.to_s
end

# Why a card differs, in terms a reviewer can act on.
#
# Transcript cards have no post-count marker to compare (that is a Mattermost
# construct), so the transcript body length is the signal: a re-transcribed or
# extended recording grows, a truncated/partial export shrinks, and a
# re-render of the same text with different metadata only moves the header.
def change_reason(live, rendered)
  return "missing_card" if live.nil?

  live_body = body_after_header(normalize_for_hash(live))
  new_body  = body_after_header(normalize_for_hash(rendered))

  return "transcript_meta_changed" if live_body == new_body

  if new_body.length > live_body.length
    "text_grew"
  elsif new_body.length < live_body.length
    "text_shrank"
  else
    "text_edited"
  end
end

# Live cards under PARENT_CARD, walked by left_id rather than matched by name
# prefix: the deck stores this branch as "RawData+transcripts" while
# PARENT_CARD is "Raw Data+transcripts", and compound Decko cards can carry a
# NULL name column. Report only; nothing here deletes.
# True only when a Decko card API is actually reachable in this process.
# Evaluated lazily (never at load time) so that merely loading this file still
# cannot touch the deck - see the RUN_REQUESTED note at the bottom of the file.
#
# This matters for honesty, not safety: outside a Decko runner there is no live
# baseline at all, so every planned card trivially looks like a create and
# every orphan/chunk query trivially returns empty. A delta report that claimed
# baseline "live-content-hash" in that situation would read as "nothing to
# reconcile" when the truth is "nothing was compared".
def card_api_available?
  defined?(Card) ? true : false
end

def live_descendant_names(parent_name)
  return [] unless defined?(Card)

  @live_descendant_cache ||= {}
  cached = @live_descendant_cache[parent_name]
  return cached if cached

  @live_descendant_cache[parent_name] = compute_live_descendant_names(parent_name)
end

def compute_live_descendant_names(parent_name)
  Card::Auth.as_bot do
    parent = begin
      Card.fetch(parent_name)
    rescue StandardError
      nil
    end
    return [] unless parent

    names = []
    frontier = [parent.id]
    seen = {}
    until frontier.empty?
      batch = Card.where(left_id: frontier).to_a
      frontier = []
      batch.each do |c|
        next if seen[c.id]

        seen[c.id] = true
        frontier << c.id
        next if c.trash

        names << c.name.to_s
      end
    end
    names
  end
end

# ============================================================
# Transcript naming
# ============================================================

# Matches the trailing part of a chunk card, in both the display form
# ("chunk-6") and Decko's key form ("chunk_6"): orphan names arrive as stored
# names while planned names are built by this script.
CHUNK_PART_RE = /\Achunk[-_](\d+)\z/.freeze

# How many name parts PARENT_CARD occupies. Descendant parts are taken by
# count, not by string prefix, for the key/spelling reason above.
PARENT_PART_COUNT = PARENT_CARD.split("+").length

def name_parts(full_name)
  full_name.to_s.split("+")
end

def relative_parts(full_name)
  name_parts(full_name).drop(PARENT_PART_COUNT)
end

# ["Standup","2026-01-02","chunk-1"] -> [["Standup","2026-01-02"], 1]
# ["Standup","2026-01-02"]           -> [["Standup","2026-01-02"], nil]
def split_chunk_parts(parts)
  m = parts.length > 1 ? CHUNK_PART_RE.match(parts.last.to_s) : nil
  m ? [parts[0..-2], m[1].to_i] : [parts, nil]
end

# base card key => Set of chunk indexes present in the given name list.
def chunk_index_by_base(names)
  names.each_with_object({}) do |n, acc|
    parts = name_parts(n)
    next unless parts.length > 1

    m = CHUNK_PART_RE.match(parts.last.to_s)
    next unless m

    (acc[name_key(parts[0..-2].join("+"))] ||= Set.new) << m[1].to_i
  end
end

# Assign a unique, stable card name to every transcript.
#
# A transcript card is "<parent>+<title>+<date>". Two transcripts of the same
# meeting on the same date therefore collided and silently overwrote each
# other; the old script had no collision handling at all. Preference order:
#   1. the sanitized meeting title            (kept when unambiguous)
#   2. "<title> (<transcript id>)"            (disambiguates duplicates)
#   3. the transcript id alone                (last resort, always unique)
def assign_transcript_labels(transcripts)
  transcripts.each do |t|
    t[:base_label] = sanitize_name_part(t[:meeting_name]) ||
                     sanitize_name_part(t[:transcript_id]) ||
                     "Unknown Meeting"
    t[:date_part] = sanitize_name_part(t[:date]) || "unknown-date"
  end

  base_counts = Hash.new(0)
  transcripts.each do |t|
    base_counts[name_key("#{PARENT_CARD}+#{t[:base_label]}+#{t[:date_part]}")] += 1
  end

  taken = {}
  transcripts.each do |t|
    base = t[:base_label]
    tid = sanitize_name_part(t[:transcript_id])
    unambiguous =
      base_counts[name_key("#{PARENT_CARD}+#{base}+#{t[:date_part]}")] == 1

    candidates = []
    candidates << [base, "meeting_name"] if unambiguous
    candidates << ["#{base} (#{tid})", "meeting_name+transcript_id"] if tid
    candidates << [tid, "transcript_id"] if tid
    candidates << ["#{base} (#{taken.length + 1})", "ordinal"]

    chosen = nil
    candidates.each do |label, reason|
      next unless label

      key = name_key("#{PARENT_CARD}+#{label}+#{t[:date_part]}")
      next if taken.key?(key)

      chosen = [label, reason, key]
      break
    end

    raise "Unable to assign a unique card name for transcript #{t[:transcript_id]}" unless chosen

    t[:label], t[:label_reason], t[:card_key] = chosen
    t[:card_name] = "#{PARENT_CARD}+#{t[:label]}+#{t[:date_part]}"
    taken[t[:card_key]] = t
  end

  dupes = transcripts.group_by { |t| t[:card_key] }.select { |_k, v| v.length > 1 }
  unless dupes.empty?
    raise "Card name collision unresolved: " +
          dupes.map { |k, v| "#{k} <- #{v.map { |t| t[:transcript_id] }.join(', ')}" }.join("; ")
  end

  transcripts
end

# The name this card's content would live under today, if it is an artifact of
# the pre-fix naming (an unsanitized "+" in the meeting title produced extra
# name parts). Re-running the live card's parts through the real sanitizer and
# the real key function tells us the two names denote one transcript without
# guessing at key normalization.
#
# Returns nil when there is nothing to collapse.
def superseding_name(full_name)
  parts, chunk_idx = split_chunk_parts(relative_parts(full_name))
  return nil if parts.length < 3

  date = parts.last
  collapsed = sanitize_name_part(parts[0..-2].join("+"))
  return nil if collapsed.nil?

  base = "#{PARENT_CARD}+#{collapsed}+#{date}"
  chunk_idx ? "#{base}+chunk-#{chunk_idx}" : base
end

# ============================================================
# Orphan / chunk-shrink / name-binding classification (report only)
# ============================================================
#
# Everything in this section LABELS. Nothing deletes, re-files or writes.
# The functions take the planned/live name lists explicitly so they can be
# unit-tested with no Decko and no database.
#
# Classifications, in the order they are tested:
#   stale_chunk             - transcript is still ingested but now needs fewer
#                             chunks; this card is above the new high-water
#                             mark. THE SHRINK CASE.
#   superseded_by_rename    - content is now filed under the sanitized name.
#   relabeled_transcript    - transcript still exists but its card was
#                             disambiguated (duplicate title+date).
#   vanished_transcript_chunk - chunk of a transcript card that is itself
#                             orphaned.
#   nesting_stub            - left-hand stub that only existed to host a
#                             pre-fix nested title.
#   vanished_transcript     - no exported transcript maps to this card.
def classify_orphans(orphans, planned_names, transcripts)
  planned_keys = planned_names.map { |n| name_key(n) }.to_set
  planned_chunks = chunk_index_by_base(planned_names)
  orphan_keys = orphans.map { |o| o[:key] }.to_set

  # Transcripts whose card name was disambiguated: the bare title they *would*
  # have used is very likely sitting in the deck from an earlier run.
  bare_label_keys = {}
  transcripts.each do |t|
    next if t[:label_reason].to_s == "meeting_name"

    bare = sanitize_name_part(t[:meeting_name].to_s)
    next unless bare

    bare_label_keys[name_key("#{PARENT_CARD}+#{bare}+#{t[:date_part]}")] = t
  end

  classified = orphans.map do |orphan|
    entry = orphan.dup
    parts = name_parts(orphan[:name])
    _base_parts, chunk_idx = split_chunk_parts(relative_parts(orphan[:name]))
    base_name = chunk_idx ? parts[0..-2].join("+") : nil
    base_key = base_name && name_key(base_name)

    superseded = superseding_name(orphan[:name])
    superseded = nil unless superseded && planned_keys.include?(name_key(superseded))

    entry[:chunk_index] = chunk_idx
    entry[:base_card] = base_name
    entry[:superseded_by] = superseded

    entry[:classification], entry[:detail] =
      if chunk_idx && base_key && planned_keys.include?(base_key)
        planned = planned_chunks[base_key] || Set.new
        if planned.include?(chunk_idx)
          # Planned and live, yet reported orphan: should be impossible.
          # Surfaced rather than swallowed so it cannot pass silently.
          ["unexpected_planned_chunk",
           "chunk-#{chunk_idx} is in the plan but was reported as an orphan"]
        else
          ["stale_chunk",
           "transcript still ingested but now needs #{planned.length} chunk(s); " \
           "this card is above the new high-water mark"]
        end
      elsif superseded
        ["superseded_by_rename",
         "content is now filed under #{superseded}"]
      elsif bare_label_keys.key?(orphan[:key])
        t = bare_label_keys[orphan[:key]]
        ["relabeled_transcript",
         "transcript #{t[:transcript_id]} is now filed as #{t[:card_name]} " \
         "(#{t[:label_reason]})"]
      elsif chunk_idx && base_key && orphan_keys.include?(base_key)
        ["vanished_transcript_chunk",
         "chunk of #{base_name}, which is itself orphaned"]
      else
        ["vanished_transcript",
         "no exported transcript maps to this card"]
      end

    entry
  end

  # A left-hand stub that only ever existed to host a pre-fix nested title has
  # no transcript of its own: every orphan below it is accounted for and it
  # holds no exported transcript.
  stub_candidates = classified.select do |e|
    e[:classification] == "vanished_transcript" &&
      relative_parts(e[:name]).length < 2
  end
  stub_candidates.each do |e|
    nested = classified.any? do |other|
      next false if other.equal?(e)

      name_key(other[:name]).start_with?("#{e[:key]}+") &&
        %w[superseded_by_rename stale_chunk].include?(other[:classification])
    end
    next unless nested

    e[:classification] = "nesting_stub"
    e[:detail] = "left-hand stub of a renamed nested title; holds no exported transcript"
  end

  classified
end

def orphan_summary(classified)
  by_class = classified.group_by { |o| o[:classification] }
                       .transform_values(&:length)
  stale = classified.select { |o| o[:classification] == "stale_chunk" }
                    .map { |o| o[:name] }.sort
  {
    total: classified.length,
    by_classification: by_class,
    # Always listed, under either policy: the reviewer sees every stale chunk
    # card by name whether or not it blocks.
    stale_chunks: stale,
    stale_chunk_policy: STALE_CHUNK_POLICY,
    stale_chunks_preserved: true,
    # Under the keep policy a stale chunk card is an accepted, preserved
    # leftover rather than a decision to make, so it needs no attention
    # before a write. Under review it is the one class that does.
    needs_attention: (KEEP_STALE_CHUNKS ? 0 : stale.length),
    unexpected: classified.count { |o| o[:classification] == "unexpected_planned_chunk" }
  }
end

def find_orphans(transcripts)
  return [] unless defined?(Card)

  planned_keys = STATS[:cards].map { |c| name_key(c[:name]) }.to_set

  raw = live_descendant_names(PARENT_CARD).reject do |nm|
    key = name_key(nm)
    planned_keys.include?(key) || nm.end_with?("+*self")
  end.map { |nm| { name: nm, key: name_key(nm) } }

  classify_orphans(raw, STATS[:cards].map { |c| c[:name] }, transcripts)
end

# Planned vs live chunk cards per transcript, and exactly which chunk cards
# the difference refers to. Counting the chunk cards that actually exist (and
# naming them) is what makes a shrink reviewable; a bare count hides it.
def chunk_changes(transcripts, live_names, planned_names)
  live_idx = chunk_index_by_base(live_names)
  plan_idx = chunk_index_by_base(planned_names)
  actions = STATS[:cards].each_with_object({}) do |c, h|
    h[name_key(c[:name])] = c[:action]
  end

  transcripts.filter_map do |t|
    base_key = name_key(t[:card_name])
    live = (live_idx[base_key] || Set.new).to_a.sort
    plan = (plan_idx[base_key] || Set.new).to_a.sort
    next if live == plan

    stale = (live - plan).sort
    added = (plan - live).sort
    direction =
      if stale.any? && added.any? then "resegmented"
      elsif stale.any? then "shrink"
      else "grow"
      end

    index_action = actions[base_key]
    index_consistent = index_action == "skip-unchanged"
    note =
      if stale.empty?
        "new chunk cards only; the index card gains links and strands nothing"
      elsif KEEP_STALE_CHUNKS
        "KEEP policy: these chunk cards are preserved as-is and are not " \
        "deleted, re-filed or rewritten. The index card " \
        "#{index_consistent ? 'already lists only the planned chunks' : 'will be rewritten to drop these chunk links'}, " \
        "so the stale cards remain in the deck holding their original text, " \
        "possibly duplicating text that is also in the planned chunks. " \
        "Accepted in exchange for never dropping content."
      elsif index_consistent
        "the live index card already lists only the planned chunks, so these " \
        "chunk cards are ALREADY stranded in the live deck - a delta write " \
        "neither creates nor repairs that condition"
      else
        "the index card will be rewritten to drop these chunk links; the " \
        "chunk cards themselves would be left in place (report-only)"
      end

    { transcript_id: t[:transcript_id], meeting_name: t[:meeting_name],
      date: t[:date], card_name: t[:card_name],
      live_chunks: live.length, planned_chunks: plan.length,
      delta: plan.length - live.length, direction: direction,
      live_chunk_indexes: live, planned_chunk_indexes: plan,
      stale_chunk_cards: stale.map { |i| "#{t[:card_name]}+chunk-#{i}" },
      new_chunk_cards: added.map { |i| "#{t[:card_name]}+chunk-#{i}" },
      live_index_gaps: ((1..(live.max || 0)).to_a - live),
      index_card: t[:card_name], index_card_action: index_action,
      index_already_consistent: index_consistent,
      stale_chunk_policy: STALE_CHUNK_POLICY,
      stale_chunks_preserved: true,
      blocking: (stale.any? && !KEEP_STALE_CHUNKS), note: note }
  end
end

# Which live card each exported transcript binds to, and what else in the deck
# claims that transcript's content. Report only; a rename is only safe to act
# on once both ends of it are visible.
def name_binding_manifest(transcripts, live_names, classified_orphans)
  live_keys = live_names.map { |n| name_key(n) }.to_set
  superseded_by_target = classified_orphans.group_by do |o|
    o[:superseded_by] && name_key(o[:superseded_by])
  end
  relabeled = classified_orphans.select { |o| o[:classification] == "relabeled_transcript" }

  transcripts.map do |t|
    key = name_key(t[:card_name])
    live_present = live_keys.include?(key)
    supersedes = (superseded_by_target[key] || []).map { |o| o[:name] }.sort
    bare = sanitize_name_part(t[:meeting_name].to_s)
    shadowed = if bare && t[:label_reason].to_s != "meeting_name"
                 relabeled.select { |o| o[:key] == name_key("#{PARENT_CARD}+#{bare}+#{t[:date_part]}") }
                          .map { |o| o[:name] }.sort
               else
                 []
               end

    { transcript_id: t[:transcript_id], meeting_name: t[:meeting_name],
      date: t[:date], source_service: t[:source_service],
      planned_card_name: t[:card_name], planned_key: key,
      label_reason: t[:label_reason],
      live_present: live_present,
      binding: (live_present ? "bound" : "new_card"),
      supersedes_live_cards: supersedes,
      shadowed_by_live_cards: shadowed,
      notable: (!live_present || t[:label_reason].to_s != "meeting_name" ||
                supersedes.any? || shadowed.any?) }
  end
end

# ============================================================
# Rendering
# ============================================================

def format_transcript_header(data)
  meeting_name = data["meeting_name"] || "Unknown Meeting"
  date = data["date"] || "?"
  service = data["source_service"] || "?"
  duration = data["duration_minutes"] || 0
  participants = data["participants"] || []
  keywords = data["keywords"] || []
  summary = data["summary"] || ""
  action_items = data["action_items"] || []
  transcript_url = data["transcript_url"] || ""

  lines = []
  lines << "<p><strong>Source:</strong> #{escape_html(service)} — #{escape_html(meeting_name)}</p>"
  lines << "<p><strong>Date:</strong> #{escape_html(date)}</p>"
  lines << "<p><strong>Duration:</strong> #{duration} min</p>" if duration.to_i > 0
  lines << "<p><strong>Participants:</strong> #{escape_html(participants.join(', '))}</p>" unless participants.empty?
  lines << "<p><strong>Keywords:</strong> #{escape_html(keywords.join(', '))}</p>" unless keywords.empty?

  if transcript_url && !transcript_url.empty?
    lines << "<p><strong>View on #{escape_html(service)}:</strong> <a href=\"#{escape_html(transcript_url)}\">#{escape_html(transcript_url)}</a></p>"
  end

  unless summary.empty?
    lines << "<h3>Summary</h3>"
    lines << "<p>#{escape_html(summary)}</p>"
  end

  unless action_items.empty?
    lines << "<h3>Action Items</h3>"
    lines << "<ul>"
    action_items.each { |item| lines << "  <li>#{escape_html(item)}</li>" }
    lines << "</ul>"
  end

  # The <hr> terminates the header for change_reason/body_after_header, so it
  # must be the last thing emitted here.
  lines << "<hr>"

  lines.join("\n")
end

def format_full_text(full_text)
  return "" if full_text.nil? || full_text.empty?

  lines = []
  lines << "<h3>Full Transcript</h3>"
  lines << "<pre>#{escape_html(full_text)}</pre>"
  lines.join("\n")
end

# ============================================================
# Card writing / planning
# ============================================================

def create_or_update_card(name, content, type_code = :raw_data)
  if DELTA
    # Analysis only. DELTA implies DRY_RUN (enforced at load), so this branch
    # can never fall through to a write.
    live = live_content(name)
    rendered_hash = content_hash(content)

    if live && content_hash(live) == rendered_hash
      STATS[:skipped_unchanged] += 1
      STATS[:cards] << {
        name: name, action: "skip-unchanged", reason: "content_identical",
        chars_before: live.length, chars_after: content.length,
        hash_before: rendered_hash, hash_after: rendered_hash
      }
      return
    end

    reason = change_reason(live, content)
    if live
      STATS[:planned_update] += 1
      STATS[:cards] << {
        name: name, action: "update", reason: reason,
        chars_before: live.length, chars_after: content.length,
        hash_before: content_hash(live), hash_after: rendered_hash
      }
      puts "  [delta] would update: #{name} (#{reason}, " \
           "#{live.length} -> #{content.length} chars)"
    else
      STATS[:planned_create] += 1
      STATS[:cards] << {
        name: name, action: "create", reason: reason,
        chars_before: nil, chars_after: content.length,
        hash_before: nil, hash_after: rendered_hash
      }
      puts "  [delta] would create: #{name} (#{content.length} chars)"
    end
    return
  end

  if DRY_RUN
    # Read-only: classify the write without performing it.
    exists = card_exists?(name)
    exists ? STATS[:planned_update] += 1 : STATS[:planned_create] += 1
    STATS[:cards] << { name: name, chars: content.length,
                       action: exists ? "update" : "create" }
    puts "  [dry-run] #{exists ? 'would update' : 'would create'}: #{name} " \
         "(#{content.length} chars)"
    return
  end

  Card::Auth.as_bot do
    card = begin
      Card.fetch(name)
    rescue StandardError
      nil
    end

    begin
      if card
        card.update!(content: content)
        STATS[:updated] += 1
        STATS[:cards] << { name: name, chars: content.length, action: "updated" }
        puts "  Updated: #{name} (#{content.length} chars)"
      else
        Card.create!(
          name: name,
          type_code: type_code,
          content: content
        )
        STATS[:created] += 1
        STATS[:cards] << { name: name, chars: content.length, action: "created" }
        puts "  Created: #{name} (#{content.length} chars)"
      end
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.message =~ /Name must be unique/
      card = Card.where(name: name).first
      if card
        card.update!(content: content)
        STATS[:updated] += 1
        STATS[:cards] << { name: name, chars: content.length,
                           action: "updated_after_conflict" }
        puts "  Updated (after conflict): #{name}"
      else
        raise
      end
    end
  end
rescue StandardError => e
  STATS[:errors] += 1
  STATS[:cards] << { name: name, action: "error", error: e.message }
  puts "  ERROR on #{name}: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# ============================================================
# Main: process each transcript export
# ============================================================

def ingest_transcript(json_path, base_card_name)
  data = JSON.parse(File.read(json_path))

  meeting_name = data["meeting_name"] || "Unknown"
  date = data["date"] || "unknown"
  full_text = data["full_text"] || ""

  puts "\n#{'=' * 60}"
  puts "Transcript: #{meeting_name} (#{date})"
  puts "Card:       #{base_card_name}"
  puts "  Full text: #{full_text.length} chars"
  puts "=" * 60

  header_html = format_transcript_header(data)
  text_html = format_full_text(full_text)
  full_html = header_html + "\n" + text_html

  if full_html.length <= MAX_CARD_CHARS
    create_or_update_card(base_card_name, full_html)
    return 1
  end

  puts "  Content too large (#{full_html.length} chars). Splitting..."

  text_lines = full_text.split("\n")
  chunks = []
  current_chunk = []
  current_length = 0

  text_lines.each do |line|
    line_html = "<p>#{escape_html(line)}</p>\n"
    if current_length + line_html.length > MAX_CARD_CHARS && !current_chunk.empty?
      chunks << current_chunk
      current_chunk = []
      current_length = 0
    end
    current_chunk << line
    current_length += line_html.length
  end
  chunks << current_chunk unless current_chunk.empty?

  puts "  Split into #{chunks.length} chunks"

  chunk_links = (1..chunks.length).map do |i|
    "<li>{{#{base_card_name}+chunk-#{i}|view:link;title:_R}}</li>"
  end

  index_content = header_html + <<~HTML
    <h3>Full Transcript</h3>
    <p><strong>Transcript split into #{chunks.length} parts:</strong></p>
    <ol>
    #{chunk_links.join("\n")}
    </ol>
  HTML

  create_or_update_card(base_card_name, index_content)

  chunks.each_with_index do |chunk_lines, idx|
    chunk_num = idx + 1
    chunk_text = chunk_lines.join("\n")
    chunk_content = <<~HTML
      <p><strong>Source:</strong> #{escape_html(data["source_service"])} — #{escape_html(meeting_name)} (part #{chunk_num}/#{chunks.length})</p>
      <p><strong>Date:</strong> #{escape_html(date)}</p>
      <hr>
      <pre>#{escape_html(chunk_text)}</pre>
    HTML

    create_or_update_card("#{base_card_name}+chunk-#{chunk_num}", chunk_content)
  end

  chunks.length + 1
end

# ============================================================
# Entry point
# ============================================================

def run!
  mode_label =
    if DELTA then " (DELTA PLAN - report only, no database writes)"
    elsif DRY_RUN then " (DRY RUN - no database writes)"
    else ""
    end

  puts "Hyperon Wiki Transcript Ingestion#{mode_label}"
  puts "Export directory: #{EXPORT_DIR}"
  puts "Parent card: #{PARENT_CARD}"
  puts

  unless Dir.exist?(EXPORT_DIR)
    puts "ERROR: Export directory not found: #{EXPORT_DIR}"
    puts "Run export_transcripts.py first, then copy exports to the server."
    exit 1
  end

  json_files = Dir.glob("#{EXPORT_DIR}/*.json")
    .reject { |f| NON_TRANSCRIPT_FILES.include?(File.basename(f)) }
    .sort

  puts "Found #{json_files.length} transcript exports"

  # Pass 1: metadata only, so names can be deduplicated globally before
  # anything is written.
  transcripts = []
  json_files.each do |f|
    data = begin
      JSON.parse(File.read(f))
    rescue JSON::ParserError => e
      puts "Skipping unparseable JSON #{File.basename(f)}: #{e.message}"
      next
    end
    unless data.is_a?(Hash) && (data["meeting_name"] || data["full_text"])
      puts "Skipping non-transcript JSON: #{File.basename(f)}"
      next
    end

    transcripts << {
      path: f,
      meeting_name: data["meeting_name"].to_s,
      date: data["date"].to_s,
      source_service: data["source_service"].to_s,
      transcript_id: data["transcript_id"].to_s
    }
  end

  assign_transcript_labels(transcripts)

  disambiguated = transcripts.reject { |t| t[:label_reason] == "meeting_name" }
  unless disambiguated.empty?
    puts "\nDisambiguated #{disambiguated.length} transcript card name(s):"
    disambiguated.each do |t|
      puts "  #{t[:meeting_name].inspect} -> #{t[:label].inspect} (#{t[:label_reason]})"
    end
  end

  sanitized = transcripts.select { |t| t[:base_label] != t[:meeting_name].to_s }
  unless sanitized.empty?
    puts "\nSanitized #{sanitized.length} meeting title(s) for Decko naming:"
    sanitized.each { |t| puts "  #{t[:meeting_name].inspect} -> #{t[:base_label].inspect}" }
  end

  # Pass 2: ingest
  transcripts.each_with_index do |t, idx|
    puts "\n[#{idx + 1}/#{transcripts.length}] #{File.basename(t[:path])}"
    t[:cards_written] = ingest_transcript(t[:path], t[:card_name])
  end

  total_cards = STATS[:cards].length
  live_names = DELTA ? live_descendant_names(PARENT_CARD) : []
  planned_names = STATS[:cards].map { |c| c[:name] }
  orphans = DELTA ? find_orphans(transcripts) : []
  orphan_stats = DELTA ? orphan_summary(orphans) : nil
  chunk_changes_list = DELTA ? chunk_changes(transcripts, live_names, planned_names) : []
  binding_manifest = DELTA ? name_binding_manifest(transcripts, live_names, orphans) : []
  name_conflicts = DELTA ? binding_manifest.reject { |m| m[:live_present] } : []
  shrinks = chunk_changes_list.select { |c| c[:stale_chunk_cards].any? }
  stale_chunk_names = shrinks.flat_map { |c| c[:stale_chunk_cards] }.sort
  stale_chunk_total = stale_chunk_names.length

  puts "\n#{'=' * 60}"
  if DRY_RUN
    puts "Dry run complete - nothing was written."
  elsif STATS[:errors].positive?
    # "Ingestion complete!" next to a pile of errors is how a half-written
    # deck gets signed off. Say plainly that it failed.
    puts "Ingestion FAILED: #{STATS[:errors]} card(s) errored."
  else
    puts "Ingestion complete!"
  end
  puts "Total transcripts: #{transcripts.length}"
  puts "Total cards: #{total_cards}"

  if DELTA
    unless card_api_available?
      puts "\n!! NO LIVE BASELINE: the Card API is not available in this " \
           "process, so nothing was compared against the deck."
      puts "!! Every card below is reported as a create and every " \
           "orphan/chunk count is trivially zero."
      puts "!! Re-run under `decko runner` to get a real reconciliation.\n"
    end

    puts "  skipped unchanged: #{STATS[:skipped_unchanged]}"
    puts "  would create:      #{STATS[:planned_create]}"
    puts "  would update:      #{STATS[:planned_update]}"
    puts "  stale-chunk policy: #{STALE_CHUNK_POLICY} " \
         "(TRANSCRIPT_KEEP_STALE_CHUNKS=#{KEEP_STALE_CHUNKS ? '1' : '0'}) - " \
         "#{KEEP_STALE_CHUNKS ? 'stale chunk cards are preserved and do not block a write' : 'shrinks block a write pending review'}"

    puts "\nOrphaned live cards: #{orphans.length} (report-only, nothing is deleted)"
    orphan_stats[:by_classification].sort_by { |_, v| -v }.each do |cls, n|
      puts "  #{cls.to_s.ljust(26)} #{n}"
    end

    puts "\nChunk count changes: #{chunk_changes_list.length}"
    chunk_changes_list.each do |c|
      puts "  #{c[:meeting_name]} (#{c[:date]}) [#{c[:direction]}] " \
           "live=#{c[:live_chunks]} planned=#{c[:planned_chunks]} " \
           "(#{format('%+d', c[:delta])})"
      puts "    stale: #{c[:stale_chunk_cards].join(', ')}" if c[:stale_chunk_cards].any?
      puts "    new:   #{c[:new_chunk_cards].join(', ')}" if c[:new_chunk_cards].any?
      puts "    gaps in live chunk numbering: #{c[:live_index_gaps].join(', ')}" if c[:live_index_gaps].any?
    end

    if shrinks.any?
      if KEEP_STALE_CHUNKS
        puts "\n#{'-' * 60}"
        puts "SHRINKING CHUNKS - #{shrinks.length} transcript(s), " \
             "#{stale_chunk_total} stale chunk card(s) [policy=keep]"
        shrinks.each do |c|
          puts "  #{c[:card_name]}: #{c[:live_chunks]} live -> #{c[:planned_chunks]} planned"
          c[:stale_chunk_cards].each { |n| puts "    KEPT: #{n}" }
        end
        puts "These cards are PRESERVED exactly as they are: not deleted,"
        puts "not pruned, not re-filed. Their text stays in the deck and may"
        puts "duplicate text in the planned chunks - accepted, because losing"
        puts "content is worse than duplicating it."
        puts "Policy: TRANSCRIPT_KEEP_STALE_CHUNKS=1 (default). This does NOT"
        puts "block a write mode. Set =0 to treat shrinks as blockers."
        puts "-" * 60
      else
        puts "\n#{'!' * 60}"
        puts "SHRINKING CHUNKS - #{shrinks.length} transcript(s) would strand chunk cards:"
        shrinks.each do |c|
          puts "  #{c[:card_name]}: #{c[:live_chunks]} live -> #{c[:planned_chunks]} planned"
          c[:stale_chunk_cards].each { |n| puts "    STALE: #{n}" }
          puts "    #{c[:note]}"
        end
        puts "A delta write would leave these cards in place and unreferenced."
        puts "This is reported, not acted on: nothing is deleted or re-filed."
        puts "Decide before enabling write mode, or set"
        puts "TRANSCRIPT_KEEP_STALE_CHUNKS=1 to keep them and proceed."
        puts "!" * 60
      end
    end

    notable = binding_manifest.select { |m| m[:notable] }
    puts "\nName bindings: #{binding_manifest.length} transcript(s), " \
         "#{name_conflicts.length} not yet present live, #{notable.length} notable"
    notable.each do |m|
      puts "  #{m[:planned_card_name]} [#{m[:binding]}/#{m[:label_reason]}]"
      m[:supersedes_live_cards].each { |n| puts "    supersedes live: #{n}" }
      m[:shadowed_by_live_cards].each { |n| puts "    shadowed by live: #{n}" }
    end

    if orphan_stats[:unexpected].positive?
      puts "\nWARNING: #{orphan_stats[:unexpected]} orphan(s) classified " \
           "'unexpected_planned_chunk'. The plan and the orphan scan disagree; " \
           "investigate before trusting this report."
    end
  elsif DRY_RUN
    puts "  would create: #{STATS[:planned_create]}"
    puts "  would update: #{STATS[:planned_update]}"
  else
    puts "  created: #{STATS[:created]}"
    puts "  updated: #{STATS[:updated]}"
    puts "  errors:  #{STATS[:errors]}"
  end
  puts "=" * 60

  if REPORT_PATH
    report = {
      mode: (DELTA ? "delta" : (DRY_RUN ? "full-dry-run" : "full-write")),
      baseline: (if DELTA
                   card_api_available? ? "live-content-hash" : "none-no-card-api"
                 end),
      baseline_available: (DELTA ? card_api_available? : nil),
      hash_normalization: (DELTA ? ["none_required_no_export_timestamp"] : nil),
      dry_run: DRY_RUN,
      export_dir: EXPORT_DIR,
      parent_card: PARENT_CARD,
      max_card_chars: MAX_CARD_CHARS,
      transcript_count: transcripts.length,
      services: transcripts.map { |t| t[:source_service] }.reject(&:empty?).uniq.sort,
      card_count: total_cards,
      stats: STATS.reject { |k, _| k == :cards },
      transcripts: transcripts.map do |t|
        {
          transcript_id: t[:transcript_id], meeting_name: t[:meeting_name],
          date: t[:date], source_service: t[:source_service],
          card_name: t[:card_name], card_key: t[:card_key],
          label_reason: t[:label_reason], cards_written: t[:cards_written]
        }
      end,
      cards: STATS[:cards]
    }

    if DELTA
      report[:cards_summary] = {
        total: total_cards,
        skipped_unchanged: STATS[:skipped_unchanged],
        planned_create: STATS[:planned_create],
        planned_update: STATS[:planned_update],
        orphaned: orphans.length
      }
      report[:orphans] = orphans
      report[:orphan_summary] = orphan_stats
      report[:name_binding_conflicts] = name_conflicts
      report[:name_binding_manifest] = binding_manifest
      report[:chunk_count_changes] = chunk_changes_list
      report[:chunk_shrinks] = shrinks
      report[:stale_chunk_policy] = {
        policy: STALE_CHUNK_POLICY,
        env_var: "TRANSCRIPT_KEEP_STALE_CHUNKS",
        keep_stale_chunks: KEEP_STALE_CHUNKS,
        preserved: true,
        destructive_path_exists: false,
        shrinking_chunk_transcripts: shrinks.length,
        stale_chunk_cards_total: stale_chunk_total,
        stale_chunk_cards: stale_chunk_names,
        blocks_write: (!KEEP_STALE_CHUNKS && stale_chunk_total.positive?),
        rationale: (KEEP_STALE_CHUNKS ?
          "Stale chunk cards are kept. Risking duplicated transcript text is " \
          "preferred over any chance of cutting content that only exists in " \
          "a stale chunk card. Nothing is deleted, pruned or re-filed." :
          "Shrinks are treated as blockers pending review. Even here nothing " \
          "is deleted: the script has no destructive path.")
      }
      # One place a reviewer can look to answer "is this safe to write yet?".
      report[:write_readiness] = {
        write_path_implemented: false,
        baseline_compared: card_api_available?,
        stale_chunk_policy: STALE_CHUNK_POLICY,
        blocking: {
          # Under the keep policy a shrink is an accepted outcome, not a
          # blocker: the stale cards stay exactly where they are.
          shrinking_chunk_transcripts: (KEEP_STALE_CHUNKS ? 0 : shrinks.length),
          stale_chunk_cards: (KEEP_STALE_CHUNKS ? 0 : stale_chunk_total),
          unexpected_planned_chunks: orphan_stats[:unexpected],
          no_live_baseline: card_api_available? ? 0 : 1
        },
        # Reported under either policy so the shrink never becomes invisible.
        acknowledged: {
          shrinking_chunk_transcripts: shrinks.length,
          stale_chunk_cards: stale_chunk_total
        },
        stale_chunk_cards: stale_chunk_names,
        note: "Report-only. Orphans and stale chunks are labelled, never " \
              "deleted or re-filed. Delta mode has no write path and aborts " \
              "unless TRANSCRIPT_INGEST_DRY_RUN=1." +
              (if KEEP_STALE_CHUNKS
                 " STALE-CHUNK POLICY=keep (TRANSCRIPT_KEEP_STALE_CHUNKS): " \
                 "the #{stale_chunk_total} stale chunk card(s) above are " \
                 "PRESERVED and do not block a write. They stay in the deck " \
                 "with their original text, which may duplicate text in the " \
                 "planned chunks. Duplication is preferred over any risk of " \
                 "dropping content. Set TRANSCRIPT_KEEP_STALE_CHUNKS=0 to " \
                 "treat a shrink as a blocker again."
               else
                 " STALE-CHUNK POLICY=review: the #{stale_chunk_total} stale " \
                 "chunk card(s) above block a write mode until decided. Set " \
                 "TRANSCRIPT_KEEP_STALE_CHUNKS=1 to preserve them and proceed."
               end) +
              (card_api_available? ? "" : " WARNING: no Card API in this " \
               "process, so NOTHING was compared against the live deck. " \
               "Every card below is reported as a create and every " \
               "orphan/chunk count is trivially zero. Re-run under " \
               "`decko runner` before treating this as a reconciliation.")
      }
      report[:reasons] = STATS[:cards].group_by { |c| c[:reason] }
                                      .transform_values(&:length)
      report[:cards_detail] = STATS[:cards].reject { |c| c[:action] == "skip-unchanged" }
    end

    File.write(REPORT_PATH, JSON.pretty_generate(report))
    puts "Report written to #{REPORT_PATH}"
  end

  STATS[:errors]
end

# ------------------------------------------------------------
# Only auto-run when this file is the program being executed, or when a Decko
# runner is explicitly asking for an ingest.
#
# Inside a Decko/Rails process `Card` is ALWAYS defined, so a guard of
# `defined?(Card)` would mean that *merely loading* this file - an autoload, a
# console `load`, a test `require`, or anything that happened to sweep the
# scripts directory - kicked off a full ingest that wrote cards to the live
# database. Loading a file must never mutate the deck.
#
# `decko runner` evaluates the script rather than setting $PROGRAM_NAME to it
# (notably `runner -`, which streams the script over stdin), so the runner
# path opts in explicitly via TRANSCRIPT_INGEST=1.
RUN_REQUESTED = ENV["TRANSCRIPT_INGEST"] == "1"

if $PROGRAM_NAME == __FILE__ || RUN_REQUESTED
  errors = run!
  # run! counts per-card failures but used to return them into the void, so a
  # run where EVERY card blew up still exited 0 and any wrapper (sync script,
  # CI step, cron) read total failure as success. Propagate it.
  exit(1) if errors.to_i.positive?
end
