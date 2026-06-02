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

  puts "[#{idx + 1}/#{json_files.length}] #{title}"
  puts "  Full text: #{full_text.length} chars"

  card_name = "Raw Data+publications+#{title}"

  header = "<p><strong>Source:</strong> #{escape_html(source_url)}</p>\n<hr>\n"
  text_html = "<pre>#{escape_html(full_text)}</pre>"
  full_html = header + text_html

  if full_html.length <= MAX_CARD_CHARS
    create_or_update_card(card_name, full_html)
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
end

puts "\nIngestion complete!"
