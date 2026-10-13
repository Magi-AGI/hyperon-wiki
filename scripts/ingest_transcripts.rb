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
#   This script NEVER writes in delta mode: setting
#   TRANSCRIPT_INGEST_DELTA=1 without TRANSCRIPT_INGEST_DRY_RUN=1 aborts before
#   any database access. The delta WRITE path lives in a separate, manifest
#   driven applier - scripts/apply_transcript_delta.rb - which refuses to run
#   without an explicit write gate, the manifest's sha256, a confirm token and
#   a loopback deck origin. See TRANSCRIPT_DELTA_MANIFEST below.
#
# DELTA WRITE MANIFEST (still report-only here; consumed by the applier):
#   TRANSCRIPT_INGEST=1 TRANSCRIPT_INGEST_DRY_RUN=1 TRANSCRIPT_INGEST_DELTA=1 \
#     TRANSCRIPT_INGEST_REPORT=/tmp/transcript_delta.json \
#     TRANSCRIPT_DELTA_MANIFEST=/tmp/transcript_delta_manifest.json \
#     bundle exec decko runner scripts/ingest_transcripts.rb
#
#   The manifest freezes the write set by HASH rather than by embedded payload:
#   every row carries the desired content sha256, the live content sha256 it
#   was planned against, and the export file it renders from (itself pinned by
#   sha256). The applier re-renders through this script's own
#   render_transcript_cards_from_data, so it can only ever write bytes the
#   planner planned, and it halts if either side has moved.
#
#   The manifest covers planned creates and updates ONLY. It declares zero
#   deletes, zero orphan cleanup and zero stale-chunk pruning, and names the
#   orphan/stale-chunk/foreign-corpus cards that must be left exactly as they
#   are so the applier can verify their preservation after writing.
#
#   Delta mode additionally reports, without ever deleting or re-filing:
#     - orphaned live cards, labelled (stale_chunk, superseded_by_rename,
#       relabeled_transcript, nesting_stub, structural_ancestor_stub,
#       vanished_transcript, ...)
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
require 'date'

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

# There is no delta write path IN THIS SCRIPT. Refusing here - before any card
# is fetched or rendered - is the whole safety story for the planner: there is
# no code path in which DELTA can reach a database write from this file. The
# write path is a separate applier (scripts/apply_transcript_delta.rb) driven
# by the frozen manifest this planner emits.
if DELTA && !DRY_RUN
  abort <<~MSG
    TRANSCRIPT_INGEST_DELTA=1 requires TRANSCRIPT_INGEST_DRY_RUN=1.

    The delta planner is analysis-only. This script has no delta write path,
    so running it with writes enabled would silently fall back to the
    full-rewrite behaviour it is meant to replace. Aborting before any
    database access.

    To APPLY a delta, run the planner with TRANSCRIPT_DELTA_MANIFEST=<path>
    and then hand that manifest to scripts/apply_transcript_delta.rb, which
    has its own write gate, manifest-sha gate, confirm token and
    loopback-origin guard.
  MSG
end

# ------------------------------------------------------------
# Delta write manifest (emitted by the planner, consumed by the applier)
# ------------------------------------------------------------
# Optional path for the frozen write manifest. Emitting a manifest is still a
# read-only act: it records what a write WOULD do. It is only meaningful when
# the delta planner actually compared against a live baseline, so it is gated
# on DELTA (which in turn requires DRY_RUN above).
DELTA_MANIFEST_PATH = ENV["TRANSCRIPT_DELTA_MANIFEST"]

if DELTA_MANIFEST_PATH && !DELTA
  abort <<~MSG
    TRANSCRIPT_DELTA_MANIFEST requires TRANSCRIPT_INGEST_DELTA=1.

    A write manifest is only honest when it was produced by the delta planner
    against a live baseline: outside delta mode nothing is compared, so every
    row would claim to be a create with no live hash. Aborting before any
    database access.
  MSG
end

# The exact token scripts/apply_transcript_delta.rb demands in
# TRANSCRIPT_DELTA_CONFIRM before it will write. Declared here so the planner
# can stamp it into the manifest and the two files cannot drift apart.
DELTA_CONFIRM_TOKEN = "APPLY-TRANSCRIPT-DELTA-LOCAL"

# Manifest schema version. The applier pins this exactly: a manifest from a
# future planner must not be applied by an older applier.
DELTA_MANIFEST_VERSION = 1

