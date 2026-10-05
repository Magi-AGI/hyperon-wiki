#!/usr/bin/env ruby
# Ingest Mattermost exports into the Hyperon Wiki as RawData cards.
#
# Reads JSON exports produced by mattermost_export.py and creates
# complete, unfiltered RawData cards in the Decko database.
#
# Run via:
#   cat scripts/ingest_mattermost.rb | ssh -T -i <ssh-key-path> <ssh-user>@<wiki-host> \
#     'export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH" && eval "$(rbenv init -)" && \
#      cd <deck-root> && set -a && source .env.production && set +a && \
#      MATTERMOST_INGEST=1 RAILS_ENV=production bundle exec decko runner -'
#
# Or copy to server and run:
#   MATTERMOST_INGEST=1 RAILS_ENV=production bundle exec decko runner scripts/ingest_mattermost.rb
#
# MATTERMOST_INGEST=1 is required under `decko runner`: loading this file must
# never write cards, so the runner has to opt in explicitly. Running the file
# directly (`ruby scripts/ingest_mattermost.rb`) does not need it.
#
# DRY RUN (no database writes at all):
#   MATTERMOST_INGEST=1 MATTERMOST_INGEST_DRY_RUN=1 \
#     MATTERMOST_INGEST_REPORT=/tmp/ingest_plan.json \
#     bundle exec decko runner scripts/ingest_mattermost.rb
#
# DELTA PLANNER (Phase 1 - dry run only, refuses to run with writes enabled):
#   MATTERMOST_INGEST=1 MATTERMOST_INGEST_DRY_RUN=1 MATTERMOST_INGEST_DELTA=1 \
#     MATTERMOST_INGEST_REPORT=/tmp/delta_plan.json \
#     bundle exec decko runner scripts/ingest_mattermost.rb
#
#   Delta mode compares a sha256 of each rendered card against the live card's
#   stored content and classifies it as skip-unchanged / update / create. The
#   per-card "Exported:" timestamp is excluded from the hash, because it changes
#   on every export and would otherwise mark ~94% of cards dirty with identical
#   bodies. There is deliberately NO delta write path yet: setting
#   MATTERMOST_INGEST_DELTA=1 without MATTERMOST_INGEST_DRY_RUN=1 aborts before
#   any database access.
#
# PRIVATE CHANNELS:
#   Mattermost private channels (type "P") are ingested like any other channel,
#   but each resulting card (index and every chunk) also gets a
#   "<card>+*self+*read" rule naming a single party, so only that party (and
#   deck admins) can read it. Configure with:
#     MATTERMOST_PRIVATE_READ_PARTY="Lake Watkins"  # default
#     MATTERMOST_RESTRICT_PRIVATE=0                 # disable (debug only)
#
# Prerequisites:
#   - Mattermost JSON exports in EXPORT_DIR (produced by mattermost_export.py)
#   - The RawData cardtype must exist on the wiki
#   - MATTERMOST_PRIVATE_READ_PARTY must name an existing User or Role card

require 'json'

# ============================================================
# Configuration
# ============================================================

# Path to the Mattermost export directory on the server.
# Upload exports via: scp -i <ssh-key-path> -r mattermost_exports/ <ssh-user>@<wiki-host>:~/
EXPORT_DIR = ENV.fetch("MATTERMOST_EXPORT_DIR",
  File.expand_path("~/mattermost_exports/latest"))

PARENT_CARD = "Raw Data+mattermost"

# Maximum characters per card. Decko can handle large cards but
# we chunk to keep the UI responsive.
MAX_CARD_CHARS = 50_000

# When set, plan and report every card that *would* be written but never touch
# the database. Use this to verify naming/chunking before a real ingest.
DRY_RUN = %w[1 true yes on].include?(
  ENV.fetch("MATTERMOST_INGEST_DRY_RUN", "").strip.downcase
)

# Optional path for a machine-readable plan/result report.
REPORT_PATH = ENV["MATTERMOST_INGEST_REPORT"]

# ------------------------------------------------------------
# Delta planning (Phase 1: analysis only, no write path)
# ------------------------------------------------------------
# When set, every rendered card is hashed and compared against the live card's
# stored content so unchanged cards can be skipped instead of rewritten.
DELTA = %w[1 true yes on].include?(
  ENV.fetch("MATTERMOST_INGEST_DELTA", "").strip.downcase
)

