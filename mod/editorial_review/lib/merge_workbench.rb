# frozen_string_literal: true

# MergeWorkbench — pure Phase 4 payload builder for the merge workbench view.
#
# Turns an already-resolved base + the three content strings into the FROZEN
# schemaVersion-1 payload (docs/ws6-merge-editor-phase4-ui-contract.md §3) that
# the workbench view serializes into its JSON island and the client renders +
# previews. No Card / DB / permissions: the view does the I/O (BaseResolver +
# parent content) and hands the result here, so this stays unit-testable with no
# database (mirrors the other pure WS6 libs).
#
# It does NOT re-implement any merge logic: every hunk's blocks, types, and the
# default selection come verbatim from BlockMerge.merge. The only work here is
# (a) restoring {{nest}} tokens for display, (b) aggregating consecutive stable
# chunks into one collapsed entry (carrying their current content so the
# client-side preview assembler is fully deterministic), and (c) shaping keys.
#
# BlockMerge is autoloaded from the mod lib dir at runtime; the pure spec
# requires it before this file. Do NOT require_relative it from a set file.
require "json"

module MergeWorkbench
  module_function

  SCHEMA_VERSION = 1

  # The canonical workbench URL for a proposal. ALWAYS carries layout=none — the
  # Phase 4 finding is that without it the view renders wrapped in the card-513
  # layout. Every entry point (links, redirects, the legacy bridge) must build
  # the URL here so the param can't be dropped. Spaces are %20-encoded; the "+"
  # in compound card names stays literal (Decko routes it).
  def workbench_url(proposal_name)
    "/" + proposal_name.to_s.gsub(" ", "%20") + "?view=merge_workbench&layout=none"
  end

  # resolve: a BaseResolver.resolve result hash.
  # current / proposal: content strings. format: :html | :markdown.
  # proposal_name / parent_name: for the payload header.
  def build_payload(resolve:, current:, proposal:, format:, proposal_name:, parent_name:)
    three_way = resolve[:mode] == :three_way && !resolve[:base_content].nil?
    base = three_way ? resolve[:base_content] : current

    merge = BlockMerge.merge(base: base.to_s, current: current.to_s,
                             proposal: proposal.to_s, format: format)
    nests = merge[:nests]

    hunks = []
    counts = Hash.new(0)
    stable_buf = []
    flush = lambda do
      next if stable_buf.empty?

      hunks << { id: nil, type: "stable", count: stable_buf.size,
                 current: restore_all(stable_buf, nests) }
      stable_buf = []
    end

    merge[:chunks].each do |ch|
      counts[ch[:type]] += 1
      if ch[:type] == :stable
        stable_buf.concat(ch[:current])
        next
      end
      flush.call
      hunks << build_hunk(ch, merge[:default_selection], nests)
    end
    flush.call

    {
      schemaVersion: SCHEMA_VERSION,
      proposal: proposal_name,
      parent: parent_name,
      format: format.to_s,
      mode: three_way ? "three_way" : "two_way",
      tier: resolve[:tier]&.to_s,
      warning: resolve[:warning],
      baseHashOk: resolve[:base_hash_ok],
      counts: {
        conflict: counts[:conflict], ai_only: counts[:ai_only],
        human_only: counts[:human_only], both_same: counts[:both_same],
        stable: counts[:stable]
      },
      hunks: hunks,
      selectionDefaults: stringify_values(merge[:default_selection])
    }
  end

  # JSON for the workbench's <script type="application/json"> island. Escapes
  # "</" -> "<\/" so embedded HTML content (which can contain </script>) can't
  # break out of the island; "<\/" is a valid escaped solidus inside JSON
  # strings, and "</" only ever appears inside string values here.
  def to_island_json(payload)
    JSON.generate(payload).gsub("</", "<\\/")
  end

  # --- internals ---

  def build_hunk(chunk, defaults, nests)
    {
      id: chunk[:id],
      type: chunk[:type].to_s,
      base: restore_all(chunk[:base], nests),
      current: restore_all(chunk[:current], nests),
      proposal: restore_all(chunk[:proposal], nests),
      default: defaults[chunk[:id]]&.to_s, # nil for conflicts -> client must choose
      display: { currentVsProposal: display_diff(chunk[:current], chunk[:proposal], nests) }
    }
  end

  def restore_all(raws, nests)
    (raws || []).map { |raw| BlockMerge.restore_nests(raw, nests) }
  end

  # Display-only inline diff (advisory; never fed back to assemble). word_diff is
  # nest-atomic on the protected tokens; restore after so {{nests}} render whole.
  def display_diff(current_raws, proposal_raws, nests)
    diff = BlockMerge.word_diff((current_raws || []).join(" "), (proposal_raws || []).join(" "))
    BlockMerge.restore_nests(diff, nests)
  end

  def stringify_values(hash)
    (hash || {}).each_with_object({}) { |(k, v), o| o[k] = v.to_s }
  end
end