# Cards that must never appear in a write set, whatever the plan says.
# Enumerated, never inferred (same reasoning as FOREIGN_CORPORA above).
#
#   - the 2026-03-03 "Frag, EARTHwise, Magi" card is a keep-only retention
#     decision: it is an unmatched orphan whose content has no export source.
#   - anything under a foreign corpus is ingested by a different pipeline.
#
# Semicolon-separated, compared through name_key.
DELTA_PROTECTED_NAMES = ENV.fetch(
  "TRANSCRIPT_DELTA_PROTECTED",
  "Raw Data+transcripts+Elowyn AI Meeting - Frag, EARTHwise, Magi+2026-03-03"
).split(";").map(&:strip).reject(&:empty?).freeze

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

# ------------------------------------------------------------
# Foreign corpora
# ------------------------------------------------------------
# Some cards under PARENT_CARD were ingested by a different pipeline and no
# transcript exporter can ever produce them, so they are permanently
# "vanished" through no fault of the deck. The known case is "AGI 26":
# conference-video captions, not meeting transcripts, ~120 cards that bury the
# single genuine gap under 3x their own noise.
#
# The list is enumerated, never inferred. A structural rule such as "anything
# without a trailing date part" would also swallow real undated meeting stubs,
# and - far worse - would silently hide any FUTURE genuinely lost card that
# happened to lack a date. An enumerated list can only ever hide names an
# operator typed in.
#
# Semicolon-separated because real meeting titles contain commas (e.g.
# "Elowyn AI Meeting - Frag, EARTHwise, Magi"). Set to "" to disable.
FOREIGN_CORPORA = ENV.fetch("TRANSCRIPT_FOREIGN_CORPORA", "AGI 26")
                     .split(";").map(&:strip).reject(&:empty?).freeze
# Compared through name_key so "AGI 26" / "AGI-26" / "agi 26" all agree.
FOREIGN_CORPUS_KEYS = FOREIGN_CORPORA.to_h { |c| [name_key(c), c] }.freeze

# Collects what happened (or would happen) for the final report.
STATS = {
  created: 0, updated: 0, errors: 0,
  planned_create: 0, planned_update: 0, skipped_unchanged: 0,
  cards: []
}

# planned card name => provenance of the render that produced it. Populated by
# ingest_transcript during planning; consumed only by the write manifest.
DELTA_SOURCES = {}

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
#   structural_ancestor_stub - empty left-hand card that exists ONLY because a
#                             planned card is filed beneath it. Decko creates
#                             these itself; see the section below.
#   vanished_transcript     - no exported transcript maps to this card.
#
# content_reader is how this function learns whether a card is empty. It is
# injected rather than called directly so the classifier stays unit-testable
# with no Decko and no database, and so "I could not read it" (nil) is
# distinguishable from "I read it and it was empty" ("").
def classify_orphans(orphans, planned_names, transcripts,
                     content_reader: method(:live_content))
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

  # ----------------------------------------------------------
  # Empty structural ancestors Decko created to file a planned card
  # ----------------------------------------------------------
  # A Decko compound card is filed under BOTH of its name parts, so writing
  # "<parent>+MeTTa Coders+2026-02-11" brings the left card
  # "<parent>+MeTTa Coders" into existence as an EMPTY card of a structural
  # type. That ancestor is a live descendant of PARENT_CARD, it is not in the
  # plan (no transcript renders to it), so the orphan scan sees it - and the
  # old code called it a vanished_transcript, i.e. "we lost a meeting".
  #
  # That label is simply false: the card has never held a transcript and
  # nothing is missing. It is scaffolding for a card we deliberately wrote.
  # Mislabelling it also inflates the undated_legacy generation count, which
  # is the number a reviewer reads to decide whether content was lost.
  #
  # Every condition below is a property of the card itself, checked against
  # the plan that is running - never a count, never a name pattern:
  #
  #   1. it is a strict left-hand ancestor of at least one PLANNED card, so
  #      the current plan is the reason it exists;
  #   2. it is EMPTY, read from the live deck, so it holds no content that
  #      could have come from a transcript;
  #   3. no transcript renders to it (it is an orphan, by construction).
  #
  # Anything that fails one of these keeps the label it already had. A
  # non-empty ancestor is still a vanished_transcript: it holds text, and
  # text under a name no export produces is exactly the case a reviewer must
  # see. Foreign-corpus and protected cards are untouched here; this changes
  # a LABEL and nothing else. Nothing is deleted, re-filed or rewritten.
  planned_ancestor_keys = strict_ancestor_keys(planned_names)
  classified.each do |e|
    next unless e[:classification] == "vanished_transcript"
    next unless planned_ancestor_keys.key?(e[:key])
    # nil means "could not read" (no Card API); only a card we actually read
    # and found empty may be relabelled.
    content = content_reader.call(e[:name])
    next unless content.is_a?(String) && content.empty?

    beneath = planned_ancestor_keys[e[:key]]
    e[:classification] = "structural_ancestor_stub"
    e[:detail] =
      "empty left-hand card Decko creates to file #{beneath.length} planned " \
      "card(s) beneath it (e.g. #{beneath.min}); holds no content and no " \
      "exported transcript maps to it"
    e[:structural_ancestor_of] = beneath.sort.first(5)
    e[:structural_ancestor_count] = beneath.length
  end

  classified