# Phase 1 has no delta write path. Refusing here - before any card is fetched
# or rendered - is the whole safety story: there is no code path in which
# DELTA can reach a database write.
if DELTA && !DRY_RUN
  abort <<~MSG
    MATTERMOST_INGEST_DELTA=1 requires MATTERMOST_INGEST_DRY_RUN=1.

    The delta planner is analysis-only (Phase 1). No delta write path exists
    yet, so running it with writes enabled would silently fall back to the
    full-rewrite behaviour it is meant to replace. Aborting before any
    database access.
  MSG
end


# Files that live in an export dir but are not channel payloads.
NON_CHANNEL_FILES = %w[export_summary.json verification_report.json].freeze

# ------------------------------------------------------------
# Private-channel read restriction
# ------------------------------------------------------------
# Mattermost private channels (type "P") must not be readable by everyone who
# can read public RawData. Without an explicit rule a channel card is governed
# by "RawData+*type+*read" (the Raw Data Analyst role) and each chunk card by
# the same type rule, because "*type" outranks "*all plus" in Decko's set
# pattern precedence.
#
# The fix is a per-card self rule, "<card>+*self+*read", naming exactly one
# party. "*self" is the highest-precedence pattern, so it overrides the type
# rule for that card and nothing else. Chunk cards do NOT inherit from their
# channel card (the type rule beats "*all plus+*read = _left"), so every chunk
# card gets its own rule too.
PRIVATE_READ_PARTY = ENV.fetch("MATTERMOST_PRIVATE_READ_PARTY", "Lake Watkins").strip

# Escape hatch for debugging only. Leaving private channels unrestricted
# publishes them to every Raw Data Analyst, so this defaults to on.
RESTRICT_PRIVATE = !%w[0 false no off].include?(
  ENV.fetch("MATTERMOST_RESTRICT_PRIVATE", "1").strip.downcase
)

# Party types that make sense as a read rule value.
PARTY_TYPES = %w[User Role].freeze

# ============================================================
# Helpers
# ============================================================

def escape_html(text)
  text.to_s
    .gsub("&", "&amp;")
    .gsub("<", "&lt;")
    .gsub(">", "&gt;")
end

# Decko uses "+" as the name joint, so a channel display name containing "+"
# silently creates extra name parts: "LLM+PLN" would be filed as
# "Raw Data+mattermost+LLM+PLN", i.e. a child of a non-existent
# "Raw Data+mattermost+LLM" channel card. Collapse the joint and other
# structurally meaningful characters so a channel is always exactly one part.
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
# offline unit tests where Cardname is not loaded.
def name_key(full_name)
  return full_name.to_name.key if defined?(Cardname)

  full_name.split("+").map { |p| p.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "") }.join("+")
end

# Assign a unique, stable card label to every channel.
#
# Preference order per channel:
#   1. the sanitized display name (kept as-is when it is unambiguous)
#   2. "<display> (<channel slug>)"      - disambiguates duplicate display names
#   3. "<display> (<channel id>)"        - last-resort, always unique
#
# Returns the channels array with :label and :label_reason filled in.
def assign_channel_labels(channels)
  channels.each do |ch|
    ch[:base_label] = sanitize_name_part(ch[:display]) ||
                      sanitize_name_part(ch[:slug]) ||
                      ch[:id]
  end

  # How many channels want each base key? >1 means the base name is ambiguous.
  base_counts = Hash.new(0)
  channels.each { |ch| base_counts[name_key("#{PARENT_CARD}+#{ch[:base_label]}")] += 1 }

  taken = {}
  channels.each do |ch|
    base = ch[:base_label]
    slug = sanitize_name_part(ch[:slug])
    unambiguous = base_counts[name_key("#{PARENT_CARD}+#{base}")] == 1

    candidates = []
    candidates << [base, "display_name"] if unambiguous
    candidates << ["#{base} (#{slug})", "display_name+slug"] if slug
    candidates << ["#{base} (#{ch[:id]})", "display_name+channel_id"]
    candidates << [ch[:id], "channel_id"]

    chosen = nil
    candidates.each do |label, reason|
      key = name_key("#{PARENT_CARD}+#{label}")
      next if taken.key?(key)

      chosen = [label, reason, key]
      break
    end

    raise "Unable to assign a unique card name for channel #{ch[:id]}" unless chosen

    ch[:label], ch[:label_reason], ch[:card_key] = chosen
    ch[:card_name] = "#{PARENT_CARD}+#{ch[:label]}"
    taken[ch[:card_key]] = ch
  end

  dupes = channels.group_by { |ch| ch[:card_key] }.select { |_k, v| v.length > 1 }
  unless dupes.empty?
    raise "Card name collision unresolved: " +
          dupes.map { |k, v| "#{k} <- #{v.map { |c| c[:id] }.join(', ')}" }.join("; ")
  end

  channels
