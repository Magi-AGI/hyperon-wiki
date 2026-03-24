# frozen_string_literal: true

# UrlLinkifier
# Post-processes RichText HTML to linkify URLs that include characters like
# en-dash (\u2013), em-dash (\u2014), and ellipsis (\u2026), which RFC regexes
# typically exclude. Visible text is preserved; href is safely percent-encoded
# for those special characters.

module UrlLinkifier
  SPECIALS = {
    "\u2013" => '%E2%80%93', # en-dash
    "\u2014" => '%E2%80%94', # em-dash
    "\u2026" => '%E2%80%A6' # ellipsis
  }.freeze

  # Allowed URL characters while scanning (text side)
  # RFC3986 unreserved + reserved + percent plus our specials.
  URL_CHAR = /[A-Za-z0-9\-._~:\/\?#\[\]@!$&'()*+,;=%]/
  # Include known problematic joiners like currency sign \u00A4 that may appear
  # inside pasted URLs; they will be percent-encoded in hrefs.
  URL_OR_SPECIAL = /#{URL_CHAR.source}|[\u2013\u2014\u2026\u00A4]/

  TRAILING_PUNCT = /[\.,!?:;\)\]\}"']$/

  SKIP_PARENTS = %w[a script style pre code textarea].freeze

  module_function

  def linkify_html(html)
    return html if html.nil? || html.empty?

    begin
      require 'nokogiri'
    rescue LoadError
      Rails.logger.warn('[URLFIX] Nokogiri not available; skipping linkify') if defined?(Rails)
      return html
    end

    frag = Nokogiri::HTML::DocumentFragment.parse(html)

    # First, fix existing anchors' href values to percent-encode specials
    fix_existing_anchors(frag)
    text_nodes = frag.xpath('.//text()')

    text_nodes.each do |t|
      parent = t.parent
      next if !parent || SKIP_PARENTS.include?(parent.name.downcase)

      content = t.text
      next if content.strip.empty?

      new_nodes = build_nodes_for_text(frag, content)
      next if new_nodes.nil?

      new_nodes.each { |n| t.add_previous_sibling(n) }
      t.remove
    end

    # Merge anchors split by adjacent URL fragments
    fix_split_url_fragments(frag)

    frag.to_html
  rescue StandardError => e
    Rails.logger.error("[URLFIX] linkify_html error: #{e.class}: #{e.message}") if defined?(Rails)
    html
  end

  def fix_existing_anchors(frag)
    frag.css('a[href]').each do |a|
      href = a['href']
      next if href.nil? || href.empty?
      # only adjust http/https URLs or bare www domains
      next unless href.start_with?('http://', 'https://') || href.start_with?('www.')
      fixed = normalize_href(href)
      a['href'] = fixed if fixed != href
    end
  end

  INLINE_NAMES = %w[span b i em strong small code samp kbd u s sup sub].freeze

  def fix_split_url_fragments(frag)
    frag.css('a[href]').each do |a|
      href = a['href']
      next unless href && (href.start_with?('http://', 'https://') || href.start_with?('www.'))

      node = a.next_sibling
      while node
        text_node = nil
        if node.text?
          text_node = node
        elsif node.element? && INLINE_NAMES.include?(node.name.downcase) && node.children.length == 1 && node.children.first.text?
          text_node = node.children.first
        end

        break unless text_node

        raw = text_node.text
        break if raw.nil? || raw.empty?

        # Leading spaces / NBSPs
        leading_ws = raw[/\A[\s\u00A0]*/]
        rest = raw[leading_ws.length..-1] || ''

        # Accept a contiguous run of URL-ish continuation characters
        if (m = rest.match(/\A([\u2013\u2014\u2026\u00A4\/\?#&=A-Za-z0-9\-._~:@!$'()*+,;=%]+)/))
          ext = m[1]

          # Update anchor text and href
          a.content = (a.text.to_s + ext)
          a['href'] = encode_url_piece(href) + encode_url_piece(ext)

          # Remove consumed portion from sibling
          remainder = rest[ext.length..-1] || ''
          if remainder.empty?
            parent = text_node.parent
            text_node.remove
            if parent != a && parent.element? && parent.children.empty?
              parent.remove
            end
          else
            text_node.content = remainder
          end

          # Continue to next sibling
          node = (node.element? ? node.next_sibling : text_node.next_sibling)
          href = a['href']
          next
        end

        break
      end
    end
  end

  def encode_url_piece(str)
    s = SPECIALS.reduce(str.to_s) { |acc, (char, enc)| acc.gsub(char, enc) }
    allowed = /[A-Za-z0-9\-._~:\/\?#\[\]@!$&'()*+,;=%]/
    s.gsub(/[^#{allowed.source}]/) { |ch| ch.bytes.map { |b| '%%%02X' % b }.join }
  end

  def build_nodes_for_text(doc, text)
    i = 0
    nodes = []
    changed = false

    while i < text.length
      idx = next_url_start(text, i)
      break unless idx

      # Preceding text
      if idx > i
        nodes << Nokogiri::XML::Text.new(text[i...idx], doc)
      end

      # Grow match to include URL characters + specials
      j = idx
      while j < text.length && text[j].match?(URL_OR_SPECIAL)
        j += 1
      end

      # Trim trailing punctuation off URL
      end_idx = j
      while end_idx > idx && text[end_idx - 1].match?(TRAILING_PUNCT)
        end_idx -= 1
      end

      url_text = text[idx...end_idx]
      trailing = text[end_idx...j]

      if url_text && !url_text.empty?
        href = normalize_href(url_text)
        a = Nokogiri::XML::Node.new('a', doc)
        a['href'] = href
        a.content = url_text
        nodes << a
        nodes << Nokogiri::XML::Text.new(trailing, doc) unless trailing.empty?
        changed = true
      else
        # No actual URL, just punctuation—emit raw text
        nodes << Nokogiri::XML::Text.new(text[idx...j], doc)
      end

      i = j
    end

    if !changed
      nil
    else
      # Remainder
      nodes << Nokogiri::XML::Text.new(text[i..-1], doc) if i < text.length
      nodes
    end
  end

  def next_url_start(text, from)
    http = text.index('http://', from)
    https = text.index('https://', from)
    www = text.index('www.', from)

    # bare domain like example.com/... or example.com? or example.com#
    domain_rel = nil
    slice = text[from..-1]
    if slice && !slice.empty?
      if (m = slice.match(/\b(?:[a-z0-9-]+\.)+[a-z]{2,}(?=\/|\?|#)/i))
        domain_rel = from + m.begin(0)
      end
    end

    # pick earliest non-nil
    candidates = [http, https, www, domain_rel].compact
    return nil if candidates.empty?
    candidates.min
  end

  def normalize_href(url_text)
    href = if url_text.start_with?('http://', 'https://')
             url_text.dup
           else
             # no scheme provided -> default to https
             "https://#{url_text}"
           end

    # First replace explicit specials
    href = SPECIALS.reduce(href) { |acc, (char, enc)| acc.gsub(char, enc) }

    # Then percent-encode any character not allowed by RFC3986 for URLs
    allowed = /[A-Za-z0-9\-._~:\/\?#\[\]@!$&'()*+,;=%]/
    href.gsub(/[^#{allowed.source}]/) do |ch|
      ch.bytes.map { |b| '%%%02X' % b }.join
    end
  end
end