end

# key of every strict left-hand ancestor in a name list => the names filed
# beneath it. "a+b+c" contributes "a" and "a+b", never "a+b+c" itself.
def strict_ancestor_keys(names)
  names.each_with_object({}) do |n, acc|
    parts = name_parts(n)
    (1...parts.length).each do |i|
      (acc[name_key(parts[0...i].join("+"))] ||= []) << n
    end
  end
end

# ------------------------------------------------------------
# Vanished-transcript generation sub-classification (report only)
# ------------------------------------------------------------
# "vanished_transcript" only says *no exported transcript maps to this card*.
# That one label covers several very different situations, and the difference
# matters a lot when deciding what to do before a write:
#
#   undated_legacy    - the card has no trailing date part at all, so it comes
#                       from the pre-date naming generation (or from a corpus
#                       that never used dated names). Usually an empty stub.
#   date_shifted      - the series IS being re-ingested and a planned card for
#                       the same series sits within DATE_SHIFT_TOLERANCE_DAYS.
#                       Strongly suggests an exporter date/timezone change
#                       rather than lost content: the same meeting is simply
#                       being filed under an adjacent date.
#   series_renamed    - the series is not in the plan, but some other series IS
#                       planned on exactly this date. The meeting is very likely
#                       the same one re-titled upstream.
#   series_active     - the series is being re-ingested, but no planned date is
#                       near this one. A date genuinely dropped out of a series
#                       that otherwise still exports.
#   unmatched         - no planned card for this series and nothing planned on
#                       this date. The real "we have no source for this" case.
#
# This is pure labelling derived from the planned names; it reads no card
# content, contacts nothing, and changes no decision the planner makes. It
# exists so a reviewer can tell "162 vanished" apart from "162 lost meetings".
DATE_PART_RE = /\A\d{4}-\d{2}-\d{2}\z/.freeze
DATE_SHIFT_TOLERANCE_DAYS = 3

# ["Standup","2026-01-02"] -> ["Standup", "2026-01-02"]
# ["AGI 26","vid","full"]  -> ["AGI 26+vid+full", nil]
def split_date_part(parts)
  if parts.length > 1 && DATE_PART_RE.match?(parts.last.to_s)
    [parts[0..-2].join("+"), parts.last.to_s]
  else
    [parts.join("+"), nil]
  end
end

# series key => Set of dates, and date => Set of series keys, over a name list.
def series_date_index(names)
  by_series = {}
  by_date = {}
  names.each do |n|
    base_parts, = split_chunk_parts(relative_parts(n))
    series, date = split_date_part(base_parts)
    next unless date

    skey = name_key(series)
    (by_series[skey] ||= Set.new) << date
    (by_date[date] ||= Set.new) << skey
  end
  [by_series, by_date]
end

def days_between(one, other)
  (Date.parse(one) - Date.parse(other)).to_i.abs
rescue ArgumentError, TypeError
  nil
end

# Nearest planned date for this series, as [distance_in_days, date].
def nearest_planned_date(date, planned_dates)
  planned_dates.filter_map { |d| (n = days_between(date, d)) && [n, d] }.min
end

def vanished_generation(name, planned_by_series, planned_by_date)
  base_parts, = split_chunk_parts(relative_parts(name))
  series, date = split_date_part(base_parts)
  skey = name_key(series)

  return { generation: "undated_legacy", series: series, date: nil,
           detail: "no trailing date part; pre-date naming generation" } unless date

  planned_dates = planned_by_series[skey]
  if planned_dates&.any?
    nearest = nearest_planned_date(date, planned_dates)
    if nearest && nearest.first <= DATE_SHIFT_TOLERANCE_DAYS
      return { generation: "date_shifted", series: series, date: date,
               nearest_planned_date: nearest.last, date_offset_days: nearest.first,
               detail: "same series is planned #{nearest.first} day(s) away on " \
                       "#{nearest.last}; looks like an exporter date shift, not lost content" }
    end
    return { generation: "series_active", series: series, date: date,
             nearest_planned_date: nearest&.last, date_offset_days: nearest&.first,
             detail: "series is still ingested but no planned date is within " \
                     "#{DATE_SHIFT_TOLERANCE_DAYS} day(s) of #{date}" }
  end

  other = (planned_by_date[date] || Set.new).reject { |k| k == skey }
  if other.any?
    return { generation: "series_renamed", series: series, date: date,
             planned_series_on_date: other.to_a.sort,
             detail: "this series is not planned, but #{other.length} other series " \
                     "is planned on #{date}; likely the same meeting re-titled" }
  end

  { generation: "unmatched", series: series, date: date,
    detail: "no planned card for this series and nothing planned on #{date}" }
