# CHANGES TO DECKO

## DONE
- TinyMCE fullscreen button enabled (`mod/hyperon_ui/assets/script/tinymce_fullscreen.js.coffee`)
- Decko modal made full screen (`mod/hyperon_ui/set/all/edit_modal.rb` + `hyperon_ui.scss`)
- `wiki_nav_tree` mod implemented (`mod/wiki_nav_tree/`) — lazy-loads child pages via slotter, respects read permissions, filters system cards

## IN PROGRESS
- UI overhaul — phased plan below
Correctly implement the header design spec: Make the header logo small and make the theme switcher correctly swap the background color.  
Nav Tree: The sidebar links should have background color boxes with descending opacity color. currently selected page should be highlighted. Breadcrumb should be visible in the sidebar above contents.

## PLANNED — Phased Implementation

See full design spec in [UI LAYOUT](#ui-layout) below. Implementation is organized into four phases by effort and dependency order, following [The Decko Way](#design-methodology).

### Phase 1 — Zero/Minimal Code (Config + CSS only)
These require no new mod files; changes go into existing mods or the wiki's rule cards directly.

- [ ] **Wire wiki_nav_tree into left sidebar** — Set `*sidebar` card content to `{{_|view:wiki_nav_tree}}` via the wiki admin UI. No code change.
- [ ] **Rename navbox menu items** — Edit `*navbox` card content directly in the wiki UI: "Getting started" → "Start", "Recent Changes" → "Recent". No code change.
- [ ] **Sticky navbar + sticky sidebars** — Add `position: sticky` CSS to `mod/hyperon_ui/assets/style/hyperon_ui.scss` targeting Decko's existing `header` and `aside` elements.
- [ ] **Override Sign in/out/up labels** — Add `mod/hyperon_ui/set/self/account_links.rb`, override `account_link_text` to return "Login 🔑", "Logout ⏻", "Register". Override `account_dropdown_label` to return "Account 👤".

### Phase 2 — View Overrides in `hyperon_ui` mod (Small Code)
Override Decko views within the existing `hyperon_ui` mod. No new mods needed.

- [ ] **Two-sidebar layout** — Override `layout :default` in `mod/hyperon_ui/set/all/layouts.rb` to output a second `<aside id="sidebar-right">` alongside the existing left sidebar. Wire CSS Grid in `hyperon_ui.scss`.
- [ ] **Breadcrumbs view** — Add `view :breadcrumbs` to `mod/hyperon_ui/set/all/` using `card.name.to_name.part_names` to build Bootstrap `.breadcrumb` markup. Render in the right sidebar.
- [ ] **Page TOC view** — Add `view :page_toc` using Nokogiri (already available) to parse rendered content and extract `h2`/`h3`/`h4` headings into a nested link list. Render in the right sidebar.
- [ ] **Dark/light theme toggle** — Add a CoffeeScript asset to `hyperon_ui` that toggles Bootstrap's `data-bs-theme` attribute on `<html>` and persists via `localStorage`. Add toggle button to `*navbox` card content as a Decko link. Add `[data-bs-theme="dark"] { … }` overrides in `hyperon_ui.scss`.
- [ ] **Ben's Focus Mode** — Extend `mod/wiki_nav_tree/set/all/wiki_nav_tree.rb`: override `nav_tree_parent_card` to check `Env.session[:nav_root]` before the env var. Add a small "Focus here / Clear focus" button view that sets/clears the session key.
- [ ] **Active ancestor expansion in nav tree** — Extend `render_wiki_nav_row` to compare each nav card against the current context card's ancestor chain (`card.name.to_name.part_names`) and pre-render matching children inline (expanded) instead of deferred.
- [ ] **Logo: icon + text, responsive hide** — Override the header/brand view in `hyperon_ui` to render an `<img>` icon alongside a `<span class="d-none d-md-inline">` text span. CSS hides the text below Bootstrap's `md` breakpoint.
- [ ] **Collapsible search field** — Override the navbox search view in `hyperon_ui` to render a collapsed `<input>` with a 🔎 icon; JS expands it on focus/click.

### Phase 3 — New Features via Existing Mods (Moderate Code)
Wire up already-installed Decko mods; add companion views/permissions.

- [ ] **Comments via `card-mod-comment`** — `card-mod-comment` is already installed (part of `card-mod-defaults`). Nest `{{+*discussion|view:comment_box}}` in the right sidebar or page footer view. Configure `*discussion+*create` and `*discussion+*read` permission rule cards in the wiki admin UI for role-based access — no code needed for permissions.
- [ ] **User avatars** — Create `+avatar` as an Image-type subcard on User cards (carrierwave is already installed). Override `account_dropdown_label` in `hyperon_ui/set/self/account_links.rb` to `image_tag(avatar.image_url(:icon))` when `Auth.current.name+avatar` exists. Add `{{+avatar}}` to `+account_settings` card content in the wiki UI.

### Phase 4 — New Mods (Higher Effort)
Package as standalone reusable Decko mods.

- [ ] **Star/Pin actions (`mod/wiki_actions/`)** — Store stars as `CardName+*stars` (Pointer card, one username per line). Store pins as `CardName+*pinned` (Basic card, integer priority). Add `view :star_button` and `view :pin_button` with Decko event handlers for toggling. Count stars from `+*stars` content line count. Render in the right sidebar's Wiki Page Box.
- [ ] **Local graph (`mod/local_graph/`)** — Add `view :local_graph` that renders `<div class="local-graph" data-links="…">` where `data-links` is JSON built from CQL queries (`links_to`, `linked_to_by`, left/right compound relationships). Add a CoffeeScript asset initializing Cytoscape.js or vis.js inside that div. Render at the top of the right sidebar.

---

# TESTING

UI work splits across three test tracks. Each has a different toolchain and a different question it can answer.

## Track 1 — Structural / Behavioral Specs (RSpec, no database)

**Toolchain:** `decko-rspec` (already in Gemfile), run via `bundle exec rspec spec/mod/`

**What they verify:** That every view is defined, that permission guards and slotter wiring are present, that key CSS classes exist in SCSS files. These tests catch regressions when behavioral code is accidentally removed or renamed.

**What they cannot verify:** That views render correctly, that the HTML structure is right, or that cards are queried correctly at runtime. Those require a live Decko test deck (see Track 2).

**Convention:** Every mod that defines `view :` blocks gets a companion spec in `spec/mod/<mod_name>_spec.rb`. Each spec covers:
- View definition exists (guards against typos / accidental removal)
- Slotter wiring if lazy-loading is used
- Permission checks are present (`ok?(:read)`, `trash: false`)
- SCSS defines the classes referenced in the Ruby

**Running:**
```bash
bundle exec rspec spec/mod/
# ~67ms — no Rails boot, no database needed
```

**Example pattern** (see `spec/mod/wiki_nav_tree_spec.rb`):
```ruby
it "checks read permission on every card" do
  expect(source).to include(".ok?(:read)")
end
```

## Track 2 — View Rendering Specs (RSpec + Capybara, requires Decko test deck)

**Toolchain:** `decko-rspec` + Capybara (both already bundled), but requires a seeded test database

**What they verify:** That views produce correct HTML — heading anchor links in the TOC, correct breadcrumb order, expanded ancestors in the nav tree, the right Bootstrap classes applied.

**Setup:** A Decko test deck needs seed cards. Run `bundle exec decko seed` in the test environment, then write specs using Capybara's `have_css` / `have_link` matchers against rendered view output.

**Convention:** View rendering specs live in `spec/views/<mod_name>/` and use Decko's card test helpers to instantiate a card, call `render(:view_name)`, and assert on the resulting HTML.

**Running:**
```bash
RAILS_ENV=test bundle exec rspec spec/views/
```

**When to write:** Add a rendering spec whenever a new `view :` block is added in Phase 2 or later that produces non-trivial HTML (TOC, breadcrumbs, two-sidebar layout).

## Track 3 — Cypress End-to-End Specs (JS behaviors, requires running server)

**Toolchain:** `decko-cypress` (in Gemfile, currently commented out) — uncomment and run `bundle install` to enable

**What they verify:** JavaScript-dependent behaviors that can't be tested in Ruby:
- Dark mode toggle persists `data-bs-theme` across page loads (checked via `localStorage`)
- Collapsible search expands on click and collapses when empty and blurred
- Focus Mode sets and clears the nav tree root per-session
- Nav tree slotter loads children on ▸ click without a full page reload

**Running:**
```bash
# Requires a running dev server: bundle exec thin start
bundle exec cypress run
```

**When to write:** Add a Cypress spec for each JS-dependent item in Phase 2 (dark mode, collapsible search, Focus Mode) as those features are implemented.

## Track 4 — Manual Visual Checklist (CSS/layout, per-phase)

CSS correctness — sticky positioning, grid column widths, opacity gradients, responsive logo hide — cannot be automated. Before marking any phase complete, verify this checklist in a browser:

### Phase 1 checklist
- [ ] Header stays pinned at top when scrolling a long page
- [ ] Left sidebar stays pinned and scrolls independently from the article
- [ ] Nav tree appears in left sidebar (not the old default sidebar content)
- [ ] Navbox shows "Login 🔑", "Logout ⏻", "Register", "Account 👤"
- [ ] "Start" and "Recent" appear in place of old labels

### Phase 2 checklist
- [ ] Right sidebar appears and stays pinned during article scroll
- [ ] Breadcrumbs show correct parent chain for a nested page
- [ ] TOC shows all h2/h3/h4 headings; anchor links jump to correct sections
- [ ] Dark mode toggle switches theme; preference survives a page reload
- [ ] Logo icon stays visible on narrow viewport; text hides below `md` breakpoint
- [ ] Search collapses to 🔎 icon by default; expands on click
- [ ] Nav tree auto-expands ancestors of the current page on load
- [ ] Focus Mode button narrows the nav tree to the current card's subtree

### Phase 3 checklist
- [ ] Comment box appears; anonymous and signed-in comments render correctly
- [ ] Avatar upload field visible in account settings; avatar shown in navbar dropdown

### Phase 4 checklist
- [ ] Star button toggles; count increments/decrements correctly
- [ ] Pin badge visible in nav tree for pinned cards
- [ ] Local graph renders for a card with multiple links; nodes are clickable

## Summary

| Track | Tool | DB needed | Covers |
|---|---|---|---|
| 1 — Structural | `bundle exec rspec spec/mod/` | No | View defined, guards present, SCSS classes |
| 2 — Rendering | `bundle exec rspec spec/views/` | Yes (test deck) | HTML structure, card query output |
| 3 — Cypress | `bundle exec cypress run` | Yes (dev server) | JS toggle/session behaviors |
| 4 — Visual | Browser + checklist | Yes (dev server) | CSS layout, responsive breakpoints |

---

# DECKO

The site is a wiki meant to utilize Decko's unique "everything is a card" flexibility to support a hypergraph of cards about the SNET Hyperon ecosystem and Atomspace cognitive architectures.

## Design Methodology

- **Wiki Pattern:** This is a [Wiki design pattern](https://ui-patterns.com/patterns/Wiki).
- **The Decko Way:** Wherever possible, check for existing Decko mods created by the community or ways of utilizing the unique nested rules that Decko allows for to do things "the decko way" instead of overly complex approaches that use excessive non-Decko code to achieve a less maintainable result.
- **Make Reusable Decko Mods:** If a new kind of functionality is necessary, find a way to package it as a mod that is reusable and shareable with the Decko community.
- **Surface Navigational Scaffolding:** UI should make navigational scaffolding totally clear with visible system status changes as feedback for navigating through content menus.
  - Adopt lessons learned from Wikipedia's successful 2023 redesign research paper: https://www.mdpi.com/2227-9709/12/3/97
```
6.1. Theoretical Implications
Our findings connect directly to core HCI theories about how surfacing navigational scaffolding changes behavior in content-dense systems. The immediate and durable rise in in-site link traversal after launch is consistent with usability heuristics that emphasize visibility and user control: the scroll-persistent table of contents (TOC) and sticky header keep key actions perceptible at the moment of need, strengthening the information scent and reducing the way-finding effort. Framed by cognitive load theory, the TOC externalizes the page structure and lowers the extraneous load by offloading section memory, enabling users to navigate deeper within articles without additional search. Mechanistically, these elements shorten the decision time (Hick–Hyman) and pointing time (Fitts), which explains why internal navigation scales up even as the overall demand remains stable after a brief adjustment period. The transient rollout dip followed by normalization aligns with habit disruption/re-attunement accounts: expert users incur a short relearning cost, then reestablish efficient routines once the new scaffolding is routinized. Theoretically, large-scale redesigns that add persistent, low-friction navigational cues—rather than removing familiar structures—can shift behavior toward richer within-site exploration without depressing traffic, suggesting a general principle for reference platforms: prioritize persistent, context-coupled navigation that minimizes cognitive and motor costs while preserving expert workflows.

6.3. Implications for UI Design
To increase the paper’s practical impact, we conclude with design implications that translate our evidence into guidance for UI teams. First, strengthen in-site navigation by elevating low-friction, high-salience paths, e.g., persistent/collapsible tables of contents, sticky headers, and clearer on-page link affordances, and track the internal click-through and path diversity as leading indicators. Second, modernize without dismantling expertise: favor additive, progressively disclosed changes over removals; preserve learned workflows; and provide power–user shortcuts or opt-outs alongside novice-friendly defaults. Third, pair rollouts with disciplined measurement: stage deployments, enforce performance budgets, and predefine quasi-experimental evaluations (e.g., regression discontinuity around launch or stepped-wedge rollouts), segmented by device class and user tenure to detect short-term disorientation versus durable gains. For content-dense reference sites, prioritize readability (typographic scale, line length) and navigational scaffolding over purely esthetic revisions. Our openly replicable pipeline enables teams to adopt these practices and evaluate their own redesigns with comparable, policy-relevant metrics.

```

## Good UI Examples
- Decko
  - [Wikirate](https://wikirate.org/)
- Non-Decko
  - [Obsidian Docs](https://docs.obsidian.md/Home)

---

# UI LAYOUT

The page layout has a combination of standard Wiki and Docs navigation features. Decko renders `<header>`, `<article>`, `<aside>`, and `<footer>` elements controlled by the `*layout` rule card and overridable via `format :html do / layout :name` blocks.

## Top Navbox

### Logo
- Smaller icon (SingularityNET symbol) with logo text to its right at the same height.
- On mobile (below Bootstrap `md` breakpoint): icon stays, text is hidden via `d-none d-md-inline`.
- **Implementation:** Override the header brand view in `mod/hyperon_ui/set/all/` to render `<img>` icon + `<span class="d-none d-md-inline">` text.

### Menu Item Labels
Text changes to the `*navbox` card are editable directly in the wiki UI — no code needed:
- "Getting started" → "Start"
- "Recent Changes" → "Recent"

Sign-in/out/up labels come from `card-mod-layout`'s `account_link_text` method and are overridden in `mod/hyperon_ui/set/self/account_links.rb`:
- "Sign in" → "Login 🔑"
- "Sign out" → "Logout ⏻"
- "Sign up" → "Register"
- Username → "Account 👤" (until avatar is set; then shows avatar image)

### Search
- Default state: collapsed to a 🔎 icon button.
- Expands to full input on click/focus, or when a search string is already present.
- **Implementation:** Override the navbox search view in `hyperon_ui`; add a small JS expand/collapse toggle.

### Dark/Light Theme Toggle
- Button (☀️/🌙) in the navbox toggles Bootstrap's `data-bs-theme` attribute on `<html>`.
- Persisted in `localStorage` so it survives page loads.
- **Implementation:** CoffeeScript asset in `hyperon_ui` + `[data-bs-theme="dark"] { … }` overrides in `hyperon_ui.scss`. Button added to `*navbox` card content.
- Top navbox should have a solid background color based on the current light/dark theme.
- Page background should be dark for dark theme, light for light theme.

## Always Visible Navigation

Decko's layout renders `<header>` and `<aside>` as standard HTML elements. Making them sticky requires only CSS in `hyperon_ui.scss`:

```scss
header { position: sticky; top: 0; z-index: 1020; }

body.left-sidebar, body.right-sidebar, body.two-sidebar {
  aside { position: sticky; top: 4rem; height: calc(100vh - 4rem); overflow-y: auto; }
}
```

No JS, no new mod — Bootstrap's layout classes are already present on the body element.

## Wiki Layout (Two-Sidebar)

The current `*layout` uses Decko's left-sidebar layout (one `<aside>`). The target layout adds a right sidebar.

**Implementation:** Override `layout :default` in `mod/hyperon_ui/set/all/layouts.rb`:

```ruby
format :html do
  layout :default do
    body_tag "wiki-layout" do
      <<-HTML
        <header>#{nest :header, view: :core}</header>
        <aside id="sidebar-left">#{nest :sidebar, view: :core}</aside>
        <article>#{layout_nest}</article>
        <aside id="sidebar-right">#{render :page_sidebar}</aside>
        <footer>#{nest :footer, view: :core}</footer>
      HTML
    end
  end

  view :page_sidebar do
    [render(:local_graph), render(:breadcrumbs),
     render(:page_toc), render(:page_actions)].join
  end
end
```

CSS Grid in `hyperon_ui.scss` positions the four columns (left sidebar / article / right sidebar / footer spanning all).

## Left Sidebar — Wiki Nav Tree

The `mod/wiki_nav_tree/` mod is fully implemented. **Remaining step:** set `*sidebar` card content to:

```
{{_|view:wiki_nav_tree}}
```

This is a wiki UI edit — no code change.

### Nav Tree Behavior
- **Lazy loading:** Child pages load on demand via Decko's slotter when the ▸ expand button is clicked.
- **Active ancestor expansion:** `render_wiki_nav_row` will be extended to compare each nav card against the current page's ancestor chain (`card.name.to_name.part_names`) and pre-render matching ancestors inline (expanded) at page load.
- **Focus Mode:** A "Focus here" button sets `Env.session[:nav_root]` to the current card name, making it the tree root. "Clear focus" resets it. Addresses Ben's feedback about feeling "deep in a subsubsubmenu."
- **Hide system cards:** Cards that aren't content shouldn't be shown in the left sidebar nav tree or the table of contents right sidebar.
  - tag
  - approved by
  - approved at
  - expert approved by
  - expert approved at
  - table of contents
  - content
  - Tags
  - Discussion

### Nav Tree Styling
- Top-level items: solid box borders.
- Each nested level: 20% less opacity than the level above (implemented via SCSS `@for` loop or nested CSS custom property).
- Current file: `mod/wiki_nav_tree/assets/style/wiki_nav_tree.scss`

### Nav Tree Environment Variables
| Variable | Default | Meaning |
|---|---|---|
| `WIKI_NAV_ROOT` | (none) | If set, tree starts with that card's children |
| `WIKI_NAV_ROOT_LIMIT` | 150 | Max top-level cards when no root set |
| `WIKI_NAV_CHILD_LIMIT` | 250 | Max children per parent |

## Right Sidebar

The right sidebar renders a `view :page_sidebar` composed of four sub-views, top to bottom:

### 1. Local Graph (`mod/local_graph/`)
Shows how the current page connects to linked and hierarchically related pages.

- **View:** Renders `<div class="local-graph" data-links="[…]">` where `data-links` is JSON built from CQL queries: `links_to`, `linked_to_by`, left/right compound card relationships.
- **JS:** CoffeeScript asset initializes Cytoscape.js (or vis.js) inside the container div.
- **Packaged as:** `mod/local_graph/` — reusable for any Decko wiki.

### 2. Breadcrumbs
Hierarchy of parent pages leading to the current page.

- **Implementation:** `view :breadcrumbs` in `mod/hyperon_ui/set/all/` using `card.name.to_name.part_names` → Bootstrap `.breadcrumb` / `.breadcrumb-item` markup.
- No external dependency; pure Decko card name traversal.

### 3. Wiki Page Box — Actions
A box of page-level actions. Decko's built-in card menu already provides Edit, Move, and History — this box surfaces them alongside new wiki-specific actions:

| Action | Source | Notes |
|---|---|---|
| 📝 Edit | Decko built-in | Link to existing card edit action |
| 🔗 Links | Decko built-in | `links_to` / `linked_to_by` CQL views |
| Move | Decko built-in | Changes compound `+` name hierarchy |
| New / New Child | Decko built-in | Card create actions |
| Featured Image | Decko built-in | Image-type card association |
| ⭐ Star | New (`mod/wiki_actions/`) | `CardName+*stars` Pointer card; line-count = star total |
| 📌 Pin | New (`mod/wiki_actions/`) | `CardName+*pinned` Basic card; integer = priority order |
| 💬 Comments | `card-mod-comment` | Wire `{{+*discussion\|view:comment_box}}`; permissions via rule cards |

#### Star Storage
`CardName+*stars` — a Pointer card. Content is a newline-separated list of user card names. Star count = number of lines. Toggle via Decko event on update.

#### Pin Storage
`CardName+*pinned` — a Basic card. Content is an integer (sort priority among pinned pages). Absence = not pinned. Nav tree and search results check for this card when ordering results.

#### Comments
`card-mod-comment` is already installed (included in `card-mod-defaults`). To activate:
1. Nest `{{+*discussion|view:comment_box}}` in the page sidebar or footer view.
2. Configure role-based permissions via `*discussion+*create` and `*discussion+*read` rule cards in the wiki admin UI — no code change for permissions.

### 4. Page Contents (TOC)
A hierarchical link list of `h2`/`h3`/`h4` headings on the current page.

- **Implementation:** `view :page_toc` in `mod/hyperon_ui/set/all/` parses rendered content via Nokogiri (already available in Decko) and emits anchor links.
- Requires headings to carry `id` attributes (verify Decko's markdown renderer outputs these; add a post-processing step if not).

## Account Settings — User Avatar

No community mod exists for this; implemented natively via Decko's card architecture.

- **Storage:** Image-type card at `UserName+avatar` (carrierwave is already installed and handles upload/resizing).
- **Display:** Override `account_dropdown_label` in `mod/hyperon_ui/set/self/account_links.rb` to show `image_tag(avatar.image_url(:icon))` when the `+avatar` card exists; fall back to "Account 👤" otherwise.
- **Settings page:** Add `{{+avatar}}` to the `+account_settings` card content in the wiki UI — surfaces the upload field automatically.

---

# FEEDBACK

## Ben's Feedback (Early April 2026)

> "The basic organization of wiki.hyperon.dev looks fine to me, I mean the idea of a wiki is to be stripped down not fancy and it's all about the content...
>
> I wonder if there is a way to select the topic of interest and click to make it the TOP of the page for a while, so one is not trapped by the right margin of the page. I.e. if one's main interest at the moment is some topic T that is at the third level of indenting and its subtopics, then it would be good to be able to put T at the top (by the left margin) for a while rather than having the feeling one is deep in a subsubsubmenu all the time... HOWEVER this is a nice-to-have and not a blocker for being able to launch something...
>
> In general I am extremely eager to move this website and wiki to launch, and wondering if somehow we could/should have done all this more simply so we would have something on the web a while ago instead of still iterating, iterating, iterating, iterating...!"

**Response:** Ben's "focus on subtopic" request maps directly to the existing `WIKI_NAV_ROOT` env var in `wiki_nav_tree`. The Focus Mode feature (Phase 2) adds a session-based version of this so any user can set it per-session without admin access. Phase 1 items (sticky nav, wire nav tree) address the core navigability concern and have no blockers to shipping now.
