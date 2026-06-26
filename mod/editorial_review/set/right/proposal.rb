# frozen_string_literal: true

# Set: <Parent>+proposal — the WS6 structured edit-proposal convention.
#
# WHY a new convention (not +AI): `+AI` has historically been a catch-all for
# ANY AI-generated content (notes, summaries, ad-hoc suggestions). The merge
# workbench needs an unambiguous trigger — "this card IS a proposed replacement
# for its parent's content, with a known base and a merge lifecycle." `+proposal`
# is that trigger, and is author-neutral (humans can open peer-review proposals
# too). `+AI` is left untouched. See docs/ws6-merge-editor-design.md §3.5/§4.1.
#
# WHAT this file is: Phase 1, the MODEL layer only. It (1) aligns the proposal's
# content format to its parent so later diffs compare like with like, and
# (2) stamps the base revision + writes verifiable provenance at AUTHORING time.
# The merge workbench view and the verifying merge-apply path land in later
# phases; the legacy blunt overwrite (set/right/ai_draft.rb) stays live until
# Phase 6 replaces it, so there is never a window with no merge path.

# ProposalProvenance (mod/editorial_review/lib/proposal_provenance.rb) is
# autoloaded from the mod's lib dir — do NOT require_relative it here; Decko's
# set loader evaluates this file without a stable __FILE__, so a relative
# require raises and silently drops the whole set (events never register).

# Inert plain-text cardtype for the JSON sidecars (+provenance; later +merge
# audit). We read its stored db_content back verbatim and never rely on its
# rendered form, so Decko's RichText URL chunk-processor never touches it.
# NOTE (dev-runtime check): confirm "Plain Text" is the right inert core type
# in this Decko 0.20 deck; if not, this is the single constant to change.
PROPOSAL_META_TYPE = "Plain Text"

# Content cardtypes a proposal may mirror (so 3-way diffs are apples-to-apples).
# Compared by type NAME (robust) rather than codename ids. Non-content parent
# types (e.g. Published/Draft, themselves HTML-backed) are left alone — a
# proposal created against them stays its authored type and the diff engine keys
# off the recorded parent_type/proposal_type instead.
PROPOSAL_CONTENT_TYPES = %w[RichText Markdown].freeze

# (1) Align proposal content format to its parent's, before the card is stored.
event :align_proposal_type, :prepare_to_validate, on: :create do
  parent = left
  next unless parent
  next if type_id == parent.type_id
  next unless PROPOSAL_CONTENT_TYPES.include?(parent.type_name)

  self.type_id = parent.type_id
end

# (2) Stamp base + write provenance at authoring time. Idempotent; honours a
#     generator-supplied base override (never overwrites it).
#
# STAGE = :finalize (not :integrate): :integrate runs after-commit and is
# deferred/suppressed on the MCP-API and runner create paths (the AI-generator
# path), so an :integrate stamp would never run for AI-authored proposals.
# :finalize runs inside the save transaction, so the proposal + base +
# provenance commit atomically (no orphaned unstamped proposals). The metadata
# cards' right names (+base/+provenance) are not "proposal", so writing them
# here does not re-trigger this set.
event :stamp_proposal_base, :finalize, on: :create do
  parent = left
  next unless parent

  base_name = "#{name}+base"
  prov_name = "#{name}+provenance"
  next if Card.fetch(prov_name)&.db_content.present? # already stamped

  # Capture the REAL actor before switching to the bot for the metadata writes.
  actor = Card::Auth.current
  override_reason = Env.params[:proposal_base_override_reason].presence

  existing_base = Card.fetch(base_name)
  if existing_base&.db_content.present?
    # A generator/human pre-stamped a read-time (or deliberately chosen) base.
    # A read-time stamp is NOT an override; override is reserved for an explicit
    # manual non-current base selection (carries a required reason).
    base_act_id = existing_base.db_content.to_i
    stamp_source = override_reason ? "manual_override" : "generator_read_time"
  else
    latest = Card::Action.where(card_id: parent.id)
                         .where(draft: [false, nil]).order(id: :desc).first
    base_act_id = latest&.act&.id
    stamp_source = "server_current"
  end

  # Durable reconstruction key: the PARENT's Card::Action at that act. An Act can
  # span several cards' actions, so resolve the parent's action explicitly rather
  # than assuming act_id maps to one content revision (Codex #1).
  base_action_id =
    if base_act_id
      Card::Action.joins(:act)
                  .where(card_id: parent.id, card_acts: { id: base_act_id })
                  .order(id: :desc).first&.id
    end

  record = ProposalProvenance.build_record(
    parent_id: parent.id, parent_name: parent.name,
    parent_type: parent.type_name, proposal_type: type_name,
    base_act_id: base_act_id, base_action_id: base_action_id,
    base_hash: ProposalProvenance.content_hash(parent.db_content),
    proposal_hash: ProposalProvenance.content_hash(db_content),
    actor_id: actor&.id, actor_name: actor&.name,
    source: Env.params[:proposal_source].presence || "unknown",
    stamp_source: stamp_source,
    override: stamp_source == "manual_override",
    override_reason: override_reason,
    stamped_at: Time.now.utc.iso8601
  )

  Card::Auth.as_bot do
    if base_act_id && existing_base&.db_content.blank?
      Card.create!(name: base_name, type: "Number", content: base_act_id.to_s)
    end
    Card.create!(name: prov_name, type: PROPOSAL_META_TYPE,
                 content: ProposalProvenance.to_json_compact(record))
  end
