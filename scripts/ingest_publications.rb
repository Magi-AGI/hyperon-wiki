#!/usr/bin/env ruby
# Ingest publication full texts into the Hyperon Wiki as RawData cards.
#
# Run via:
#   cat scripts/ingest_publications.rb | ssh -T -i ~/.ssh/hyperon-key.pem ubuntu@54.183.80.144 \
#     'export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH" && eval "$(rbenv init -)" && \
#      cd ~/hyperon-wiki && set -a && source .env.production && set +a && \
#      RAILS_ENV=production bundle exec decko runner -'

require 'json'

EXPORT_DIR = ENV.fetch("PUBLICATION_EXPORT_DIR",
  File.expand_path("~/transcript_exports/publications"))

MAX_CARD_CHARS = 50_000

def escape_html(text)
  text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
end

def create_or_update_card(name, content, type_code = :raw_data)
  Card::Auth.as_bot do
    card = Card.fetch(name) rescue nil
    begin
      if card
        card.update!(content: content)
        puts "  Updated: #{name} (#{content.length} chars)"
      else
        Card.create!(name: name, type_code: type_code, content: content)
        puts "  Created: #{name} (#{content.length} chars)"
      end
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.message =~ /Name must be unique/
      card = Card.where(name: name).first
      card.update!(content: content) if card
      puts "  Updated (conflict): #{name}"
    end
  end
rescue => e
  puts "  ERROR on #{name}: #{e.message}"
end

# --- Bibliographic metadata (ask #1, schema approved 2026-06-09) -------------
# Real, queryable subcards on RawData+Publications+<title>:
#   +year  (Number), +venue (Phrase), +metadata_source (Phrase)
#   metadata_source values: curated_sheet | arxiv | inferred
# These three subcards are non-sensitive bibliographic metadata and inherit
# *all+*read = Anyone (PUBLIC). This is an INTENTIONAL, recorded exception
# (Codex 2026-06-21): the point is public queryability; the gated RawData
# full-text parent card is unaffected.
#
# Idempotent + provenance-aware: a lower-authority source (inferred) NEVER
# overwrites a higher-authority one (curated_sheet/arxiv). Every proposed write
# is logged. Set METADATA_DRY_RUN=1 to log proposed writes without persisting.
METADATA_RANK = { "curated_sheet" => 3, "curated" => 3, "arxiv" => 2, "inferred" => 1 }.freeze
METADATA_DRY_RUN = !ENV["METADATA_DRY_RUN"].to_s.empty?

def metadata_rank(src)
  METADATA_RANK[src.to_s.strip.downcase] || 0
end

def emit_metadata(parent_name, year:, venue:, source:)
  fields = { "year" => [:number, year], "venue" => [:phrase, venue],
             "metadata_source" => [:phrase, source] }
  fields.reject! { |_, (_, v)| v.nil? || v.to_s.strip.empty? }
  # +year is a Number cardtype: it rejects non-numeric content. Normalize whole-number
  # floats (sheet JSON may serialize "2013.0") and require a sane 4-digit year; otherwise
  # skip emitting +year (logged) rather than letting the create raise.
  if fields.key?("year")
    yv = fields["year"][1].to_s.strip.sub(/\.0+\z/, "")
    if yv =~ /\A\d{4}\z/ && (1900..2100).cover?(yv.to_i)
      fields["year"][1] = yv
    else
      puts "  metadata SKIP +year: #{fields["year"][1].inspect} is not a valid 4-digit year (1900-2100)"
      fields.delete("year")
    end
  end
  return if fields.empty?

  Card::Auth.as_bot do
    existing_src = (Card.fetch("#{parent_name}+metadata_source") rescue nil)&.db_content
    if metadata_rank(source) < metadata_rank(existing_src)
      puts "  metadata SKIP: incoming '#{source}' < existing '#{existing_src}' (curated value preserved)"
      next
    end

    type_names = { number: "Number", phrase: "Phrase" }
    fields.each do |right, (tc, val)|
      val = val.to_s.strip
      name = "#{parent_name}+#{right}"
      expected_type = type_names[tc]
      card = Card.fetch(name) rescue nil
      if card&.real?
        # Correct a pre-existing subcard whose cardtype is wrong (e.g. a +year
        # stored as Phrase): an unexpected type must not be silently kept just
        # because the content string happens to match.
        type_mismatch = expected_type && card.type_name != expected_type
        if card.db_content.to_s == val && !type_mismatch
          puts "  metadata UNCHANGED: #{name} = #{val}"
        else
          changes = []
          changes << "content #{card.db_content.inspect} -> #{val.inspect}" if card.db_content.to_s != val
          changes << "type #{card.type_name} -> #{expected_type}" if type_mismatch
          puts "  metadata #{METADATA_DRY_RUN ? 'PROPOSE-UPDATE' : 'UPDATE'}: #{name} (#{changes.join('; ')})"
          card.update!(type_code: tc, content: val) unless METADATA_DRY_RUN
        end
      else
        puts "  metadata #{METADATA_DRY_RUN ? 'PROPOSE-CREATE' : 'CREATE'}: #{name} (#{tc}) = #{val.inspect}"
        Card.create!(name: name, type_code: tc, content: val) unless METADATA_DRY_RUN
      end
    end
  end
