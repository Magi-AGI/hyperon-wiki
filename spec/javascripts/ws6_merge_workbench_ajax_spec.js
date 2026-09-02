'use strict';

// CP006E regression harness for the WS6 merge-workbench AJAX handling.
//
// WHY A NODE HARNESS. The behaviour under test lives in the JS that
// mod/editorial_review/set/right/proposal.rb emits inline (WS6_MW_JS). The bug
// is a CLIENT-SIDE decision — "was this response a successful save?" — so a
// server-side spec can only assert on the source text. This harness extracts
// that exact heredoc, runs it against a minimal fake DOM, and drives the real
// click handlers with stubbed fetch responses, so the seed/apply success and
// rejection paths are exercised as behaviour rather than asserted as strings.
//
// NO npm DEPENDENCIES ON PURPOSE. The Decko runtime image has no node and no
// JS test toolchain; adding jsdom/jest would put this gate behind an install
// step the deck does not otherwise need. Everything below is stdlib (vm + fs).
//
// RUN: node spec/javascripts/ws6_merge_workbench_ajax_spec.js
// The companion RSpec file (spec/mod/editorial_review/merge_workbench_ajax_
// redirect_spec.rb) shells out to this when `node` is on PATH, and always
// enforces the structural guards so the regression is covered either way.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const PROPOSAL_RB = path.join(
  __dirname, '..', '..', 'mod', 'editorial_review', 'set', 'right', 'proposal.rb'
);

// ---- extract the WS6_MW_JS squiggly heredoc verbatim ------------------------
function extractWorkbenchJs () {
  // Normalize CRLF: a Windows checkout (core.autocrlf) rewrites the working
  // copy, but the deck always evaluates the LF form.
  const src = fs.readFileSync(PROPOSAL_RB, 'utf8').split('\r\n').join('\n');
  const start = src.indexOf("WS6_MW_JS = <<~'WS6JS'\n");
  if (start === -1) throw new Error('WS6_MW_JS heredoc not found in proposal.rb');
  const bodyStart = src.indexOf('\n', start) + 1;
  const end = src.indexOf('\nWS6JS\n', bodyStart);
  if (end === -1) throw new Error('WS6JS heredoc terminator not found');
  const lines = src.slice(bodyStart, end).split('\n');
  // <<~ strips the smallest indentation across non-blank lines.
  const indent = lines
    .filter((l) => l.trim().length)
    .reduce((m, l) => Math.min(m, l.match(/^ */)[0].length), Infinity);
  return lines.map((l) => l.slice(indent)).join('\n');
}

const WORKBENCH_JS = extractWorkbenchJs();

