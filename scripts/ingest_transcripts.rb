#!/usr/bin/env ruby
# Ingest transcript exports into the Hyperon Wiki as RawData cards.
#
# Reads JSON exports produced by export_transcripts.py and creates
# complete RawData cards in the Decko database with full transcript text.
#
# Run via:
#   cat scripts/ingest_transcripts.rb | ssh -T -i ~/.ssh/hyperon-key.pem ubuntu@54.183.80.144 \
#     'export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH" && eval "$(rbenv init -)" && \
#      cd ~/hyperon-wiki && set -a && source .env.production && set +a && \
#      RAILS_ENV=production bundle exec decko runner -'
#
# Or copy to server and run:
#   RAILS_ENV=production bundle exec decko runner scripts/ingest_transcripts.rb
#
# Prerequisites:
#   - Transcript JSON exports in EXPORT_DIR (produced by export_transcripts.py)
#   - The RawData cardtype must exist on the wiki

require 'json'

# ============================================================
# Configuration
# ============================================================

EXPORT_DIR = ENV.fetch("TRANSCRIPT_EXPORT_DIR",
  File.expand_path("~/transcript_exports/latest"))

PARENT_CARD = "Raw Data+transcripts"

# Maximum characters per card. Transcripts can be very large.
MAX_CARD_CHARS = 50_000

# ============================================================
# Helpers
# ============================================================

def escape_html(text)
  text.to_s
    .gsub("&", "&amp;")
    .gsub("<", "&lt;")
    .gsub(">", "&gt;")
end

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
  lines << "<p><strong>Duration:</strong> #{duration} min</p>" if duration > 0
  lines << "<p><strong>Participants:</strong> #{escape_html(participants.join(', '))}</p>" unless participants.empty?
  lines << "<p><strong>Keywords:</strong> #{escape_html(keywords.join(', '))}</p>" unless keywords.empty?

  if transcript_url && !transcript_url.empty?
    lines << "<p><strong>View on #{escape_html(service)}:</strong> <a href=\"#{escape_html(transcript_url)}\">#{escape_html(transcript_url)}</a></p>"
  end

  lines << "<hr>"

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

  lines.join("\n")
end

def format_full_text(full_text)
  return "" if full_text.nil? || full_text.empty?

  lines = []
  lines << "<h3>Full Transcript</h3>"
  lines << "<pre>#{escape_html(full_text)}</pre>"
  lines.join("\n")
end

def create_or_update_card(name, content, type_code = :raw_data)
  Card::Auth.as_bot do
    card = begin
      Card.fetch(name)
    rescue
      nil
    end

    begin
      if card
        card.update!(content: content)
        puts "  Updated: #{name} (#{content.length} chars)"
      else
        Card.create!(
          name: name,
          type_code: type_code,
          content: content
        )
        puts "  Created: #{name} (#{content.length} chars)"
      end
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.message =~ /Name must be unique/
      card = Card.where(name: name).first
      if card
        card.update!(content: content)
        puts "  Updated (after conflict): #{name}"
      else
        raise
      end
    end
  end
rescue => e
  puts "  ERROR on #{name}: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# ============================================================
# Main: Process each transcript export
# ============================================================

def ingest_transcript(json_path)
  data = JSON.parse(File.read(json_path))

  meeting_name = data["meeting_name"] || "Unknown"
  date = data["date"] || "unknown"
  full_text = data["full_text"] || ""

  puts "\n#{'=' * 60}"
  puts "Transcript: #{meeting_name} (#{date})"
  puts "  Full text: #{full_text.length} chars"
  puts "=" * 60

  # Build card content
  header_html = format_transcript_header(data)
  text_html = format_full_text(full_text)
  full_html = header_html + "\n" + text_html

  # Safe card name: replace problematic characters
  safe_name = meeting_name.gsub('+', '-').gsub('/', '-')
  base_card_name = "#{PARENT_CARD}+#{safe_name}+#{date}"

  # If content fits in one card, create a single card
  if full_html.length <= MAX_CARD_CHARS
    create_or_update_card(base_card_name, full_html)
    return
  end

  # Otherwise, split: header card + transcript chunk cards
  puts "  Content too large (#{full_html.length} chars). Splitting..."

  # Split the full text into chunks
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

  # Create index card with header + links to chunks
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

  # Create chunk cards
  chunks.each_with_index do |chunk_lines, idx|
    chunk_num = idx + 1
    chunk_text = chunk_lines.join("\n")
    chunk_content = <<~HTML
      <p><strong>Source:</strong> #{escape_html(data["source_service"])} — #{escape_html(meeting_name)} (part #{chunk_num}/#{chunks.length})</p>
      <p><strong>Date:</strong> #{escape_html(date)}</p>
      <hr>
      <pre>#{escape_html(chunk_text)}</pre>
    HTML

    chunk_card_name = "#{base_card_name}+chunk-#{chunk_num}"
    create_or_update_card(chunk_card_name, chunk_content)
  end
end

# ============================================================
# Entry point
# ============================================================

puts "Hyperon Wiki Transcript Ingestion"
puts "Export directory: #{EXPORT_DIR}"
puts "Parent card: #{PARENT_CARD}"
puts

unless Dir.exist?(EXPORT_DIR)
  puts "ERROR: Export directory not found: #{EXPORT_DIR}"
  puts "Run export_transcripts.py first, then copy exports to the server."
  exit 1
end

# Find all transcript JSON files (skip export_summary.json)
json_files = Dir.glob("#{EXPORT_DIR}/*.json")
  .reject { |f| File.basename(f) == "export_summary.json" }
  .sort

puts "Found #{json_files.length} transcript exports"

json_files.each_with_index do |json_file, idx|
  puts "\n[#{idx + 1}/#{json_files.length}] #{File.basename(json_file)}"
  ingest_transcript(json_file)
end

puts "\n#{'=' * 60}"
puts "Ingestion complete!"
puts "Total transcripts: #{json_files.length}"
puts "=" * 60
