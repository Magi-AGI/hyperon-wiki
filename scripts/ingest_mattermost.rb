#!/usr/bin/env ruby
# Ingest Mattermost exports into the Hyperon Wiki as RawData cards.
#
# Reads JSON exports produced by mattermost_export.py and creates
# complete, unfiltered RawData cards in the Decko database.
#
# Run via:
#   cat scripts/ingest_mattermost.rb | ssh -T -i ~/.ssh/hyperon-key.pem ubuntu@54.183.80.144 \
#     'export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH" && eval "$(rbenv init -)" && \
#      cd ~/hyperon-wiki && set -a && source .env.production && set +a && \
#      RAILS_ENV=production bundle exec decko runner -'
#
# Or copy to server and run:
#   RAILS_ENV=production bundle exec decko runner scripts/ingest_mattermost.rb
#
# Prerequisites:
#   - Mattermost JSON exports in EXPORT_DIR (produced by mattermost_export.py)
#   - The RawData cardtype must exist on the wiki

require 'json'

# ============================================================
# Configuration
# ============================================================

# Path to the Mattermost export directory on the server.
# Upload exports via: scp -i ~/.ssh/hyperon-key.pem -r mattermost_exports/ ubuntu@54.183.80.144:~/
EXPORT_DIR = ENV.fetch("MATTERMOST_EXPORT_DIR",
  File.expand_path("~/mattermost_exports/latest"))

PARENT_CARD = "Raw Data+mattermost"

# Maximum characters per card. Decko can handle large cards but
# we chunk to keep the UI responsive.
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

def format_post(post, threads)
  lines = []
  username = escape_html(post["username"] || "?")
  created = (post["created"] || "?")[0..18]
  message = escape_html(post["message"] || "")

  lines << "<p><strong>#{username}</strong> (#{created})</p>"
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
# Main: Process each channel export
# ============================================================

def ingest_channel(json_path)
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

  puts "\n#{'=' * 60}"
  puts "Channel: #{channel_name} (#{post_count} posts, #{thread_count} threads)"
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
    <p><strong>Exported:</strong> #{exported_at}</p>
    <p><strong>Posts:</strong> #{post_count}</p>
    <p><strong>Threads:</strong> #{thread_count}</p>
    #{purpose.empty? ? '' : "<p><strong>Purpose:</strong> #{escape_html(purpose)}</p>"}
    #{header_text.empty? ? '' : "<p><strong>Header:</strong> #{escape_html(header_text)}</p>"}
    <hr>
  HTML

  # If content fits in one card, create a single card
  if (channel_header.length + full_html.length) <= MAX_CARD_CHARS
    card_name = "#{PARENT_CARD}+#{channel_name}"
    create_or_update_card(card_name, channel_header + full_html)
    return
  end

  # Otherwise, chunk into multiple cards
  chunks = []
  current_chunk = []
  current_length = 0

  all_posts_html.each_with_index do |post_html, idx|
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
    first_post = nil
    last_post = nil
    # We need to find date ranges — parse from the HTML
    "<li>{{#{PARENT_CARD}+#{channel_name}+chunk-#{i}|view:link;title:_R}}</li>"
  end

  index_content = channel_header + <<~HTML
    <p><strong>Content split into #{chunks.length} chunks:</strong></p>
    <ol>
    #{chunk_links.join("\n")}
    </ol>
  HTML

  card_name = "#{PARENT_CARD}+#{channel_name}"
  create_or_update_card(card_name, index_content)

  # Create chunk cards
  chunks.each_with_index do |chunk_posts, idx|
    chunk_num = idx + 1
    chunk_content = <<~HTML
      <p><strong>Source:</strong> Mattermost — #{escape_html(channel_name)} (chunk #{chunk_num}/#{chunks.length})</p>
      <p><strong>Posts in chunk:</strong> #{chunk_posts.length}</p>
      <hr>
      #{chunk_posts.join("\n")}
    HTML

    chunk_card_name = "#{PARENT_CARD}+#{channel_name}+chunk-#{chunk_num}"
    create_or_update_card(chunk_card_name, chunk_content)
  end
end

# ============================================================
# Entry point
# ============================================================

puts "Hyperon Wiki Mattermost Ingestion"
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
  .reject { |f| f.include?("export_summary.json") }
  .sort

puts "Found #{json_files.length} channel exports"

json_files.each_with_index do |json_file, idx|
  puts "\n[#{idx + 1}/#{json_files.length}] #{File.basename(json_file)}"
  ingest_channel(json_file)
end

puts "\n#{'=' * 60}"
puts "Ingestion complete!"
puts "Total channels: #{json_files.length}"
puts "=" * 60
