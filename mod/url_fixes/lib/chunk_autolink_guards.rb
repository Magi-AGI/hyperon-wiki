# frozen_string_literal: true

# ChunkAutolinkGuards
# Hardens Decko's URI/Host/Email auto-link chunks (card-mod-content) against two
# failure modes reported in the field (MCP feedback log, 2026-06-09):
#
#   1. NESTED ANCHORS that accumulate every render. The chunk scanner's
#      `context_ok?` only inspects the 2 characters preceding a match, so URL or
#      email text that already sits inside an authored <a> is re-linkified on
#      every render — producing <a><a><a>…</a></a></a> up to ~13 levels deep in
#      stored content. We reject any match whose start position is inside an
#      open <a> element.
#
#   2. FILENAME PSEUDO-URLS. HostUri auto-links schemeless bare domains, and its
#      ccTLD list overlaps source-file extensions (.py, .rs, .io, .sh, .js, …),
#      so `nace.py` / `airis_stable.py` / `MorkDB.cc` get linked as
#      `http://nace.py`. We reject a schemeless match whose final segment is a
#      known source-file extension (real domains like docs.asichain.io — .io is
#      not in the code-extension set — still link).
#
# Prepended to Card::Content::Chunk::Uri.singleton_class, so it also covers the
# EmailUri and HostUri subclasses (which inherit context_ok?).
module ChunkAutolinkGuards
  # Field-proven set from scripts/clean_autolinker_artifacts.py. Real domain
  # TLDs people actually link (io, com, org, net, …) are deliberately absent.
  CODE_EXT = %w[
    py rs cc cpp c h hpp hh cxx
    md txt rst json yml yaml toml cfg conf ini log
    ts tsx js jsx mjs cjs coffee
    go rb erb scm ss lisp cl lean idr metta
    erl hs ml mli sh bash zsh fish
    java kt kts scala swift dart
    sql svg scss sass less
    pl pm tex bib nim zig
  ].join("|").freeze

  # bare "name.ext" (optionally dotted) ending in a source-file extension, not
  # continued by a path/word char (which would make it look like a real URL).
  FILENAME_RE = /\A[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*\.(?:#{CODE_EXT})\b(?![\/\w])/i

  def context_ok?(content, chunk_start)
    return false unless super
    return false if inside_anchor?(content, chunk_start)
    return false if schemeless_code_filename?(content, chunk_start)

    true
  end

  # True when chunk_start falls inside an open <a> … </a>.
  def inside_anchor?(content, chunk_start)
    before = content[0...chunk_start].to_s
    open_idx = before.rindex(/<a\b/i)
    return false unless open_idx

    close_idx = before.rindex(/<\/a>/i)
    close_idx.nil? || open_idx > close_idx
  end

  # True when the token at chunk_start is a bare source-filename (no scheme,
  # no leading path slash) ending in a code extension.
  def schemeless_code_filename?(content, chunk_start)
    return false if chunk_start.positive? && content[chunk_start - 1] == "/"

    content[chunk_start, 256].to_s.match?(FILENAME_RE)
  end
end
