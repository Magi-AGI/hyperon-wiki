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
  .ws6-grid{display:grid;border:1px solid #ddd;border-bottom:none;max-height:62vh;overflow:auto;}
  .ws6-grid.ws6-3{grid-template-columns:1fr 28px 1fr 28px 1fr 210px;}
  .ws6-grid.ws6-2{grid-template-columns:1fr 28px 1fr 210px;}
  .ws6-row{display:contents;}
  .ws6-cell{padding:6px 8px;border-bottom:1px solid #eee;min-width:0;}
  .ws6-pre{margin:0;white-space:pre-wrap;word-break:break-word;font-family:ui-monospace,Consolas,monospace;font-size:12px;}
  .ws6-gutter{background:#fafafa;text-align:center;color:#bbb;}
  .ws6-rail{padding:6px 8px;border-bottom:1px solid #eee;background:#fafbfc;font-size:13px;}
  .ws6-rail label{display:block;cursor:pointer;}
  .ws6-colhead{font-weight:600;background:#f1f3f4;border-bottom:1px solid #ddd;padding:6px 8px;font-size:11px;text-transform:uppercase;letter-spacing:.04em;position:sticky;top:0;z-index:1;}
  .ws6-stable-cell{grid-column:1/-1;padding:4px 10px;color:#888;font-size:12px;background:#f7f7f7;border-bottom:1px solid #eee;}
  .ws6-band-conflict .ws6-cell{background:#fdecea;}
  .ws6-band-ai_only .ws6-cell{background:#e8f0fe;}
  .ws6-band-human_only .ws6-cell{background:#f1f3f4;}
  .ws6-band-both_same .ws6-cell{background:#e6f4ea;}
  .ws6-unresolved .ws6-rail{outline:2px solid #d93025;outline-offset:-2px;}
  .ws6-flag{font-size:11px;font-weight:600;color:#d93025;}
  .ws6-actions{margin-top:12px;}
  .ws6-actions button{font-size:14px;padding:6px 12px;margin-right:8px;}
  .ws6-actions button[disabled]{opacity:.5;cursor:not-allowed;}
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

    refresh();
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
    cols = payload[:mode] == "three_way" ? "ws6-3" : "ws6-2"
    rows = payload[:hunks].map { |hunk| mw_row(hunk, payload[:mode]) }.join
    island = MergeWorkbench.to_island_json(payload)

    %(<div class="ws6-mw">) +
      mw_banner(payload) +
      %(<div class="ws6-grid #{cols}">#{mw_header(payload[:mode])}#{rows}</div>) +
      mw_actions +
      %(<script type="application/json" id="ws6-mw-data">#{island}</script>) +
      %(<style>#{WS6_MW_CSS}</style>) +
      %(<script>#{WS6_MW_JS}</script>) +
      %(</div>)
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
    heads =
      if mode == "three_way"
        ["Base", :gutter, "Current (human)", :gutter, "Proposal (AI)", "Selection"]
      else
        ["Current (human)", :gutter, "Proposal (AI)", "Selection"]
      end
    heads.map do |hd|
      hd == :gutter ? %(<div class="ws6-colhead ws6-gutter"></div>) : %(<div class="ws6-colhead">#{h hd}</div>)
    end.join
  end

  def mw_row(hunk, mode)
    if hunk[:type] == "stable"
      n = hunk[:count]
      return %(<div class="ws6-stable-cell">▸ #{n} unchanged block#{n == 1 ? '' : 's'}</div>)
    end

    type = hunk[:type]
    cells =
      if mode == "three_way"
        mw_cell(hunk[:base]) + mw_gutter + mw_cell(hunk[:current]) + mw_gutter + mw_cell(hunk[:proposal])
      else
        mw_cell(hunk[:current]) + mw_gutter + mw_cell(hunk[:proposal])
      end
    cells += mw_rail(hunk)

    %(<div class="ws6-row ws6-band-#{type}" data-hunk-id="#{h hunk[:id]}" data-type="#{type}">#{cells}</div>)
  end

  def mw_cell(blocks)
    %(<div class="ws6-cell"><pre class="ws6-pre">#{h Array(blocks).join("\n")}</pre></div>)
  end

  def mw_gutter
    %(<div class="ws6-cell ws6-gutter">›</div>)
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
    apply_title = "Simulation Mode — apply lands in Phase 6 (verifying merge-apply)"
    %(<div class="ws6-actions">) +
      %(<button type="button" data-ws6="assemble">Assemble Merge Draft</button>) +
      %(<span class="ws6-note" data-ws6="conflict-note"></span>) +
      %(<button type="button" disabled title="#{apply_title}">Apply to parent — Simulation Mode</button>) +
      %(<pre class="ws6-pre ws6-preview" data-ws6="preview"></pre>) +
      %(</div>)
  end
end