end

def format_post(post, threads)
  lines = []
  username = escape_html(post["username"] || "?")
  created = (post["created"] || "?")[0..18]
  message = escape_html(post["message"] || "")

  if post["orphan_reply"]
    # Retained by the date filter although its thread root was not.
    root_ref = escape_html(post["root_id"] || "?")
    lines << "<p><strong>#{username}</strong> (#{created}) " \
             "<em>[reply; thread root #{root_ref} outside export window]</em></p>"
  else
    lines << "<p><strong>#{username}</strong> (#{created})</p>"
  end
  lines << "<p>#{message}</p>"

  # Thread replies
  post_id = post["id"]
  if threads && threads[post_id]
    lines << "<blockquote>"
    threads[post_id].each do |reply|
      r_user = escape_html(reply["username"] || "?")
      r_time = (reply["created"] || "?")[0..18]
      r_msg  = escape_html(reply["message"] || "")
      lines << "<p><strong>#{r_user}</strong> (#{r_time})</p>"
      lines << "<p>#{r_msg}</p>"
    end
    lines << "</blockquote>"
  end

  lines << "<hr>"
  lines.join("\n")
end

# Collects what happened (or would happen) for the final report.
STATS = {
  created: 0, updated: 0, errors: 0, planned_create: 0, planned_update: 0, cards: [],
  perm_created: 0, perm_updated: 0, perm_errors: 0,
  planned_perm_create: 0, planned_perm_update: 0, perms: [],
  skipped_unchanged: 0, perm_skipped_unchanged: 0
}

# ============================================================
# Delta hashing
# ============================================================

require "digest"
require "set"

# The per-card "Exported:" line carries the export run's timestamp, so it
# changes on every export even when no post did. Measured on two real snapshots
# it alone accounted for 182 of 193 "changed" cards. Excluding it from the hash
# is what makes the delta honest; it is NOT removed from the written content,
# so this changes nothing about what a real ingest would store.
EXPORTED_HEADER_RE = %r{^[ \t]*<p><strong>Exported:</strong>[^\n]*</p>\x0D?\x0A?}.freeze

def normalize_for_hash(content)
  content.to_s.gsub(EXPORTED_HEADER_RE, "")
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

# A read rule's *items*, not its raw content.
#
# The write path sets content to "[[Party]]", but a read rule is a List card
# and Decko normalizes that to the bare "Party" on save. Comparing the raw
# string would therefore report every already-correct rule as an update
# forever (measured: 17 of 17 on a deck whose rules were all correct).
# Items are the actual semantics of the rule, so they are what we compare.
#
# Returns nil when the rule card does not exist, which the caller
# distinguishes from an existing-but-wrong rule.
def live_rule_items(name)
  return nil unless defined?(Card)

  card = begin
    Card::Auth.as_bot { Card.fetch(name) }
  rescue StandardError
    nil
  end
  return nil if card.nil? || card.trash

  items = begin
    card.item_names
  rescue StandardError
    nil
  end
  # Fall back to parsing the raw content for non-List storage.
  items ||= card.content.to_s.scan(/\[\[([^\]]+)\]\]/).flatten
  items = [card.content.to_s] if items.empty? && !card.content.to_s.strip.empty?

  items.map { |i| i.to_s.strip }.reject(&:empty?)
end

# Why does this card differ? Derived from the rendered vs live content so the
# report is reviewable without re-reading both bodies.
POSTS_IN_CHUNK_RE = %r{<p><strong>Posts in chunk:</strong>\s*(\d+)</p>}.freeze
POSTS_RE = %r{<p><strong>Posts:</strong>\s*(\d+)</p>}.freeze