end

# Attaches :generation (and its evidence) to every vanished_transcript entry.
# Report-only: returns the same entries, annotated.
def annotate_vanished_generations(classified, planned_names)
  planned_by_series, planned_by_date = series_date_index(planned_names)
  classified.each do |entry|
    next unless entry[:classification] == "vanished_transcript"

    info = vanished_generation(entry[:name], planned_by_series, planned_by_date)
    entry[:generation] = info[:generation]
    entry[:generation_detail] = info[:detail]
    entry[:generation_series] = info[:series]
    entry[:generation_date] = info[:date]
    entry[:nearest_planned_date] = info[:nearest_planned_date] if info[:nearest_planned_date]
    entry[:date_offset_days] = info[:date_offset_days] if info[:date_offset_days]
  end
end

# Counts per generation, plus the names for the two classes a reviewer should
# actually look at before a write.
def vanished_generation_summary(classified)
  vanished = classified.select { |o| o[:classification] == "vanished_transcript" }
  return nil if vanished.empty?

  native = vanished.reject { |o| o[:foreign_corpus] }
  by_gen = vanished.group_by { |o| o[:generation] }.transform_values(&:length)
  {
    total: vanished.length,
    by_generation: by_gen,
    date_shift_tolerance_days: DATE_SHIFT_TOLERANCE_DAYS,
    # The only class with no upstream explanation at all.
    unmatched_cards: vanished.select { |o| o[:generation] == "unmatched" }
                             .map { |o| o[:name] }.sort,
    # Same meeting under an adjacent date: fixing the exporter turns each of
    # these into a plain update instead of a duplicate card.
    date_shifted_cards: vanished.select { |o| o[:generation] == "date_shifted" }
                                .map { |o| o[:name] }.sort,
    note: "Report-only sub-classification of vanished_transcript. Nothing is " \
          "deleted, re-filed or rewritten on the basis of these labels.",
    # Same split with the foreign corpora taken out, so the readable number is
    # available without the raw one changing.
    excluding_foreign_corpus: {
      total: native.length,
      by_generation: native.group_by { |o| o[:generation] }.transform_values(&:length)
    }
  }
end

# ------------------------------------------------------------
# Foreign-corpus labelling (report only)
# ------------------------------------------------------------
# Which enumerated corpus this card belongs to, by its FIRST relative name
# part. Anchored to the first part on purpose: "AGI 26" appearing deeper in a
# name is not a foreign corpus, and a real exported series ("AGI Strategy
# Biweekly") must never match. Pure string work: no Card, no IO.
def foreign_corpus(full_name)
  parts = relative_parts(full_name)
  return nil if parts.empty?

  FOREIGN_CORPUS_KEYS[name_key(parts.first)]
end

# Attaches :foreign_corpus where it applies. Report-only, and deliberately
# leaves every existing key - :classification and :generation included -
# exactly as it found them.
def annotate_foreign_corpora(classified)
  classified.each do |entry|
    corpus = foreign_corpus(entry[:name])
    entry[:foreign_corpus] = corpus if corpus
  end
end

# Counts AND names every excluded card. Excluded from the readable signal must
# never mean excluded from the data.
def foreign_corpus_summary(classified)
  foreign = classified.select { |o| o[:foreign_corpus] }
  return nil if foreign.empty?

  {
    total: foreign.length,
    by_corpus: foreign.group_by { |o| o[:foreign_corpus] }.transform_values(&:length),
    by_classification: foreign.group_by { |o| o[:classification] }.transform_values(&:length),
    exclusions: FOREIGN_CORPORA,
    env_var: "TRANSCRIPT_FOREIGN_CORPORA",
    cards: foreign.map { |o| o[:name] }.sort,
    note: "Report-only. These cards belong to a corpus ingested by a different " \
          "pipeline, so no transcript export can ever match them. They are " \
          "EXCLUDED FROM THE READABLE ORPHAN SIGNAL ONLY: every one is counted " \
          "and named here, no classification is changed, and nothing is " \
          "deleted, re-filed or rewritten."
  }
