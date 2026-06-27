# frozen_string_literal: true

# BlockMerge — pure-Ruby 3-way block-level merge engine for WS6 (Phase 3).
# No Card / DB / permissions; operates on content strings only.
#
# Pipeline: protect {{nests}} -> tokenize into structural blocks (HTML via
# Nokogiri; Markdown via fence/blank-line, tables kept atomic) -> diff3 over
# blocks -> classify hunks -> assemble from per-hunk selections -> restore
# nests. Source format is preserved (HTML stays HTML, Markdown stays Markdown);
# nothing is normalized through rendered text. Block equality uses a normalized
# representation so trivial whitespace/serialization differences don't create
# false hunks. Defaults are human-explicit: AI changes are never auto-accepted.
require "digest"
require "diff/lcs"
begin
  require "nokogiri"
rescue LoadError
  nil # HTML tokenization falls back to blank-line splitting without Nokogiri
end

module BlockMerge
  module_function

  NEST_RE = /\{\{[^}]*\}\}/.freeze
  SENTINEL = [0xE000].pack("U").freeze

  Block = Struct.new(:raw, :norm)

  # ---- public API ----

  # base/current/proposal: content strings. format: :html or :markdown.
  # Returns:
  #   { format:, nests: {token => "{{...}}"},
  #     chunks: [ {id:, type:, base:[raw], current:[raw], proposal:[raw]} ... ]
  #              in document order (stable chunks have id:nil),
  #     default_selection: { hunk_id => :current | :proposal } }  # conflicts absent
  def merge(base:, current:, proposal:, format:)
    nests = {}
    bb = to_blocks(protect_nests(base.to_s, nests), format)
    cb = to_blocks(protect_nests(current.to_s, nests), format)
    rb = to_blocks(protect_nests(proposal.to_s, nests), format)

    chunks = []
    defaults = {}
    diff3(bb, cb, rb).each_with_index do |ch, i|
      if ch[:type] == :stable
        chunks << { id: nil, type: :stable, base: raws(ch[:base]),
                    current: raws(ch[:current]), proposal: raws(ch[:proposal]) }
        next
      end
      id = "h#{i}"
      chunks << { id: id, type: ch[:type], base: raws(ch[:base]),
                  current: raws(ch[:current]), proposal: raws(ch[:proposal]) }
      side = default_side(ch[:type])
      defaults[id] = side if side
    end

    { format: format, nests: nests, chunks: chunks, default_selection: defaults }
  end

  # selections: { hunk_id => :current | :proposal | :base }. A conflict with no
  # selection is unresolved -> raises unless allow_unresolved (then keeps current).
  def assemble(result, selections = {}, allow_unresolved: false)
    sel = result[:default_selection].merge(stringify_keys(selections))
    parts = []
    result[:chunks].each do |ch|
      if ch[:type] == :stable
        parts.concat(ch[:current])
        next
      end
      side = sel[ch[:id]]
      if side.nil?
        raise "unresolved conflict hunk #{ch[:id]}" unless allow_unresolved

        side = :current
      end
      parts.concat(ch[side] || [])
    end
    joiner = result[:format] == :markdown ? "\n\n" : "\n"
    restore_nests(parts.reject { |p| p.to_s.empty? }.join(joiner), result[:nests])
  end

  # Display-only word/inline diff between two block raws. Nest tokens contain no
  # whitespace so they are atomic words -> <ins>/<del> never split a {{nest}}.
  # Caller restores nests on the result for display.
  def word_diff(old_raw, new_raw)
    Diff::LCS.sdiff(old_raw.to_s.split(/\s+/), new_raw.to_s.split(/\s+/)).map do |c|
      case c.action
      when "=" then c.new_element
      when "+" then "<ins>#{c.new_element}</ins>"
      when "-" then "<del>#{c.old_element}</del>"
      when "!" then "<del>#{c.old_element}</del><ins>#{c.new_element}</ins>"
      end
    end.join(" ")
  end

  # ---- nest protection (content-keyed tokens: identical nests compare equal) ----

  def protect_nests(content, nests)
    content.gsub(NEST_RE) do |m|
      tok = "#{SENTINEL}N#{Digest::MD5.hexdigest(m)}#{SENTINEL}"
      nests[tok] = m
      tok
    end
  end

  def restore_nests(content, nests)
    return content if nests.empty?

    nests.each { |tok, orig| content = content.gsub(tok, orig) }
    content
  end

  # ---- tokenization ----

  def to_blocks(content, format)
    raws = format == :markdown ? tokenize_markdown(content) : tokenize_html(content)
    raws.map { |r| Block.new(r, normalize(r, format)) }
  end

  def tokenize_html(html)
    return tokenize_blankline(html) unless defined?(Nokogiri)

    Nokogiri::HTML.fragment(html).children.filter_map do |node|
      next nil if node.text? && node.text.strip.empty?

      html_block = node.to_html.strip
      html_block.empty? ? nil : html_block
    end
  end

  # Blank-line separated blocks; fenced code spans blank lines; tables (no blank
  # lines within) stay atomic naturally.
  def tokenize_markdown(md)
    blocks = []
    cur = []
    in_fence = false
    md.split("\n", -1).each do |line|
      if line.strip.start_with?("```")
        in_fence = !in_fence
        cur << line
        next
      end
      if line.strip.empty? && !in_fence
        blocks << cur.join("\n") unless cur.empty?
        cur = []
      else
        cur << line
      end
    end
    blocks << cur.join("\n") unless cur.empty?
    blocks.reject { |b| b.strip.empty? }
  end

  def tokenize_blankline(text)
    text.split(/\n[ \t]*\n/).map(&:strip).reject(&:empty?)
  end

  def normalize(raw, format)
    if format != :markdown && defined?(Nokogiri)
      (Nokogiri::HTML.fragment(raw).to_html rescue raw).gsub(/\s+/, " ").strip
    else
      raw.gsub(/[ \t]+/, " ").gsub(/\s*\n\s*/, "\n").strip
    end
  end

  # ---- diff3 over block arrays ----

  def diff3(base, current, proposal)
    mc = match_map(base, current)
    mp = match_map(base, proposal)
    anchors = (0...base.size).select { |i| mc.key?(i) && mp.key?(i) }

    chunks = []
    bi = ci = pi = 0
    anchors.each do |a|
      ca = mc[a]
      pa = mp[a]
      if a > bi || ca > ci || pa > pi
        chunks << changed_chunk(base[bi...a], current[ci...ca], proposal[pi...pa])
      end
      chunks << { type: :stable, base: [base[a]], current: [current[ca]], proposal: [proposal[pa]] }
      bi = a + 1
      ci = ca + 1
      pi = pa + 1
    end
    if bi < base.size || ci < current.size || pi < proposal.size
      chunks << changed_chunk(base[bi..] || [], current[ci..] || [], proposal[pi..] || [])
    end
    chunks
  end

  # base_index => other_index for blocks equal by normalized value
  def match_map(base, other)
    map = {}
    Diff::LCS.sdiff(base.map(&:norm), other.map(&:norm)).each do |c|
      map[c.old_position] = c.new_position if c.action == "="
    end
    map
  end

  def changed_chunk(base, current, proposal)
    bt = base.map(&:norm)
    ct = current.map(&:norm)
    pt = proposal.map(&:norm)
    type = if ct == pt then :both_same
           elsif bt == ct then :ai_only
           elsif bt == pt then :human_only
           else :conflict
           end
    { type: type, base: base, current: current, proposal: proposal }
  end

  # Human-explicit defaults: keep the current (human) side; AI changes require an
  # explicit accept; conflicts have NO default (must be chosen).
  def default_side(type)
    case type
    when :both_same, :ai_only, :human_only then :current
    end # :conflict -> nil
  end

  def raws(blocks)
    blocks.map(&:raw)
  end

  def stringify_keys(h)
    (h || {}).each_with_object({}) { |(k, v), o| o[k.to_s] = v }
  end
end