def body_after_header(content)
  i = content.to_s.index("<hr>")
  i ? content.to_s[(i + 4)..] : content.to_s
end

def post_count_marker(content)
  m = POSTS_IN_CHUNK_RE.match(content.to_s) || POSTS_RE.match(content.to_s)
  m && m[1].to_i
end

def change_reason(live, rendered)
  return "missing_card" if live.nil?

  if body_after_header(normalize_for_hash(live)) ==
     body_after_header(normalize_for_hash(rendered))
    return "channel_meta_changed"
  end

  before = post_count_marker(live)
  after  = post_count_marker(rendered)
  if before && after && after > before
    "posts_added"
  elsif before && after && after < before
    "posts_removed"
  else
    "post_edited"
  end
end

# Live cards under PARENT_CARD that the plan does not account for.
#
# Identity is Decko's key, not the display name: the deck stores this branch as
# "RawData+mattermost+..." while PARENT_CARD is "Raw Data+mattermost", and both
# resolve to the same key. Comparing raw strings reports every card as both an
# orphan and a create. Compound Decko cards can also carry a NULL name column,
# so descendants are walked by left_id rather than matched by name prefix.
#
# Report only. Nothing is deleted, in delta mode or otherwise.
def live_descendant_names(parent_name)
  return [] unless defined?(Card)

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

def find_orphans(_channels)
  return [] unless defined?(Card)

  planned_keys = STATS[:cards].map { |c| name_key(c[:name]) }.to_set
  rule_keys = STATS[:perms].map { |p| name_key(p[:rule]) }.to_set

  live_descendant_names(PARENT_CARD).reject do |nm|
    key = name_key(nm)
    planned_keys.include?(key) || rule_keys.include?(key) ||
      # "+*self" set cards exist only to hold the "+*read" rule below them.
      nm.end_with?("+*self")
  end.map { |nm| { name: nm, key: name_key(nm) } }
end

# Planned vs live chunk count per channel. A growing count means new chunk
# cards plus an index rewrite; a shrinking one leaves orphan chunks behind.
# Reported so a chunk cascade is visible before any write (§5.3).
def chunk_count_changes(channels)
  return [] unless defined?(Card)

  live_keys = live_descendant_names(PARENT_CARD).map { |nm| name_key(nm) }.to_set

  channels.filter_map do |ch|
    planned = STATS[:cards].count do |c|
      c[:name].to_s.start_with?("#{ch[:card_name]}+chunk-")
    end

    live = (1..).lazy.map { |i| name_key("#{ch[:card_name]}+chunk-#{i}") }
                     .take_while { |k| live_keys.include?(k) }.to_a.length

    next if planned == live

    { channel_id: ch[:id], display_name: ch[:display],
      card_name: ch[:card_name], live_chunks: live, planned_chunks: planned,
      delta: planned - live }
  end
end

# A channel whose planned card name is absent from the live deck. Phase 1
# reports; it never re-files a card (§5.1 of the design).
def find_name_binding_conflicts(channels)
  return [] unless defined?(Card)

  live_keys = live_descendant_names(PARENT_CARD).map { |nm| name_key(nm) }.to_set
  channels.reject { |ch| live_keys.include?(name_key(ch[:card_name])) }
          .map do |ch|
    { channel_id: ch[:id], display_name: ch[:display], slug: ch[:slug],
      planned_card_name: ch[:card_name], planned_key: name_key(ch[:card_name]),
      label_reason: ch[:label_reason], reason: "planned_name_absent_from_live" }
  end
end


# ============================================================
# Private-channel permissions
# ============================================================

# The read rule card for a single card's own set: "<card>+*self+*read".
def self_read_rule_name(card_name)
  "#{card_name}+*self+*read"
end

# Resolve the configured party once, so a typo fails loudly before any write
# instead of silently producing an unreadable (or over-readable) card.
def resolve_private_party!
  return @private_party if defined?(@private_party)

  @private_party =
    if !defined?(Card)
      # Offline unit tests: trust the configured name.
      { name: PRIVATE_READ_PARTY, id: nil, type: nil, resolved: false }
    else
      card = Card::Auth.as_bot { Card.fetch(PRIVATE_READ_PARTY) }
      unless card
        raise "Private read party #{PRIVATE_READ_PARTY.inspect} does not exist on this deck. " \
              "Set MATTERMOST_PRIVATE_READ_PARTY to an existing User or Role card."
      end

      type = card.type_name.to_s
      unless PARTY_TYPES.include?(type)
        raise "Private read party #{PRIVATE_READ_PARTY.inspect} is a #{type}, " \
              "not one of #{PARTY_TYPES.join('/')}; it cannot be used as a read rule value."
      end

      { name: card.name.to_s, id: card.id, type: type, resolved: true }
    end