end

def orphan_summary(classified)
  by_class = classified.group_by { |o| o[:classification] }
                       .transform_values(&:length)
  stale = classified.select { |o| o[:classification] == "stale_chunk" }
                    .map { |o| o[:name] }.sort
  native = classified.reject { |o| o[:foreign_corpus] }
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
    unexpected: classified.count { |o| o[:classification] == "unexpected_planned_chunk" },
    # Additive: the same counts with foreign corpora removed. Every key above
    # keeps the value it had before foreign-corpus labelling existed.
    foreign_corpus: classified.count { |o| o[:foreign_corpus] },
    by_classification_excluding_foreign:
      native.group_by { |o| o[:classification] }.transform_values(&:length)
  }
end

# ------------------------------------------------------------
# Structural ancestor stubs (report only)
# ------------------------------------------------------------
# Counts AND names every card relabelled out of vanished_transcript, together
# with the planned card each one exists to file. Relabelled must never mean
# hidden: the whole point is that a reviewer can check the claim.
def structural_ancestor_summary(classified)
  stubs = classified.select { |o| o[:classification] == "structural_ancestor_stub" }
  return nil if stubs.empty?

  {
    total: stubs.length,
    cards: stubs.map { |o| o[:name] }.sort,
    evidence: stubs.sort_by { |o| o[:name].to_s }.map do |o|
      { name: o[:name],
        planned_cards_beneath: o[:structural_ancestor_count],
        examples: o[:structural_ancestor_of] }
    end,
    note: "Report-only. Each of these is an EMPTY live card that exists only " \
          "because a planned card is filed beneath it - Decko creates the " \
          "left-hand part of a compound name itself. They were previously " \
          "counted as vanished_transcript/undated_legacy, which read as lost " \
          "meetings. Only cards that are both a strict ancestor of a planned " \
          "card AND empty when read from the deck are relabelled; a non-empty " \
          "ancestor stays a vanished_transcript. Nothing is deleted, " \
          "re-filed or rewritten."
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
# Rendering: transcript data -> the exact cards it produces
# ============================================================

# The single source of truth for "what cards does this transcript become, and
# what are their exact bytes". Pure: no database, no filesystem, no clock.
#
# Returns an ordered array of { name:, content:, role: } where role is
# :single, :index or :chunk. The ordering is the write order: the index card
# first, then chunk-1..chunk-N.
#
# WHY THIS IS EXTRACTED: scripts/apply_transcript_delta.rb must write exactly
# the bytes the delta planner hashed, and the only way to guarantee that
# without embedding ~80MB of transcript bodies in a manifest is for both sides
# to call the same renderer and verify the sha256 matches the manifest. If this
# function's output ever changes, every manifest row mismatches and the applier
# halts - which is the desired behaviour, not a bug.
def render_transcript_cards_from_data(data, base_card_name)
  full_text = data["full_text"] || ""
  meeting_name = data["meeting_name"] || "Unknown"
  date = data["date"] || "unknown"

  header_html = format_transcript_header(data)
  text_html = format_full_text(full_text)
  full_html = header_html + "\n" + text_html

  if full_html.length <= MAX_CARD_CHARS
    return [{ name: base_card_name, content: full_html, role: :single }]
  end

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

  rendered = [{ name: base_card_name, content: index_content, role: :index }]

  chunks.each_with_index do |chunk_lines, idx|
    chunk_num = idx + 1
    chunk_text = chunk_lines.join("\n")
    chunk_content = <<~HTML
      <p><strong>Source:</strong> #{escape_html(data["source_service"])} — #{escape_html(meeting_name)} (part #{chunk_num}/#{chunks.length})</p>
      <p><strong>Date:</strong> #{escape_html(date)}</p>
      <hr>
      <pre>#{escape_html(chunk_text)}</pre>
    HTML

    rendered << { name: "#{base_card_name}+chunk-#{chunk_num}",
                  content: chunk_content, role: :chunk }
  end

  rendered
end

# Same thing, from a path. Separated so the applier can hash the export file
# before parsing it.
def render_transcript_cards(json_path, base_card_name)
  render_transcript_cards_from_data(JSON.parse(File.read(json_path)), base_card_name)
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

  rendered = render_transcript_cards_from_data(data, base_card_name)

  # Provenance for the write manifest: which export file, which transcript and
  # which role produced each planned card name. Recorded during planning so a
  # later applier never has to guess, and so the manifest can pin the export
  # file it must re-render from. Read-only bookkeeping.
  rendered.each_with_index do |c, i|
    DELTA_SOURCES[c[:name]] = {
      source_path: json_path,
      source_basename: File.basename(json_path),
      transcript_id: data["transcript_id"].to_s,
      base_card: base_card_name,
      role: c[:role].to_s,
      render_index: i,
      render_total: rendered.length
    }
  end

  if rendered.length == 1 && rendered.first[:role] == :single
    create_or_update_card(base_card_name, rendered.first[:content])
    return 1
  end

  puts "  Content too large. Splitting into #{rendered.length - 1} chunks"

  rendered.each { |c| create_or_update_card(c[:name], c[:content]) }

  rendered.length
end

# ============================================================
# Delta write manifest (report-only construction)
# ============================================================

# Freeze the planned write set into a manifest that an applier can execute
# against, without embedding a single byte of transcript text.
#
# Each row is identified by (card name, action) and pinned by three hashes:
#   live_hash    - the live card's content sha256 at plan time. nil for a
#                  create, in which case the applier requires the card to be
#                  absent. For an update the applier re-reads and must see
#                  either this hash (pending) or desired_hash (already
#                  applied / idempotent resume); anything else is drift.
#   desired_hash - the sha256 the applier must produce. It re-renders from
#                  source_path and refuses to write unless the re-render
#                  hashes to exactly this.
#   source_sha256 - the export file's own sha256, so a changed export is
#                  caught before any card is touched.
#
# Everything else in the manifest is a refusal condition, not information:
# counts the applier re-derives and compares, the protected/keep lists it must
# verify untouched, and the explicit zeroes for every destructive class.
def build_delta_manifest(transcripts, orphans, shrinks, stale_chunk_names,
                         orphan_stats, foreign_stats, structural_stats = nil)
  rows = []
  source_digests = {}

  STATS[:cards].each do |c|
    action = c[:action].to_s
    next unless %w[create update].include?(action)

    prov = DELTA_SOURCES[c[:name]]
    raise "no render provenance for planned card #{c[:name].inspect}" unless prov

    path = prov[:source_path]
    source_digests[path] ||= Digest::SHA256.hexdigest(File.binread(path))

    rows << {
      card_name: c[:name],
      card_key: name_key(c[:name]),
      action: action,
      reason: c[:reason],
      role: prov[:role],
      base_card: prov[:base_card],
      transcript_id: prov[:transcript_id],
      source_basename: prov[:source_basename],
      source_sha256: source_digests[path],
      render_index: prov[:render_index],
      render_total: prov[:render_total],
      type_code: "raw_data",
      live_hash: c[:hash_before],
      desired_hash: c[:hash_after],
      live_chars: c[:chars_before],
      desired_chars: c[:chars_after]
    }
  end

  creates = rows.count { |r| r[:action] == "create" }
  updates = rows.count { |r| r[:action] == "update" }

  protected_keys = DELTA_PROTECTED_NAMES.to_h { |n| [name_key(n), n] }
  in_scope_protected = rows.select { |r| protected_keys.key?(r[:card_key]) }
  foreign_in_scope = rows.select { |r| foreign_corpus(r[:card_name]) }

  {
    manifest_version: DELTA_MANIFEST_VERSION,
    generated_utc: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    generator: "scripts/ingest_transcripts.rb delta planner",
    confirm_token: DELTA_CONFIRM_TOKEN,

    # --- target environment (the applier refuses a non-loopback origin) ---
    target_environment: "local_loopback_only",
    production_contacted: false,
    deck_origin_at_plan_time: ENV["DECK_ORIGIN"].to_s,

    # --- provenance of the plan itself ---
    export_dir: EXPORT_DIR,
    parent_card: PARENT_CARD,
    max_card_chars: MAX_CARD_CHARS,
    baseline: (card_api_available? ? "live-content-hash" : "none-no-card-api"),
    baseline_available: card_api_available?,
    hash_algorithm: "sha256",
    hash_normalization: ["none_required_no_export_timestamp"],
    transcript_count: transcripts.length,
    export_files_pinned: source_digests.length,

    # --- the write set ---
    write_set: {
      creates: creates,
      updates: updates,
      total: rows.length,
      skipped_unchanged: STATS[:skipped_unchanged]
    },
    rows: rows,

    # --- everything the applier must NOT do, stated as zeroes it checks ---
    deletes_in_scope: 0,
    trashes_in_scope: 0,
    renames_in_scope: 0,
    orphan_cleanup_in_scope: 0,
    stale_chunk_prunes_in_scope: 0,
    destructive_path_exists: false,

    # --- preservation set: named so the applier can verify, not infer ---
    preserve: {
      policy: STALE_CHUNK_POLICY,
      keep_stale_chunks: KEEP_STALE_CHUNKS,
      stale_chunk_cards: stale_chunk_names,
      stale_chunk_cards_total: stale_chunk_names.length,
      shrinking_chunk_transcripts: shrinks.length,
      orphan_cards_total: orphans.length,
      orphan_cards_excluding_foreign:
        orphan_stats ? orphan_stats[:total] - (foreign_stats ? foreign_stats[:total] : 0) : nil,
      foreign_corpus_cards: foreign_stats ? foreign_stats[:total] : 0,
      foreign_corpora: FOREIGN_CORPORA,
      # Additive: the empty left-hand cards Decko itself created to file
      # planned rows. Named so the applier's preservation check can see them
      # and so "orphans went up by N" is explained rather than tolerated.
      structural_ancestor_stub_cards: structural_stats ? structural_stats[:cards] : [],
      structural_ancestor_stub_total: structural_stats ? structural_stats[:total] : 0,
      protected_names: DELTA_PROTECTED_NAMES,
      note: "Every card listed here must be byte-identical after the apply. " \
            "The applier reads them before and after and halts on any change. " \
            "Nothing here is deleted, pruned, re-filed or rewritten."
    },

    # --- static scope assertions the applier re-checks ---
    scope: {
      actions_allowed: %w[create update],
      protected_rows_in_write_set: in_scope_protected.map { |r| r[:card_name] },
      foreign_corpus_rows_in_write_set: foreign_in_scope.map { |r| r[:card_name] },
      all_rows_under_parent:
        rows.all? { |r| r[:card_key].start_with?("#{name_key(PARENT_CARD)}+") },
      unique_card_names: rows.map { |r| r[:card_key] }.uniq.length == rows.length,
      every_row_has_desired_hash: rows.all? { |r| !r[:desired_hash].to_s.empty? },
      every_update_has_live_hash:
        rows.select { |r| r[:action] == "update" }.all? { |r| !r[:live_hash].to_s.empty? },
      every_create_has_no_live_hash:
        rows.select { |r| r[:action] == "create" }.all? { |r| r[:live_hash].nil? }
    },

    blocking: {
      unexpected_planned_chunks: orphan_stats ? orphan_stats[:unexpected] : nil,
      no_live_baseline: card_api_available? ? 0 : 1,
      stale_chunk_cards: (KEEP_STALE_CHUNKS ? 0 : stale_chunk_names.length),
      protected_rows_in_write_set: in_scope_protected.length,
      foreign_corpus_rows_in_write_set: foreign_in_scope.length
    },

    note: "Frozen plan, not an authorization. scripts/apply_transcript_delta.rb " \
          "defaults to dry-run and additionally requires " \
          "TRANSCRIPT_DELTA_WRITE=1, TRANSCRIPT_DELTA_MANIFEST_SHA=<sha256 of " \
          "this file>, TRANSCRIPT_DELTA_CONFIRM=#{DELTA_CONFIRM_TOKEN} and a " \
          "loopback deck origin before it will write anything."
  }
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
  # Report-only: splits the single "vanished_transcript" label into naming
  # generations so the count can be read. Must run before orphan_summary.
  annotate_vanished_generations(orphans, planned_names) if DELTA
  # Report-only: labels cards belonging to a corpus no exporter can produce.
  # Must also run before the summaries, which read :foreign_corpus.
  annotate_foreign_corpora(orphans) if DELTA
  orphan_stats = DELTA ? orphan_summary(orphans) : nil
  vanished_generations = DELTA ? vanished_generation_summary(orphans) : nil
  foreign_corpora_stats = DELTA ? foreign_corpus_summary(orphans) : nil
  structural_stubs = DELTA ? structural_ancestor_summary(orphans) : nil
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

    if vanished_generations
      puts "\n  of the #{vanished_generations[:total]} vanished_transcript card(s), by naming generation:"
      vanished_generations[:by_generation].sort_by { |_, v| -v }.each do |gen, n|
        puts "    #{gen.to_s.ljust(24)} #{n}"
      end
      if vanished_generations[:date_shifted_cards].any?
        puts "    date_shifted means the same series is planned within " \
             "#{vanished_generations[:date_shift_tolerance_days]} day(s):"
        puts "    an exporter date/timezone change duplicates rather than loses content."
      end
      if vanished_generations[:unmatched_cards].any?
        puts "    unmatched - no planned series and nothing planned on that date:"
        vanished_generations[:unmatched_cards].each { |n| puts "      #{n}" }
      end
    end

    if structural_stubs
      puts "\n  structural ancestor stubs: #{structural_stubs[:total]} card(s)"
      puts "    EMPTY left-hand cards Decko creates to file a planned card beneath"
      puts "    them. Previously counted as vanished_transcript/undated_legacy,"
      puts "    which read as lost meetings. Nothing is deleted or re-filed."
      structural_stubs[:evidence].each do |s|
        puts "      #{s[:name]} (#{s[:planned_cards_beneath]} planned card(s) beneath)"
      end
    end

    if foreign_corpora_stats
      puts "\n  foreign corpora excluded from the orphan signal: " \
           "#{foreign_corpora_stats[:total]} card(s)"
      foreign_corpora_stats[:by_corpus].sort_by { |_, v| -v }.each do |corpus, n|
        puts "    #{corpus.to_s.ljust(24)} #{n}"
      end
      puts "    (#{foreign_corpora_stats[:env_var]}) ingested by a different pipeline; " \
           "no transcript export can ever match them."
      puts "    COUNTED AND NAMED, NOT HIDDEN: full list in the JSON report " \
           "under \"foreign_corpora\".\"cards\"."
      puts "    nothing is deleted, re-filed or rewritten on the basis of this exclusion."

      puts "\n  orphans excluding foreign corpora: " \
           "#{orphan_stats[:total] - foreign_corpora_stats[:total]}"
      orphan_stats[:by_classification_excluding_foreign]
        .sort_by { |_, v| -v }.each { |cls, n| puts "    #{cls.to_s.ljust(26)} #{n}" }
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
      report[:vanished_generations] = vanished_generations if vanished_generations
      report[:structural_ancestor_stubs] = structural_stubs if structural_stubs
      report[:foreign_corpora] = foreign_corpora_stats if foreign_corpora_stats
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
        # This script still has no write path. A delta WRITE is performed by
        # scripts/apply_transcript_delta.rb against the frozen manifest below,
        # behind its own write gate / manifest-sha / confirm token / loopback
        # guard. True here would be a lie about THIS file.
        write_path_implemented: false,
        delta_applier: "scripts/apply_transcript_delta.rb",
        delta_manifest_emitted: !DELTA_MANIFEST_PATH.nil?,
        delta_manifest_path: DELTA_MANIFEST_PATH,
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
          stale_chunk_cards: stale_chunk_total,
          # A foreign corpus is an accepted permanent condition, not a
          # decision, so it is acknowledged and never blocking.
          foreign_corpus_cards: foreign_corpora_stats ? foreign_corpora_stats[:total] : 0
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

  # The write manifest is emitted independently of REPORT_PATH so a manifest
  # can be produced without a 600MB report, and vice versa. Still read-only:
  # this writes a local file, never a card.
  if DELTA_MANIFEST_PATH
    manifest = build_delta_manifest(transcripts, orphans, shrinks,
                                    stale_chunk_names, orphan_stats,
                                    foreign_corpora_stats, structural_stubs)
    File.write(DELTA_MANIFEST_PATH, JSON.pretty_generate(manifest))
    sha = Digest::SHA256.hexdigest(File.binread(DELTA_MANIFEST_PATH))
    puts "\nDelta write manifest: #{DELTA_MANIFEST_PATH}"
    puts "  sha256:  #{sha}"
    puts "  creates: #{manifest[:write_set][:creates]}"
    puts "  updates: #{manifest[:write_set][:updates]}"
    puts "  total:   #{manifest[:write_set][:total]}"
    puts "  preserved (never written): " \
         "#{manifest[:preserve][:orphan_cards_total]} orphan card(s), " \
         "#{manifest[:preserve][:stale_chunk_cards_total]} stale chunk card(s), " \
         "#{manifest[:preserve][:foreign_corpus_cards]} foreign-corpus card(s)"
    blocking = manifest[:blocking].reject { |_k, v| v.nil? || v.to_i.zero? }
    if blocking.any?
      puts "  BLOCKING: #{blocking.inspect}"
    else
      puts "  blocking: none"
    end
    puts "  NOT AN AUTHORIZATION. This manifest describes a write; it does not"
    puts "  perform or permit one. Applying it needs scripts/apply_transcript_delta.rb"
    puts "  with TRANSCRIPT_DELTA_WRITE=1, TRANSCRIPT_DELTA_MANIFEST_SHA=#{sha},"
    puts "  TRANSCRIPT_DELTA_CONFIRM=#{DELTA_CONFIRM_TOKEN} and a loopback deck origin."
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