end

# (3) Keep proposal_hash/proposal_type current so legitimate post-authoring edits
#     to the proposal don't trip Phase 6's integrity check. Base fields preserved.
event :refresh_proposal_hash, :finalize, on: :update, changed: :db_content do
  prov_name = "#{name}+provenance"
  prov = Card.fetch(prov_name)
  next unless prov&.db_content.present?

  record = ProposalProvenance.parse(prov.db_content)
  record["proposal_hash"] = ProposalProvenance.content_hash(db_content)
  record["proposal_type"] = type_name
  record["proposal_hash_updated_at"] = Time.now.utc.iso8601

  Card::Auth.as_bot { prov.update!(content: ProposalProvenance.to_json_compact(record)) }
end

# ---------------------------------------------------------------------------
# Phase 4 — merge workbench view (READ-ONLY; thin cut).
#
# Reached via /<Parent>+proposal?view=merge_workbench. Renders the P4Merge-style
# columnar 3-way diff (Base · Current · Proposal panes; Base dropped in forced
# 2-way) over the frozen schemaVersion-1 payload, with a client-side preview
# assembler. NO parent write, NO TinyMCE — the blunt set/right/ai_draft.rb
# overwrite stays live until Phase 6. Animated Bézier ribbons land in Phase 4.1;
# this cut uses a single scrolling CSS grid (rows align across panes for free)
# with static gutter connectors. Contract:
# docs/ws6-merge-editor-phase4-ui-contract.md. BaseResolver / MergeWorkbench
# autoload from the mod lib dir (do NOT require_relative them here).