end

# Point "<card>+*self+*read" at exactly the private party.
#
# Decko's read rule is a List card whose items are parties. Writing a single
# item means: only that party (plus deck admins, who bypass read checks by
# design via Card::Auth.always_ok?) can read the card.
def restrict_card_to_private_party(card_name)
  return unless RESTRICT_PRIVATE

  party = resolve_private_party!
  rule_name = self_read_rule_name(card_name)

  if DELTA
    # Gate on the rule's current items: an already-correct rule is 0 writes,
    # while a tampered or missing one still shows up as work to do.
    #
    # Compared as items, not raw content: Decko stores the written
    # "[[Party]]" as the bare "Party", so a literal string compare marks
    # every correct rule dirty on every run. Key-normalized so a display-name
    # variant of the same party is not treated as a difference.
    desired = "[[#{party[:name]}]]"
    live_items = live_rule_items(rule_name)

    if live_items
      live_keys = live_items.map { |i| name_key(i) }
      if live_keys == [name_key(party[:name])]
        STATS[:perm_skipped_unchanged] += 1
        STATS[:perms] << { card: card_name, rule: rule_name, party: party[:name],
                           action: "skip-unchanged", reason: "rule_matches",
                           live_items: live_items }
        return
      end

      STATS[:planned_perm_update] += 1
      STATS[:perms] << { card: card_name, rule: rule_name, party: party[:name],
                         action: "update", reason: "rule_value_differs",
                         live_items: live_items,
                         content_before: live_items.join(", "),
                         content_after: desired }
      puts "  [delta] would set read rule: #{rule_name} -> #{party[:name]}"
    else
      STATS[:planned_perm_create] += 1
      STATS[:perms] << { card: card_name, rule: rule_name, party: party[:name],
                         action: "create", reason: "rule_missing",
                         content_before: nil, content_after: desired }
      puts "  [delta] would create read rule: #{rule_name} -> #{party[:name]}"
    end
    return
  end

  if DRY_RUN
    exists = card_exists?(rule_name)
    exists ? STATS[:planned_perm_update] += 1 : STATS[:planned_perm_create] += 1
    STATS[:perms] << {
      card: card_name, rule: rule_name, party: party[:name],
      action: exists ? "update" : "create"
    }
    puts "  [dry-run] #{exists ? 'would set' : 'would create'} read rule: " \
         "#{rule_name} -> #{party[:name]}"
    return
  end

  Card::Auth.as_bot do
    rule = begin
      Card.fetch(rule_name)
    rescue StandardError
      nil
    end

    if rule
      rule.update!(content: "[[#{party[:name]}]]")
      STATS[:perm_updated] += 1
      STATS[:perms] << { card: card_name, rule: rule_name, party: party[:name],
                         action: "updated" }
      puts "  Read rule set: #{rule_name} -> #{party[:name]}"
    else
      # No type_code: the "+*read" right set assigns List automatically.
      Card.create!(name: rule_name, content: "[[#{party[:name]}]]")
      STATS[:perm_created] += 1
      STATS[:perms] << { card: card_name, rule: rule_name, party: party[:name],
                         action: "created" }
      puts "  Read rule created: #{rule_name} -> #{party[:name]}"
    end
  end
rescue => e
  STATS[:perm_errors] += 1
  STATS[:perms] << { card: card_name, rule: self_read_rule_name(card_name),
                     action: "error", error: e.message }
  puts "  ERROR setting read rule for #{card_name}: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

def card_exists?(name)
  return false unless defined?(Card)

  !!begin
    Card.fetch(name)
  rescue StandardError
    nil
  end