rescue => e
  puts "  ERROR metadata on #{parent_name}: #{e.message}"
end

puts "Hyperon Wiki Publications Ingestion"
puts "Export directory: #{EXPORT_DIR}"
puts

unless Dir.exist?(EXPORT_DIR)
  puts "ERROR: #{EXPORT_DIR} not found"
  exit 1
end

json_files = Dir.glob("#{EXPORT_DIR}/*.json")
  .reject { |f| File.basename(f) == "export_summary.json" }
  .sort

puts "Found #{json_files.length} publication exports\n\n"

json_files.each_with_index do |json_file, idx|
  data = JSON.parse(File.read(json_file))
  title = data["meeting_name"] || File.basename(json_file, ".json")
  full_text = data["full_text"] || ""
  source_url = data["transcript_url"] || ""

  # Bibliographic metadata (optional in the record; idempotently mirrored to subcards).
  year = data["year"]
  venue = data["venue"]
  metadata_source = data["metadata_source"]
  # Future arxiv records emit venue=arXiv, metadata_source=arxiv. Infer when the
  # record omits them, from ANY arxiv signal: transcript_url, pdf_url, or arxiv_id
  # (Codex 2026-06-21).
  is_arxiv = [source_url, data["pdf_url"]].any? { |u| u.to_s =~ /arxiv\.org/i } ||
             !data["arxiv_id"].to_s.strip.empty?
  if is_arxiv
    venue = "arXiv" if venue.to_s.strip.empty?
    metadata_source = "arxiv" if metadata_source.to_s.strip.empty?
  end

  puts "[#{idx + 1}/#{json_files.length}] #{title}"
  puts "  Full text: #{full_text.length} chars"

  # Canonical naming (Decko folds "Raw Data+publications" to this key, but write it
  # canonically per naming-hygiene R-DEP-4).
  card_name = "RawData+Publications+#{title}"

  header = "<p><strong>Source:</strong> #{escape_html(source_url)}</p>\n<hr>\n"
  text_html = "<pre>#{escape_html(full_text)}</pre>"
  full_html = header + text_html

  if full_html.length <= MAX_CARD_CHARS
    create_or_update_card(card_name, full_html)
    emit_metadata(card_name, year: year, venue: venue, source: metadata_source)
    next
  end

  # Split into chunks
  lines = full_text.split("\n")
  chunks = []
  current = []
  current_len = 0

  lines.each do |line|
    line_len = escape_html(line).length + 5  # <p> overhead
    if current_len + line_len > MAX_CARD_CHARS && !current.empty?
      chunks << current
      current = []
      current_len = 0
    end
    current << line
    current_len += line_len
  end
  chunks << current unless current.empty?

  puts "  Splitting into #{chunks.length} chunks"

  # Index card
  chunk_links = (1..chunks.length).map do |i|
    "<li>{{#{card_name}+chunk-#{i}|view:link;title:_R}}</li>"
  end
  index_html = header + "<p><strong>Split into #{chunks.length} parts:</strong></p>\n<ol>\n#{chunk_links.join("\n")}\n</ol>"
  create_or_update_card(card_name, index_html)

  # Chunk cards
  chunks.each_with_index do |chunk_lines, i|
    chunk_html = "<p><strong>#{escape_html(title)}</strong> (part #{i+1}/#{chunks.length})</p>\n<hr>\n<pre>#{escape_html(chunk_lines.join("\n"))}</pre>"
    create_or_update_card("#{card_name}+chunk-#{i+1}", chunk_html)
  end

  emit_metadata(card_name, year: year, venue: venue, source: metadata_source)
end

puts "\nIngestion complete!"