# Static assets, emitted inline so Phase 4 takes no dependency on the Decko/
# Sprockets asset pipeline (Gemini's brittleness caveat). The JS is fully
# literal (heredoc with a quoted terminator) and uses String.fromCharCode(10)
# for newlines so it carries no backslashes (per the plan's JS gotchas); it
# reads all state from the JSON island, never from interpolated Ruby.
WS6_MW_CSS = <<~'WS6CSS'
  .ws6-mw{font-family:system-ui,Arial,sans-serif;padding:12px;color:#202124;}
  .ws6-mw .ws6-banner{padding:8px 12px;border-radius:6px;margin-bottom:10px;font-size:14px;}
  .ws6-tier-verified{background:#e6f4ea;border:1px solid #34a853;}
  .ws6-tier-estimated{background:#fef7e0;border:1px solid #f9ab00;}
  .ws6-tier-stale{background:#fce8e6;border:1px solid #d93025;}
  .ws6-warn{margin-top:4px;color:#b06000;font-size:13px;}
  /* Phase 4.1: flex-stack so changed hunks are independent-height "slots" (each
     pane sizes to its content) -> Bézier ribbons fan to fit the differing heights.
     Column widths are kept identical across header / stable / slot rows. */
  .ws6-stackwrap{position:relative;border:1px solid #ddd;border-bottom:none;}
  .ws6-stack{position:relative;max-height:62vh;overflow:auto;}
  .ws6-row{display:flex;align-items:stretch;}
  .ws6-slot{display:flex;align-items:flex-start;border-bottom:1px solid #eee;position:relative;}
  .ws6-col{flex:1 1 0;min-width:0;padding:6px 8px;position:relative;}
  .ws6-sp{flex:0 0 28px;align-self:stretch;}
  .ws6-rail{flex:0 0 210px;padding:6px 8px;background:#fafbfc;font-size:13px;align-self:stretch;}
  .ws6-rail label{display:block;cursor:pointer;}
  .ws6-pre{margin:0;white-space:pre-wrap;word-break:break-word;font-family:ui-monospace,Consolas,monospace;font-size:12px;min-height:1em;}
  .ws6-colhead{flex:1 1 0;min-width:0;font-weight:600;background:#f1f3f4;border-bottom:1px solid #ddd;padding:6px 8px;font-size:11px;text-transform:uppercase;letter-spacing:.04em;position:sticky;top:0;z-index:3;}
  .ws6-colhead.ws6-sp{flex:0 0 28px;background:#f1f3f4;}
  .ws6-colhead.ws6-rail{flex:0 0 210px;background:#f1f3f4;align-self:auto;}
  .ws6-row.ws6-headrow{position:sticky;top:0;z-index:3;}
  .ws6-stable-bar{flex:1 1 100%;padding:4px 10px;color:#888;font-size:12px;background:#f7f7f7;border-bottom:1px solid #eee;}
  .ws6-band-conflict .ws6-col{background:#fdecea;}
  .ws6-band-ai_only .ws6-col{background:#e8f0fe;}
  .ws6-band-human_only .ws6-col{background:#f1f3f4;}
  .ws6-band-both_same .ws6-col{background:#e6f4ea;}
  .ws6-unresolved .ws6-rail{outline:2px solid #d93025;outline-offset:-2px;}
  .ws6-flag{font-size:11px;font-weight:600;color:#d93025;display:none;}
  .ws6-unresolved .ws6-flag{display:block;}
  /* resize grip: drag a pane's bottom edge to grow/shrink its band height. */
  .ws6-grip{position:absolute;left:0;right:0;bottom:0;height:6px;cursor:ns-resize;}
  .ws6-grip:hover{background:rgba(0,0,0,.12);}
  /* single SVG ribbon overlay; scrolls with content; never intercepts clicks. */
  .ws6-ribbons{position:absolute;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:2;overflow:visible;}
  .ws6-ribbon{opacity:.5;}
  .ws6-rib-conflict{fill:#d93025;}
  .ws6-rib-ai_only{fill:#1a73e8;}
  .ws6-rib-human_only{fill:#9aa0a6;}
  .ws6-rib-both_same{fill:#34a853;}
  @media (prefers-reduced-motion: no-preference){ .ws6-ribbon{transition:opacity .2s ease;} }
  .ws6-actions{margin-top:12px;}
  .ws6-actions button{font-size:14px;padding:6px 12px;margin-right:8px;}
  .ws6-actions button[disabled]{opacity:.5;cursor:not-allowed;}
  .ws6-actions button.ws6-danger{border:1px solid #d93025;color:#d93025;background:#fff;}
  .ws6-actions button.ws6-apply{background:#188038;color:#fff;border:1px solid #188038;font-weight:600;}
  .ws6-apply-status{margin-top:8px;padding:8px 10px;border-radius:4px;font-size:13px;}
  .ws6-apply-working{background:#f1f3f4;border:1px solid #bbb;color:#333;}
  .ws6-apply-ok{background:#e6f4ea;border:1px solid #34a853;color:#188038;}
  .ws6-apply-bad{background:#fce8e6;border:1px solid #d93025;color:#b71c1c;font-weight:600;}
  .ws6-draft-notice{margin-top:8px;font-size:13px;color:#5f6368;background:#fef7e0;border:1px solid #f9ab00;border-radius:4px;padding:6px 10px;}
  .ws6-draft-indicator{margin-bottom:10px;font-size:13px;background:#e8f0fe;border:1px solid #1a73e8;border-radius:4px;padding:6px 10px;}
  .ws6-note{font-size:13px;}
  .ws6-ok{color:#188038;}
  .ws6-bad{color:#d93025;font-weight:600;}
  .ws6-preview{margin-top:8px;border:1px solid #ddd;background:#fcfcfc;padding:8px;min-height:60px;}
WS6CSS

WS6_MW_JS = <<~'WS6JS'
  (function () {
    var root = document.querySelector('.ws6-mw');
    if (!root) return;
    var island = root.querySelector('#ws6-mw-data');
    if (!island) return;
    var payload = JSON.parse(island.textContent);
    var defaults = payload.selectionDefaults || {};
    var selections = {};
    var NL = String.fromCharCode(10);

    function assemble() {
      var joiner = (payload.format === 'markdown') ? NL + NL : NL;
      var parts = [];
      payload.hunks.forEach(function (h) {
        if (h.type === 'stable') {
          (h.current || []).forEach(function (b) { parts.push(b); });
          return;
        }
        var side = selections[h.id] || defaults[h.id];
        if (!side) return;
        (h[side] || []).forEach(function (b) { parts.push(b); });
      });
      return parts.filter(function (p) { return p && p.length; }).join(joiner);
    }

    function unresolved() {
      var n = 0;
      payload.hunks.forEach(function (h) {
        if (h.type === 'conflict' && !selections[h.id]) n++;
      });
      return n;
    }

    function markRows() {
      var rows = root.querySelectorAll('[data-type="conflict"]');
      Array.prototype.forEach.call(rows, function (row) {
        var id = row.getAttribute('data-hunk-id');
        if (selections[id]) row.classList.remove('ws6-unresolved');
        else row.classList.add('ws6-unresolved');
      });
    }

    function refresh() {
      var n = unresolved();
      var note = root.querySelector('[data-ws6="conflict-note"]');
      var asm = root.querySelector('[data-ws6="assemble"]');
      if (note) {
        note.textContent = (n === 0)
          ? 'All conflicts resolved'
          : (n + ' conflict' + (n === 1 ? '' : 's') + ' unresolved');
        note.className = 'ws6-note ' + (n === 0 ? 'ws6-ok' : 'ws6-bad');
      }
      if (asm) asm.disabled = (n !== 0);
      // gate the selection-driven actions (create / reset); "open existing
      // draft" is never gated — it just navigates to the saved draft.
      ['[data-ws6="polish"]', '[data-ws6="reset"]'].forEach(function (sel) {
        var b = root.querySelector(sel);
        if (b) b.disabled = (n !== 0);
      });
      markRows();
    }

    root.addEventListener('change', function (ev) {
      var t = ev.target;
      var row = t.closest('[data-hunk-id]');
      if (!row) return;
      var id = row.getAttribute('data-hunk-id');
      var type = row.getAttribute('data-type');
      if (type === 'ai_only') {
        if (t.checked) selections[id] = 'proposal'; else delete selections[id];
      } else if (type === 'conflict') {
        selections[id] = t.value;
      }
      refresh();
    });

    var asmBtn = root.querySelector('[data-ws6="assemble"]');
    if (asmBtn) asmBtn.addEventListener('click', function () {
      if (unresolved() !== 0) return;
      var pre = root.querySelector('[data-ws6="preview"]');
      if (pre) pre.textContent = assemble();
    });

    // Phase 5 handoff. Three actions over the same authenticated seed transport:
    //   - polish  (no draft yet): create the draft from selections, open editor.
    //   - reset   (draft exists): explicit, confirmed DESTRUCTIVE rebuild.
    //   - open    (draft exists): just navigate to the saved draft (preserves
    //             manual TinyMCE edits — the fix for silent-overwrite).
    // The seed POST sends SELECTIONS (not the assembled HTML as authoritative);
    // the server re-derives + re-runs the parent-drift gate. On a stale-parent
    // rejection we reload so the user merges against live reality.
    function editUrl() {
      return '/' + encodeURIComponent(root.getAttribute('data-proposal') + '+merge draft') + '?view=edit';
    }

    function seedMergeDraft(btn, isReset) {
      if (unresolved() !== 0) return;
      if (isReset && !window.confirm(
        'Discard your manual edits and re-assemble the merge draft from your current selections? ' +
        'This permanently deletes the rich-text polishing you have done in the editor.')) return;
      var meta = document.querySelector('meta[name="csrf-token"]');
      var token = meta ? meta.getAttribute('content') : '';
      var fd = new FormData();
      fd.append('card[name]', root.getAttribute('data-proposal'));
      fd.append('card[subcards][+merge draft][content]', assemble());
      fd.append('hunk_selections', JSON.stringify(selections));
      fd.append('parent_act_id', root.getAttribute('data-parent-act-id') || '');
      var orig = btn.textContent;
      btn.disabled = true;
      btn.textContent = 'Working...';
      fetch('/card/update', {
        method: 'POST',
        headers: { 'X-CSRF-Token': token, 'Accept': 'application/json' },
        credentials: 'same-origin',
        body: fd
      }).then(function (res) {
        if (res.ok || res.status === 302) { window.location.href = editUrl(); return; }
        return res.text().then(function (body) {
          btn.disabled = false; btn.textContent = orig;
          if (/parent changed|parent_act_id/i.test(body)) {
            window.alert('The parent card changed since you opened this workbench. Reloading to show the latest changes before you merge.');
            window.location.reload();
          } else {
            window.alert('Could not create the merge draft (HTTP ' + res.status + '). Try reloading the workbench.');
          }
        });
      }).catch(function () {
        btn.disabled = false; btn.textContent = orig;
        window.alert('Network error creating the merge draft.');
      });
    }

    var polishBtn = root.querySelector('[data-ws6="polish"]');
    if (polishBtn) polishBtn.addEventListener('click', function () { seedMergeDraft(polishBtn, false); });
    var resetBtn = root.querySelector('[data-ws6="reset"]');
    if (resetBtn) resetBtn.addEventListener('click', function () { seedMergeDraft(resetBtn, true); });
    var openBtn = root.querySelector('[data-ws6="open-draft"]');
    if (openBtn) openBtn.addEventListener('click', function () { window.location.href = editUrl(); });

    // Apply to parent — the verifying merge-apply (Phase 6). Posts the saved draft
    // content + parent_act_id; the server runs the four-fold gate and only then
    // writes the parent. We trust ONLY the server's verdict.
    // Surface apply outcomes clearly + persistently inline (not just a missable
    // alert), echoing the SERVER's actual reason so failures are unambiguous.
    function setApplyStatus(kind, text) {
      var el = root.querySelector('[data-ws6="apply-status"]');
      if (!el) { window.alert(text); return; }
      el.textContent = text;
      el.className = 'ws6-apply-status ws6-apply-' + kind;
      el.style.display = 'block';
    }

    // Decko returns {error_status, errors:{key:msg,...}} on a rejected save —
    // join the messages so the human sees the exact gate that blocked.
    function serverErrors(body) {
      try {
        var j = JSON.parse(body);
        if (j && j.errors) {
          return Object.keys(j.errors).map(function (k) { return j.errors[k]; }).join(' ');
        }
      } catch (e) { /* not json */ }
      return body && body.length < 300 ? body : '';
    }

    var applyBtn = root.querySelector('[data-ws6="apply"]');
    if (applyBtn) applyBtn.addEventListener('click', function () {
      var parentName = root.getAttribute('data-parent') || 'the parent card';
      if (!window.confirm('Apply this reviewed merge draft to ' + parentName +
        '? This writes the polished content to the parent.')) return;
      var meta = document.querySelector('meta[name="csrf-token"]');
      var token = meta ? meta.getAttribute('content') : '';
      // Exact saved bytes from the JSON island (LF preserved, unlike a textarea).
      var island = root.querySelector('[data-ws6="draft-content"]');
      var content = '';
      if (island) {
        try { content = JSON.parse(island.textContent.split('<' + String.fromCharCode(92) + '/').join('</')); } catch (e) { content = ''; }
      }
      var fd = new FormData();
      fd.append('card[name]', root.getAttribute('data-proposal') + '+merge draft');
      fd.append('card[content]', content);
      fd.append('apply_to_parent', 'true');
      fd.append('parent_act_id', root.getAttribute('data-parent-act-id') || '');
      var orig = applyBtn.textContent;
      applyBtn.disabled = true;
      applyBtn.textContent = 'Applying...';
      setApplyStatus('working', 'Applying to ' + parentName + '...');
      fetch('/card/update', {
        method: 'POST',
        headers: { 'X-CSRF-Token': token, 'Accept': 'application/json' },
        credentials: 'same-origin',
        body: fd
      }).then(function (res) {
        if (res.ok || res.status === 302) {
          setApplyStatus('ok', 'Applied. Opening ' + parentName + '...');
          window.location.href = '/' + encodeURIComponent(root.getAttribute('data-parent'));
          return;
        }
        return res.text().then(function (body) {
          applyBtn.disabled = false; applyBtn.textContent = orig;
          setApplyStatus('bad', 'Apply rejected (HTTP ' + res.status + '). ' +
            (serverErrors(body) || 'See the server log.') + ' The parent was NOT changed.');
        });
      }).catch(function (e) {
        applyBtn.disabled = false; applyBtn.textContent = orig;
        setApplyStatus('bad', 'Network error during apply: ' + (e && e.message) + '. The parent was NOT changed.');
      });
    });

    // ---- Phase 4.1: Bézier ribbon overlay (presentation only) ----------------
    // One SVG overlay; for each changed hunk, draw a closed Bézier ribbon in each
    // gutter whose two adjacent panes differ. The curves fan to fit the panes'
    // (independent) heights. Pure overlay: meaning stays in text/labels/controls;
    // on any failure we hide the SVG and keep the flat thin-cut presentation.
    var SVGNS = 'http://www.w3.org/2000/svg';
    function joinNe(a, b) { return (a || []).join('') !== (b || []).join(''); }

    function addRibbon(svg, leftEl, rightEl, ox, oy, type) {
      var l = leftEl.getBoundingClientRect(), r = rightEl.getBoundingClientRect();
      var x0 = l.right + ox, x1 = r.left + ox, cx = (x0 + x1) / 2;
      var lt = l.top + oy, lb = l.bottom + oy, rt = r.top + oy, rb = r.bottom + oy;
      var d = 'M' + x0 + ',' + lt +
              ' C' + cx + ',' + lt + ' ' + cx + ',' + rt + ' ' + x1 + ',' + rt +
              ' L' + x1 + ',' + rb +
              ' C' + cx + ',' + rb + ' ' + cx + ',' + lb + ' ' + x0 + ',' + lb + ' Z';
      var path = document.createElementNS(SVGNS, 'path');
      path.setAttribute('d', d);
      path.setAttribute('class', 'ws6-ribbon ws6-rib-' + type);
      svg.appendChild(path);
    }

    function buildRibbons() {
      try {
        var svg = root.querySelector('.ws6-ribbons');
        var stack = root.querySelector('.ws6-stack');
        if (!svg || !stack) return;
        while (svg.firstChild) svg.removeChild(svg.firstChild);
        svg.setAttribute('width', stack.scrollWidth);
        svg.setAttribute('height', stack.scrollHeight);
        var s = stack.getBoundingClientRect();
        var ox = -s.left + stack.scrollLeft, oy = -s.top + stack.scrollTop;
        payload.hunks.forEach(function (h) {
          if (h.type === 'stable') return;
          var slot = root.querySelector('[data-hunk-id="' + h.id + '"]');
          if (!slot) return;
          var base = slot.querySelector('.ws6-pane-base');
          var cur = slot.querySelector('.ws6-pane-current');
          var prop = slot.querySelector('.ws6-pane-proposal');
          // Base is centered: gutter 1 connects Current<->Base, gutter 2 Base<->Proposal.
          // 2-way (no base): a single Current<->Proposal ribbon.
          if (base) {
            if (cur && joinNe(h.current, h.base)) addRibbon(svg, cur, base, ox, oy, h.type);
            if (prop && joinNe(h.base, h.proposal)) addRibbon(svg, base, prop, ox, oy, h.type);
          } else if (cur && prop && joinNe(h.current, h.proposal)) {
            addRibbon(svg, cur, prop, ox, oy, h.type);
          }
        });
      } catch (e) {
        var s2 = root.querySelector('.ws6-ribbons');
        if (s2) s2.style.display = 'none';
      }
    }

    var rebuildTimer = null;
    function rebuildSoon() {
      if (rebuildTimer) clearTimeout(rebuildTimer);
      rebuildTimer = setTimeout(buildRibbons, 60);
    }

    // resizable bands: drag a pane's grip to grow/shrink its height; ribbons
    // follow live (this is the "animate to fit the different dimensions").
    root.addEventListener('mousedown', function (ev) {
      var grip = ev.target.closest ? ev.target.closest('.ws6-grip') : null;
      if (!grip) return;
      ev.preventDefault();
      var col = grip.parentNode;
      var startY = ev.clientY, startH = col.getBoundingClientRect().height;
      function move(e) {
        var hgt = Math.max(24, startH + (e.clientY - startY));
        col.style.minHeight = hgt + 'px';
        buildRibbons();
      }
      function up() {
        document.removeEventListener('mousemove', move);
        document.removeEventListener('mouseup', up);
      }
      document.addEventListener('mousemove', move);
      document.addEventListener('mouseup', up);
    });

    // No scroll listener needed: the SVG is an absolute child of the scroll
    // container, so it scrolls with content; only resize/zoom changes geometry.
    if (window.addEventListener) window.addEventListener('resize', rebuildSoon);

    refresh();
    // draw after layout settles (fonts/reflow)
    buildRibbons();
    setTimeout(buildRibbons, 80);
  })();
WS6JS

format :html do
  view :merge_workbench do
    return "" unless card.ok?(:read)

    parent = card.left
    return wrap_with(:div, class: "alert alert-warning") { "Proposal has no parent card." } unless parent

    begin
      fmt = card.type_name == "Markdown" ? :markdown : :html
      resolve = BaseResolver.resolve(card)
      payload = MergeWorkbench.build_payload(
        resolve: resolve, current: parent.db_content.to_s, proposal: card.db_content.to_s,
        format: fmt, proposal_name: card.name, parent_name: parent.name
      )
      merge_workbench_shell(payload)
    rescue StandardError => e
      Rails.logger.error("[ws6 merge_workbench] #{e.class}: #{e.message}")
      wrap_with(:div, class: "alert alert-danger") do
        "Could not render the merge workbench (#{h e.message}). The proposal and its " \
          "parent are unchanged."
      end
    end
  end

  # ---- workbench rendering helpers (pure string building over the payload) ----

  def merge_workbench_shell(payload)
    rows = payload[:hunks].map { |hunk| mw_row(hunk, payload[:mode]) }.join
    island = MergeWorkbench.to_island_json(payload)

    # Phase 5 handoff anchors: CSRF token (for the authenticated seed POST) +
    # the parent's load-time act id (the drift-gate / Phase 6 lock anchor).
    parent = card.left
    parent_act = parent && Card::Action.where(card_id: parent.id)
                                        .where(draft: [false, nil]).order(id: :desc).first&.act&.id
    token = (form_authenticity_token rescue "")

    %(<meta name="csrf-token" content="#{h token}">) +
      %(<div class="ws6-mw" data-proposal="#{h card.name}" data-parent="#{h parent.name}" ) +
      %(data-parent-act-id="#{parent_act}">) +
      mw_banner(payload) +
      mw_draft_indicator +
      %(<div class="ws6-stackwrap"><div class="ws6-stack">) +
      mw_header(payload[:mode]) + rows +
      %(<svg class="ws6-ribbons" xmlns="http://www.w3.org/2000/svg"></svg>) +
      %(</div></div>) +
      mw_actions +
      %(<script type="application/json" id="ws6-mw-data">#{island}</script>) +
      %(<style>#{WS6_MW_CSS}</style>) +
      %(<script>#{WS6_MW_JS}</script>) +
      %(</div>)
  end

  # Prominent "a merge draft already exists" state + preview link (Codex), so the
  # human knows polishing is in progress and where it lives (it is NOT the
  # Current Parent column).
  def mw_draft_indicator
    return "" unless Card.fetch("#{card.name}+merge draft")&.db_content.present?

    url = "/" + "#{card.name}+merge draft".gsub(" ", "%20") + "?view=edit"
    %(<div class="ws6-draft-indicator">&#128221; A merge draft is in progress for this proposal. ) +
      %(<a href="#{h url}">Open it in the editor &rarr;</a></div>)
  end

  def mw_banner(payload)
    counts = payload[:counts]
    tier = payload[:tier].to_s
    cls = case tier
          when "verified" then "ws6-tier-verified"
          when "estimated" then "ws6-tier-estimated"
          else "ws6-tier-stale"
          end
    chip = payload[:mode] == "three_way" ? "3-way (#{h tier})" : "2-way (no base)"
    counts_line = "#{counts[:conflict]} conflict#{counts[:conflict] == 1 ? '' : 's'} · " \
                  "#{counts[:ai_only]} AI · #{counts[:human_only]} human · " \
                  "#{counts[:stable]} unchanged"
    warn = payload[:warning].present? ? %(<div class="ws6-warn">⚠ #{h payload[:warning]}</div>) : ""

    %(<div class="ws6-banner #{cls}">) +
      %(<strong>Merge proposal into #{h payload[:parent]}</strong> — #{chip}<br>) +
      %(#{counts_line}#{warn}</div>)
  end

  def mw_header(mode)
    # Base in the CENTER (Current Parent | Base | Proposal) — the standard 3-way
    # layout: both sides visibly diverge outward from the common ancestor.
    # "Current Parent" (not "human") makes clear this column is the LIVE parent
    # card content, never the merge draft.
    heads =
      if mode == "three_way"
        ["Current Parent", :gutter, "Base", :gutter, "Proposal (AI)", :rail]
      else
        ["Current Parent", :gutter, "Proposal (AI)", :rail]
      end
    cells = heads.map do |hd|
      case hd
      when :gutter then %(<div class="ws6-colhead ws6-sp"></div>)
      when :rail then %(<div class="ws6-colhead ws6-rail">Selection</div>)
      else %(<div class="ws6-colhead">#{h hd}</div>)
      end
    end.join
    %(<div class="ws6-row ws6-headrow">#{cells}</div>)
  end

  def mw_row(hunk, mode)
    if hunk[:type] == "stable"
      n = hunk[:count]
      return %(<div class="ws6-row"><div class="ws6-stable-bar">▸ #{n} unchanged block#{n == 1 ? '' : 's'}</div></div>)
    end

    type = hunk[:type]
    panes =
      if mode == "three_way"
        mw_pane(hunk[:current], "current") + mw_sp + mw_pane(hunk[:base], "base") +
          mw_sp + mw_pane(hunk[:proposal], "proposal")
      else
        mw_pane(hunk[:current], "current") + mw_sp + mw_pane(hunk[:proposal], "proposal")
      end
    panes += mw_rail(hunk)

    %(<div class="ws6-slot ws6-band-#{type}" data-hunk-id="#{h hunk[:id]}" data-type="#{type}">#{panes}</div>)
  end

  # A pane = a resizable content band (the grip lets the user drag its height,
  # which makes the ribbons fan to fit). pane class drives ribbon endpoint lookup.
  def mw_pane(blocks, side)
    %(<div class="ws6-col ws6-pane-#{side}"><pre class="ws6-pre">#{h Array(blocks).join("\n")}</pre>) +
      %(<div class="ws6-grip" title="drag to resize this band"></div></div>)
  end

  def mw_sp
    %(<div class="ws6-sp"></div>)
  end

  # Selection control per hunk type (contract §4). Meaning is carried in text +
  # control, never color/animation alone (Codex: non-semantic animation).
  def mw_rail(hunk)
    id = hunk[:id]
    body =
      case hunk[:type]
      when "conflict"
        %(<span class="ws6-flag">Unresolved — choose a side</span>) +
          %(<label><input type="radio" name="sel-#{h id}" value="current"> keep current</label>) +
          %(<label><input type="radio" name="sel-#{h id}" value="proposal"> take proposal</label>)
      when "ai_only"
        %(<label><input type="checkbox"> accept AI change</label>)
      when "human_only"
        "human edit (kept)"
      else # both_same
        "both sides agree"
      end
    %(<div class="ws6-rail">#{body}</div>)
  end

  def mw_actions
    # If a merge draft already exists (the human has started polishing), the
    # primary action OPENS it (edits preserved); rebuilding is an explicit,
    # confirmed, destructive "Reset" (Codex + Gemini). Otherwise the primary
    # action creates the draft.
    draft = Card.fetch("#{card.name}+merge draft")
    draft_exists = draft&.db_content.present?

    primary =
      if draft_exists
        %(<button type="button" data-ws6="open-draft">Open Existing Merge Draft &rarr;</button>) +
          %(<button type="button" data-ws6="reset" class="ws6-danger">Discard Edits &amp; Re-assemble</button>)
      else
        polish_title = "Create the merge draft from your selections and open it in the editor to polish"
        %(<button type="button" data-ws6="polish" title="#{polish_title}">Assemble &amp; Polish &rarr;</button>)
      end

    notice =
      if draft_exists
        %(<div class="ws6-draft-notice">A merge draft already exists. ) +
          %(<strong>Open Existing Merge Draft</strong> keeps your manual edits; ) +
          %(<strong>Discard Edits &amp; Re-assemble</strong> rebuilds from your current selections ) +
          %(and permanently discards your rich-text polishing.</div>)
      else
        ""
      end

    # Apply to parent — the verifying merge-apply (Phase 6). Active only once a
    # polished merge draft exists; the server re-checks permission, optimistic
    # lock, and the polished_hash before writing the parent. The draft's current
    # (server-side, saved) content rides along hidden so the apply post is a
    # no-op-content trigger whose db_content already matches polished_hash; any
    # tampering is caught by the integrity gate (audit isn't refreshed on apply).
    apply =
      if draft_exists
        # Carry the draft's EXACT saved bytes in a JSON island (NOT a <textarea>,
        # which the browser rewrites to CRLF on submit -> would mismatch the
        # LF-based polished_hash). Posting the content fires the apply act and,
        # being byte-identical to db_content, passes the integrity gate. Any
        # tampered content is still rejected (audit isn't refreshed during apply).
        island = JSON.generate(draft.db_content).gsub("</", "<\\/")
        %(<button type="button" data-ws6="apply" class="ws6-apply">Apply to parent &rarr;</button>) +
          %(<script type="application/json" data-ws6="draft-content">#{island}</script>)
      else
        %(<button type="button" disabled title="Create and polish a merge draft first">Apply to parent</button>)
      end

    %(<div class="ws6-actions">) +
      %(<button type="button" data-ws6="assemble">Assemble Merge Draft</button>) +
      primary +
      %(<span class="ws6-note" data-ws6="conflict-note"></span>) +
      apply +
      notice +
      %(<div class="ws6-apply-status" data-ws6="apply-status" role="alert" style="display:none"></div>) +
      %(<pre class="ws6-pre ws6-preview" data-ws6="preview"></pre>) +
      %(</div>)
  end
end