end

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
    STATS[:cards] << { name: name, chars: content.length, action: exists ? "update" : "create" }
    puts "  [dry-run] #{exists ? 'would update' : 'would create'}: #{name} (#{content.length} chars)"
    return
  end

  Card::Auth.as_bot do
    card = begin
      Card.fetch(name)
    rescue
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
        STATS[:cards] << { name: name, chars: content.length, action: "updated_after_conflict" }
        puts "  Updated (after conflict): #{name}"
      else
        raise
      end
    end
  end
rescue => e
  STATS[:errors] += 1
  STATS[:cards] << { name: name, action: "error", error: e.message }
  puts "  ERROR on #{name}: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# ============================================================
# Main: Process each channel export
# ============================================================

def ingest_channel(json_path, card_base_name, private_channel: false)
  data = JSON.parse(File.read(json_path))
  channel = data["channel"]
  posts = data["posts"] || []
  threads = data["threads"] || {}

  unless channel
    puts "Skipping non-channel JSON: #{json_path}"
    return
  end

  channel_name = channel["display_name"]
  post_count = channel["post_count"] || posts.length
  thread_count = channel["thread_count"] || threads.length
  exported_at = channel["exported_at"]
  purpose = channel["purpose"] || ""
  header_text = channel["header"] || ""
  visibility = channel["type"] == "P" ? "private" : "public"

  puts "\n#{'=' * 60}"
  puts "Channel: #{channel_name} (#{post_count} posts, #{thread_count} threads)"
  puts "Card:    #{card_base_name}"
  puts "=" * 60

  # Build full HTML for all posts (no filtering, no truncation)
  all_posts_html = []
  root_posts = posts.reject { |p| p["is_reply"] }

  root_posts.each do |post|
    all_posts_html << format_post(post, threads)
  end

  full_html = all_posts_html.join("\n")

  # Build header
  channel_header = <<~HTML
    <p><strong>Source:</strong> Mattermost — #{escape_html(channel_name)}</p>
    <p><strong>Channel:</strong> #{escape_html(channel['name'])} (#{visibility})</p>
    <p><strong>Exported:</strong> #{exported_at}</p>
    <p><strong>Posts:</strong> #{post_count}</p>
    <p><strong>Threads:</strong> #{thread_count}</p>
    #{purpose.empty? ? '' : "<p><strong>Purpose:</strong> #{escape_html(purpose)}</p>"}
    #{header_text.empty? ? '' : "<p><strong>Header:</strong> #{escape_html(header_text)}</p>"}
    <hr>
  HTML

  # If content fits in one card, create a single card
  if (channel_header.length + full_html.length) <= MAX_CARD_CHARS
    create_or_update_card(card_base_name, channel_header + full_html)
    restrict_card_to_private_party(card_base_name) if private_channel
    return 1
  end

  # Otherwise, chunk into multiple cards
  chunks = []
  current_chunk = []
  current_length = 0

  all_posts_html.each do |post_html|
    if current_length + post_html.length > MAX_CARD_CHARS && !current_chunk.empty?
      chunks << current_chunk
      current_chunk = []
      current_length = 0
    end
    current_chunk << post_html
    current_length += post_html.length
  end
  chunks << current_chunk unless current_chunk.empty?

  puts "  Content too large for single card. Splitting into #{chunks.length} chunks."

  # Create index card
  chunk_links = (1..chunks.length).map do |i|
    "<li>{{#{card_base_name}+chunk-#{i}|view:link;title:_R}}</li>"
  end

  index_content = channel_header + <<~HTML
    <p><strong>Content split into #{chunks.length} chunks:</strong></p>
    <ol>
    #{chunk_links.join("\n")}
    </ol>
  HTML

  create_or_update_card(card_base_name, index_content)
  restrict_card_to_private_party(card_base_name) if private_channel

  # Create chunk cards
  chunks.each_with_index do |chunk_posts, idx|
    chunk_num = idx + 1
    chunk_content = <<~HTML
      <p><strong>Source:</strong> Mattermost — #{escape_html(channel_name)} (chunk #{chunk_num}/#{chunks.length})</p>
      <p><strong>Posts in chunk:</strong> #{chunk_posts.length}</p>
      <hr>
      #{chunk_posts.join("\n")}
    HTML

    chunk_name = "#{card_base_name}+chunk-#{chunk_num}"
    create_or_update_card(chunk_name, chunk_content)
    # A chunk card is governed by "RawData+*type+*read", which outranks the
    # "_left" inheritance rule, so it needs its own self rule.
    restrict_card_to_private_party(chunk_name) if private_channel
  end

  chunks.length + 1