// ---- minimal fake DOM -------------------------------------------------------
// Supports exactly the selector shapes the workbench JS uses:
//   .class   #id   [attr="value"]   tag[attr="value"]
function parseSelector (sel) {
  let m = sel.match(/^\.([\w-]+)$/);
  if (m) return { kind: 'class', value: m[1] };
  m = sel.match(/^#([\w-]+)$/);
  if (m) return { kind: 'id', value: m[1] };
  m = sel.match(/^([a-zA-Z][\w-]*)?\[([\w-]+)="([^"]*)"\]$/);
  if (m) return { kind: 'attr', tag: m[1] || null, name: m[2], value: m[3] };
  m = sel.match(/^([a-zA-Z][\w-]*)$/);
  if (m) return { kind: 'tag', value: m[1] };
  throw new Error('fake DOM: unsupported selector ' + sel);
}

function matches (el, parsed) {
  switch (parsed.kind) {
    case 'class': return el.classList.contains(parsed.value);
    case 'id': return el.getAttribute('id') === parsed.value;
    case 'tag': return el.tagName === parsed.value;
    case 'attr':
      if (parsed.tag && el.tagName !== parsed.tag) return false;
      return el.getAttribute(parsed.name) === parsed.value;
    default: return false;
  }
}

function makeEl (tagName, attrs) {
  attrs = attrs || {};
  const classes = new Set(String(attrs.class || '').split(/\s+/).filter(Boolean));
  const el = {
    tagName,
    children: [],
    parentNode: null,
    firstChild: null,
    textContent: attrs.text || '',
    disabled: !!attrs.disabled,
    style: {},
    _attrs: Object.assign({}, attrs),
    _listeners: {},
    classList: {
      add: (c) => classes.add(c),
      remove: (c) => classes.delete(c),
      contains: (c) => classes.has(c)
    },
    get className () { return Array.from(classes).join(' '); },
    set className (v) {
      classes.clear();
      String(v).split(/\s+/).filter(Boolean).forEach((c) => classes.add(c));
    },
    getAttribute (n) { return Object.prototype.hasOwnProperty.call(el._attrs, n) ? el._attrs[n] : null; },
    setAttribute (n, v) { el._attrs[n] = String(v); },
    appendChild (child) { el.children.push(child); child.parentNode = el; return child; },
    removeChild (child) {
      el.children = el.children.filter((c) => c !== child);
      return child;
    },
    addEventListener (type, fn) { (el._listeners[type] = el._listeners[type] || []).push(fn); },
    removeEventListener (type, fn) {
      el._listeners[type] = (el._listeners[type] || []).filter((f) => f !== fn);
    },
    dispatch (type, ev) {
      (el._listeners[type] || []).forEach((fn) => fn(Object.assign({ target: el }, ev || {})));
    },
    closest () { return null; },
    getBoundingClientRect () { return { top: 0, bottom: 10, left: 0, right: 10, height: 10, width: 10 }; },
    querySelector (sel) { return descendants(el).find((d) => matches(d, parseSelector(sel))) || null; },
    querySelectorAll (sel) {
      const p = parseSelector(sel);
      return descendants(el).filter((d) => matches(d, p));
    }
  };
  el.classList.value = classes;
  return el;
}

function descendants (node, out) {
  out = out || [];
  (node.children || []).forEach((c) => { out.push(c); descendants(c, out); });
  return out;
}

// ---- fixtures ---------------------------------------------------------------
const PROPOSAL_NAME = 'CP006E Parent+proposal';
const PARENT_NAME = 'CP006E Parent';
const DRAFT_BODY = '<p>polished merge result</p>';

// One stable hunk + one ai_only hunk: no conflicts, so the selection-driven
// actions are enabled and assemble() produces content without any clicking.
const PAYLOAD = {
  schemaVersion: 1,
  mode: 'three_way',
  tier: 'verified',
  format: 'html',
  parent: PARENT_NAME,
  hunks: [
    { type: 'stable', count: 1, current: ['<p>A</p>'] },
    { type: 'ai_only', id: 'h2', default: 'current', current: ['<p>B</p>'], base: ['<p>B</p>'], proposal: ['<p>B2</p>'] }
  ],
  selectionDefaults: { h2: 'current' },
  counts: { conflict: 0, ai_only: 1, human_only: 0, stable: 1 }
};

function buildDocument (opts) {
  const withDraft = !!opts.withDraft;

  const meta = makeEl('meta', { name: 'csrf-token', content: 'test-csrf-token' });

  const root = makeEl('div', {
    class: 'ws6-mw',
    'data-proposal': PROPOSAL_NAME,
    'data-parent': PARENT_NAME,
    'data-parent-act-id': '121628'
  });

  const island = makeEl('script', { id: 'ws6-mw-data' });
  island.textContent = JSON.stringify(PAYLOAD);
  root.appendChild(island);

  root.appendChild(makeEl('button', { 'data-ws6': 'assemble' }));
  if (withDraft) {
    root.appendChild(makeEl('button', { 'data-ws6': 'open-draft' }));
    root.appendChild(makeEl('button', { 'data-ws6': 'reset', class: 'ws6-danger' }));
  } else {
    root.appendChild(makeEl('button', { 'data-ws6': 'polish' }));
  }
  root.appendChild(makeEl('span', { class: 'ws6-note', 'data-ws6': 'conflict-note' }));

  if (withDraft) {
    root.appendChild(makeEl('button', { 'data-ws6': 'apply', class: 'ws6-apply' }));
    const draftIsland = makeEl('script', { 'data-ws6': 'draft-content' });
    // Matches the Ruby side: JSON.generate(content).gsub("</", "<\\/")
    draftIsland.textContent = JSON.stringify(DRAFT_BODY).split('</').join('<\\/');
    root.appendChild(draftIsland);
  }

  root.appendChild(makeEl('div', { class: 'ws6-apply-status', 'data-ws6': 'apply-status' }));
  root.appendChild(makeEl('pre', { class: 'ws6-pre ws6-preview', 'data-ws6': 'preview' }));

  const docRoot = makeEl('html', {});
  docRoot.appendChild(meta);
  docRoot.appendChild(root);

  const document = {
    querySelector: (sel) => docRoot.querySelector(sel),
    querySelectorAll: (sel) => docRoot.querySelectorAll(sel),
    createElementNS: (_ns, tag) => makeEl(tag, {}),
    addEventListener () {},
    removeEventListener () {}
  };

  return { document, root, docRoot };
}

// ---- harness ----------------------------------------------------------------
function runWorkbench (opts) {
  const { document, root } = buildDocument(opts);

  const record = {
    fetchCalls: [],
    alerts: [],
    navigations: [],
    reloads: 0,
    confirms: []
  };

  const location = {};
  Object.defineProperty(location, 'href', {
    get () { return record.navigations[record.navigations.length - 1] || ''; },
    set (v) { record.navigations.push(v); }
  });
  location.reload = () => { record.reloads += 1; };

  const window = {
    location,
    alert: (msg) => record.alerts.push(String(msg)),
    confirm: (msg) => { record.confirms.push(String(msg)); return opts.confirm !== false; },
    addEventListener () {},
    removeEventListener () {}
  };

  const fetchStub = (url, init) => {
    record.fetchCalls.push({ url, init });
    return opts.respond(url, init);
  };

  const sandbox = {
    window,
    document,
    fetch: fetchStub,
    FormData,
    JSON,
    Object,
    Array,
    Math,
    String,
    Number,
    Boolean,
    Promise,
    Error,
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout,
    console
  };
  sandbox.globalThis = sandbox;

  vm.runInNewContext(WORKBENCH_JS, sandbox, { filename: 'ws6_mw.js' });

  return { root, record, document };
}

// Let the fetch promise chain settle (the handlers are 1-2 microtask hops deep).
function settle () {
  return new Promise((resolve) => setTimeout(resolve, 5));
}

function res (props) {
  return Promise.resolve(Object.assign({
    ok: false,
    status: 200,
    type: 'basic',
    text: () => Promise.resolve('')
  }, props));
}

const OPAQUE_REDIRECT = () => res({ ok: false, status: 0, type: 'opaqueredirect' });
const PLAIN_303 = () => res({ ok: false, status: 303, type: 'basic' });
const OK_200 = () => res({ ok: true, status: 200, type: 'basic' });
const FORBIDDEN_403 = () => res({
  ok: false,
  status: 403,
  type: 'basic',
  text: () => Promise.resolve(JSON.stringify({
    error_status: 403,
    errors: { permission_denied: 'You do not have permission to update this card' }
  }))
});
const STALE_PARENT_409 = () => res({
  ok: false,
  status: 409,
  type: 'basic',
  text: () => Promise.resolve(JSON.stringify({
    error_status: 409, errors: { parent_act_id: 'parent changed since this workbench was opened' }
  }))
});
const NETWORK_FAILURE = () => Promise.reject(new TypeError('NetworkError when attempting to fetch resource.'));

// ---- assertions -------------------------------------------------------------
const failures = [];
let currentTest = null;

function check (ok, message) {
  if (!ok) failures.push(currentTest + ': ' + message);
}

function includes (haystack, needle, label) {
  check(String(haystack).indexOf(needle) !== -1,
    label + ' expected to include ' + JSON.stringify(needle) + ' but was ' + JSON.stringify(String(haystack)));
}

function excludes (haystack, needle, label) {
  check(String(haystack).indexOf(needle) === -1,
    label + ' expected NOT to include ' + JSON.stringify(needle) + ' but was ' + JSON.stringify(String(haystack)));
}

const tests = [];
function test (name, fn) { tests.push({ name, fn }); }

function clickSeed (h) {
  const btn = h.root.querySelector('[data-ws6="polish"]') || h.root.querySelector('[data-ws6="reset"]');
  btn.dispatch('click');
  return btn;
}

function clickApply (h) {
  const btn = h.root.querySelector('[data-ws6="apply"]');
  btn.dispatch('click');
  return btn;
}

function applyStatus (h) {
  return h.root.querySelector('[data-ws6="apply-status"]');
}

// --- (1) seed path must not follow the deck's configured-origin redirect -----
test('seed POST opts out of following redirects', async () => {
  const h = runWorkbench({ respond: OPAQUE_REDIRECT });
  clickSeed(h);
  await settle();
  check(h.record.fetchCalls.length === 1, 'expected exactly one seed POST');
  const init = h.record.fetchCalls[0].init || {};
  check(init.redirect === 'manual',
    "seed fetch init.redirect expected 'manual' but was " + JSON.stringify(init.redirect));
  check(init.method === 'POST', 'seed fetch must stay a POST');
  check(init.credentials === 'same-origin', 'seed fetch must keep same-origin credentials');
});

test('seed treats an opaque redirect as a committed save and navigates locally', async () => {
  const h = runWorkbench({ respond: OPAQUE_REDIRECT });
  clickSeed(h);
  await settle();
  check(h.record.alerts.length === 0,
    'no alert expected after a committed save, got: ' + JSON.stringify(h.record.alerts));
  check(h.record.navigations.length === 1, 'expected exactly one navigation');
  const url = h.record.navigations[0] || '';
  check(url.charAt(0) === '/', 'navigation must stay local/relative, got ' + JSON.stringify(url));
  includes(url, 'merge%20draft', 'seed navigation');
  includes(url, 'view=edit', 'seed navigation');
});

test('seed treats a visible 3xx as a committed save', async () => {
  const h = runWorkbench({ respond: PLAIN_303 });
  clickSeed(h);
  await settle();
  check(h.record.alerts.length === 0, 'no alert expected for a 303, got: ' + JSON.stringify(h.record.alerts));
  check(h.record.navigations.length === 1, 'expected local navigation after a 303');
});

test('seed still succeeds on a plain 200', async () => {
  const h = runWorkbench({ respond: OK_200 });
  clickSeed(h);
  await settle();
  check(h.record.alerts.length === 0, 'no alert expected for a 200');
  check(h.record.navigations.length === 1, 'expected local navigation after a 200');
});

// --- (2) apply path must do the same -----------------------------------------
test('apply POST opts out of following redirects', async () => {
  const h = runWorkbench({ withDraft: true, respond: OPAQUE_REDIRECT });
  clickApply(h);
  await settle();
  check(h.record.fetchCalls.length === 1, 'expected exactly one apply POST');
  const init = h.record.fetchCalls[0].init || {};
  check(init.redirect === 'manual',
    "apply fetch init.redirect expected 'manual' but was " + JSON.stringify(init.redirect));
  check(init.credentials === 'same-origin', 'apply fetch must keep same-origin credentials');
});

test('apply reports success (never "NOT changed") after a committed save', async () => {
  const h = runWorkbench({ withDraft: true, respond: OPAQUE_REDIRECT });
  clickApply(h);
  await settle();
  const status = applyStatus(h);
  includes(status.textContent, 'Applied.', 'apply status');
  excludes(status.textContent, 'NOT changed', 'apply status');
  excludes(status.textContent, 'Network error', 'apply status');
  includes(status.className, 'ws6-apply-ok', 'apply status class');
  check(h.record.navigations.length === 1, 'expected navigation to the parent');
  check((h.record.navigations[0] || '').charAt(0) === '/', 'apply navigation must stay local/relative');
});

test('apply posts the exact saved draft bytes and the parent lock', async () => {
  const h = runWorkbench({ withDraft: true, respond: OPAQUE_REDIRECT });
  clickApply(h);
  await settle();
  const fd = h.record.fetchCalls[0].init.body;
  check(fd.get('card[content]') === DRAFT_BODY,
    'apply must post the saved draft bytes, got ' + JSON.stringify(fd.get('card[content]')));
  check(fd.get('apply_to_parent') === 'true', 'apply_to_parent flag must be posted');
  check(fd.get('parent_act_id') === '121628', 'parent_act_id lock must be posted');
});

// --- (3) rejection paths must still fail closed ------------------------------
test('seed still reports a true 403 rejection', async () => {
  const h = runWorkbench({ respond: FORBIDDEN_403 });
  const btn = clickSeed(h);
  await settle();
  check(h.record.navigations.length === 0, 'a rejected seed must NOT navigate');
  check(h.record.alerts.length === 1, 'expected one rejection alert');
  includes(h.record.alerts[0], 'HTTP 403', 'seed rejection alert');
  check(btn.disabled === false, 'the seed button must be re-enabled after a rejection');
});

test('seed still detects the stale-parent rejection and reloads', async () => {
  const h = runWorkbench({ respond: STALE_PARENT_409 });
  clickSeed(h);
  await settle();
  check(h.record.navigations.length === 0, 'a stale-parent rejection must NOT navigate to the editor');
  includes(h.record.alerts[0] || '', 'parent card changed', 'stale-parent alert');
  check(h.record.reloads === 1, 'expected a reload so the human merges against live reality');
});

test('seed still fails closed on a pre-response network failure', async () => {
  const h = runWorkbench({ respond: NETWORK_FAILURE });
  clickSeed(h);
  await settle();
  check(h.record.navigations.length === 0, 'a network failure must NOT be reported as success');
  includes(h.record.alerts[0] || '', 'Network error creating the merge draft', 'network failure alert');
});

test('apply still reports a true 403 rejection with the server reason', async () => {
  const h = runWorkbench({ withDraft: true, respond: FORBIDDEN_403 });
  const btn = clickApply(h);
  await settle();
  const status = applyStatus(h);
  includes(status.textContent, 'Apply rejected (HTTP 403)', 'apply rejection status');
  includes(status.textContent, 'You do not have permission', 'apply rejection status');
  includes(status.textContent, 'The parent was NOT changed.', 'apply rejection status');
  includes(status.className, 'ws6-apply-bad', 'apply rejection class');
  check(h.record.navigations.length === 0, 'a rejected apply must NOT navigate');
  check(btn.disabled === false, 'the apply button must be re-enabled after a rejection');
});

test('apply still fails closed on a pre-response network failure', async () => {
  const h = runWorkbench({ withDraft: true, respond: NETWORK_FAILURE });
  clickApply(h);
  await settle();
  const status = applyStatus(h);
  includes(status.textContent, 'Network error during apply', 'apply network-failure status');
  includes(status.textContent, 'The parent was NOT changed.', 'apply network-failure status');
  check(h.record.navigations.length === 0, 'a network failure must NOT be reported as an applied merge');
});

test('apply is still gated behind an explicit confirm', async () => {
  const h = runWorkbench({ withDraft: true, confirm: false, respond: OK_200 });
  clickApply(h);
  await settle();
  check(h.record.confirms.length === 1, 'expected a confirm prompt');
  check(h.record.fetchCalls.length === 0, 'declining the confirm must not POST');
});

test('reset is still gated behind an explicit destructive confirm', async () => {
  const h = runWorkbench({ withDraft: true, confirm: false, respond: OK_200 });
  h.root.querySelector('[data-ws6="reset"]').dispatch('click');
  await settle();
  check(h.record.confirms.length === 1, 'expected a destructive-reset confirm prompt');
  check(h.record.fetchCalls.length === 0, 'declining the reset confirm must not POST');
});

// ---- go ---------------------------------------------------------------------
(async () => {
  for (const t of tests) {
    currentTest = t.name;
    try {
      await t.fn();
    } catch (e) {
      failures.push(t.name + ': threw ' + (e && e.stack ? e.stack : e));
    }
  }
  const passed = tests.length - new Set(failures.map((f) => f.split(':')[0])).size;
  if (failures.length) {
    console.error('\nFAILURES (' + failures.length + '):');
    failures.forEach((f) => console.error('  - ' + f));
    console.error('\n' + passed + '/' + tests.length + ' examples passed');
    process.exit(1);
  }
  console.log(tests.length + '/' + tests.length + ' examples passed');
  process.exit(0);
})();