end

# ============================================================
# Entry point
# ============================================================

def run!
  puts "Hyperon Wiki Mattermost Ingestion#{DRY_RUN ? ' (DRY RUN - no database writes)' : ''}"
  puts "Export directory: #{EXPORT_DIR}"
  puts "Parent card: #{PARENT_CARD}"
  puts

  unless Dir.exist?(EXPORT_DIR)
    puts "ERROR: Export directory not found: #{EXPORT_DIR}"
    puts "Run mattermost_export.py first, then copy exports to the server."
    exit 1
  end

  # Find all channel JSON files
  json_files = Dir.glob("#{EXPORT_DIR}/**/*.json")
    .reject { |f| NON_CHANNEL_FILES.include?(File.basename(f)) }
    .sort

  puts "Found #{json_files.length} channel exports"

  # Pass 1: read channel metadata only, so names can be deduplicated globally
  # before anything is written.
  channels = []
  json_files.each do |f|
    meta = JSON.parse(File.read(f))["channel"]
    unless meta
      puts "Skipping non-channel JSON: #{f}"
      next
    end
    channels << {
      path: f, id: meta["id"], slug: meta["name"], display: meta["display_name"],
      type: meta["type"], posts: meta["post_count"], threads: meta["thread_count"]
    }
  end

  assign_channel_labels(channels)

  renamed = channels.reject { |ch| ch[:label_reason] == "display_name" }
  unless renamed.empty?
    puts "\nDisambiguated #{renamed.length} channel card name(s):"
    renamed.each do |ch|
      puts "  #{ch[:display].inspect} -> #{ch[:label].inspect} (#{ch[:label_reason]})"
    end
  end

  sanitized = channels.select { |ch| ch[:base_label] != ch[:display].to_s }
  unless sanitized.empty?
    puts "\nSanitized #{sanitized.length} channel display name(s) for Decko naming:"
    sanitized.each { |ch| puts "  #{ch[:display].inspect} -> #{ch[:base_label].inspect}" }
  end

  # Pass 2: ingest
  private_count = channels.count { |ch| ch[:type] == "P" }
  if private_count.positive?
    if RESTRICT_PRIVATE
      party = resolve_private_party!
      puts "\nPrivate channels: #{private_count}; read access restricted to " \
           "#{party[:name].inspect}#{party[:id] ? " (card #{party[:id]}, #{party[:type]})" : ''}"
    else
      puts "\nWARNING: MATTERMOST_RESTRICT_PRIVATE is off - #{private_count} private " \
           "channel(s) will be readable by anyone who can read RawData."
    end
  end

  channels.each_with_index do |ch, idx|
    puts "\n[#{idx + 1}/#{channels.length}] #{File.basename(ch[:path])}"
    ch[:private] = ch[:type] == "P"
    ch[:cards_written] = ingest_channel(ch[:path], ch[:card_name],
                                        private_channel: ch[:private])
  end

  total_cards = STATS[:cards].length
  orphans = DELTA ? find_orphans(channels) : []
  name_conflicts = DELTA ? find_name_binding_conflicts(channels) : []
  puts "\n#{'=' * 60}"
  puts DRY_RUN ? "Dry run complete - nothing was written." : "Ingestion complete!"
  puts "Total channels: #{channels.length}"
  puts "  public:  #{channels.count { |c| c[:type] != 'P' }}"
  puts "  private: #{channels.count { |c| c[:type] == 'P' }}"
  puts "Total cards: #{total_cards}"
  if DELTA
    puts "  skipped unchanged: #{STATS[:skipped_unchanged]}"
    puts "  would create:      #{STATS[:planned_create]}"
    puts "  would update:      #{STATS[:planned_update]}"
    puts "  orphaned:          #{orphans.length}"
    puts "Private read rules: #{STATS[:perms].length}"
    puts "  skipped unchanged: #{STATS[:perm_skipped_unchanged]}"
    puts "  would create:      #{STATS[:planned_perm_create]}"
    puts "  would update:      #{STATS[:planned_perm_update]}"
    puts "Name binding conflicts: #{name_conflicts.length}"
  elsif DRY_RUN
    puts "  would create: #{STATS[:planned_create]}"
    puts "  would update: #{STATS[:planned_update]}"
    puts "Private read rules: #{STATS[:perms].length}"
    puts "  would create: #{STATS[:planned_perm_create]}"
    puts "  would update: #{STATS[:planned_perm_update]}"
  else
    puts "  created: #{STATS[:created]}"
    puts "  updated: #{STATS[:updated]}"
    puts "  errors:  #{STATS[:errors]}"
    puts "Private read rules: #{STATS[:perms].length}"
    puts "  created: #{STATS[:perm_created]}"
    puts "  updated: #{STATS[:perm_updated]}"
    puts "  errors:  #{STATS[:perm_errors]}"
  end
  puts "=" * 60

  if REPORT_PATH
    report = {
      mode: (DELTA ? "delta" : (DRY_RUN ? "full-dry-run" : "full-write")),
      baseline: (DELTA ? "live-content-hash" : nil),
      hash_normalization: (DELTA ? ["exported_at_header_excluded"] : nil),
      dry_run: DRY_RUN,
      export_dir: EXPORT_DIR,
      parent_card: PARENT_CARD,
      max_card_chars: MAX_CARD_CHARS,
      restrict_private: RESTRICT_PRIVATE,
      private_read_party: (RESTRICT_PRIVATE ? resolve_private_party! : nil),
      channel_count: channels.length,
      channels_total: channels.length,
      public_channels: channels.count { |c| c[:type] != "P" },
      private_channels: channels.count { |c| c[:type] == "P" },
      total_posts: channels.sum { |c| c[:posts].to_i },
      total_threads: channels.sum { |c| c[:threads].to_i },
      card_count: total_cards,
      permission_card_count: STATS[:perms].length,
      stats: STATS.reject { |k, _| %i[cards perms].include?(k) },
      channels: channels.map do |c|
        {
          id: c[:id], slug: c[:slug], display_name: c[:display], type: c[:type],
          private: c[:type] == "P",
          card_name: c[:card_name], card_key: c[:card_key],
          label_reason: c[:label_reason], cards_written: c[:cards_written],
          posts: c[:posts], threads: c[:threads]
        }
      end,
      cards: STATS[:cards],
      permissions: STATS[:perms]
    }

    if DELTA
      report[:cards_summary] = {
        total: total_cards,
        skipped_unchanged: STATS[:skipped_unchanged],
        planned_create: STATS[:planned_create],
        planned_update: STATS[:planned_update],
        orphaned: orphans.length
      }
      report[:permissions_summary] = {
        total: STATS[:perms].length,
        skipped_unchanged: STATS[:perm_skipped_unchanged],
        planned_create: STATS[:planned_perm_create],
        planned_update: STATS[:planned_perm_update]
      }
      report[:orphans] = orphans
      report[:name_binding_conflicts] = name_conflicts
      report[:chunk_count_changes] = chunk_count_changes(channels)
      report[:reasons] = STATS[:cards].group_by { |c| c[:reason] }
                                      .transform_values(&:length)
      report[:cards_detail] = STATS[:cards].reject { |c| c[:action] == "skip-unchanged" }
    end

    File.write(REPORT_PATH, JSON.pretty_generate(report))
    puts "Report written to #{REPORT_PATH}"
  end

  STATS[:errors] + STATS[:perm_errors]
end

# ------------------------------------------------------------
# Entry point
# ------------------------------------------------------------
# Only auto-run when this file is the program being executed, or when a
# Decko runner is explicitly asking for an ingest.
#
# The previous guard was `$PROGRAM_NAME == __FILE__ || defined?(Card)`.
# Inside a Decko/Rails process `Card` is ALWAYS defined, so *merely loading*
# this file — an autoload, a console `load`, a test `require`, or anything
# that happened to sweep the scripts directory — kicked off a full ingest
# that wrote cards to the live database. Loading a file must never mutate
# the deck.
#
# `decko runner` evaluates the script rather than setting $PROGRAM_NAME to
# it (notably `runner -`, which streams the script over stdin), so the
# runner path opts in explicitly via MATTERMOST_INGEST=1.
RUN_REQUESTED = ENV["MATTERMOST_INGEST"] == "1"

run! if $PROGRAM_NAME == __FILE__ || RUN_REQUESTED
