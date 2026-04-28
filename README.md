# Hyperon Wiki — Developer Guide

A Decko-based wiki for the Hyperon/Atomspace ecosystem. Built on top of [Decko](https://decko.org) (a Rails-based wiki engine where "everything is a card").

---

# SETUP & RUNNING

## Prerequisites

- Ruby 3.x (`rbenv` or `rvm` recommended)
- MySQL 8.x (or MariaDB 10.x)
- Node.js (for asset compilation)
- Bundler

## Local Installation

```bash
git clone https://github.com/Magi-AGI/hyperon-wiki.git
cd hyperon-wiki
bundle install
```

Copy the example environment file and fill in your database credentials:

```bash
cp .env.example .env       # or set vars in config/application.yml if using Figaro
```

Set up the database (choose one):

```bash
# Fresh install from seed (empty wiki with default cards)
bundle exec rake db:create db:migrate
bundle exec decko seed

# Restore from a production backup .sql.gz
zcat backup.sql.gz | mysql -u root -p hyperon_development
bundle exec rake db:migrate    # apply any pending migrations
```

Install mod assets (required after `bundle install` or adding a new mod):

```bash
bundle exec rake card:mod:install
bundle exec rake card:assets:wipe
bundle exec rake card:assets:refresh
```

## Running Locally

```bash
bundle exec thin start        # default: http://localhost:3000
```

After changing **Ruby** code (mods, set files):

```bash
kill -HUP $(cat tmp/pids/thin.pid)   # hot reload without full restart
```

After changing **SCSS or CoffeeScript** assets:

```bash
bundle exec rake card:assets:wipe
bundle exec rake card:assets:refresh
# Then hard-refresh the browser (Ctrl+Shift+R)
```

## Running Tests

```bash
bundle exec rspec spec/mod/       # structural specs — no database needed, ~70ms
RAILS_ENV=test bundle exec rspec spec/views/   # rendering specs — needs test deck
```

---

# DEPLOYMENT

## Environments

| Environment | URL | Branch | Server |
|---|---|---|---|
| Production | https://wiki.hyperon.dev | `main` | Thin (Decko) |

## Deploying to Production

SSH into the production server, then:

```bash
cd /path/to/hyperon-wiki
git pull origin main
bundle install --without development test
bundle exec rake db:migrate          # run if any new migrations
bundle exec rake card:assets:wipe
bundle exec rake card:assets:refresh
kill -HUP $(cat tmp/pids/thin.pid)  # reload Ruby code
```

If the process has fully stopped (not just stale), restart with:

```bash
bundle exec thin start -d -e production --pid tmp/pids/thin.pid \
  --log log/thin.log --port 3000
```

## Database Cards vs. Code

This project has two layers that must stay in sync:

| Layer | Where it lives | How to deploy |
|---|---|---|
| Ruby code (mods, views, SCSS, JS) | Git repo | `git pull` + server reload |
| Card content (`*header`, `*sidebar`, layouts) | MySQL database | Edit via wiki admin UI or MCP tools |

When both change at once (e.g. a new layout card + new Ruby view), deploy code **before** editing cards, so the new view exists when the card content references it.

## Data Migrations

Decko uses ActiveRecord migrations for schema changes:

```bash
bundle exec rails generate migration AddFooToCards foo:string
bundle exec rake db:migrate
```

Card content changes (the "soft" data layer) are done via:
- **Wiki admin UI:** `/admin` → edit any card directly
- **MCP tools:** `mcp__hyperon-wiki__update_card` etc. (see MCP server config)
- **Runner scripts:** `bundle exec decko runner path/to/script.rb` for bulk card updates

Example runner script pattern (see `/tmp/update_header_and_sidebar.rb` for reference):

```ruby
Card::Auth.as_bot do
  c = Card.fetch("*header")
  c.update!(content: "<nav>...</nav>")
end
```

---

# CI / CONTINUOUS INTEGRATION

## GitHub Actions

The structural spec suite (Track 1) runs on every push — no database needed:

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  specs:
    name: Structural specs
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true

      - name: Run mod specs
        run: bundle exec rspec spec/mod/ --format progress
```

Create this file at `.github/workflows/ci.yml` to enable it. The structural specs are self-contained (no Rails boot, no database) and run in under 100ms, making them well-suited for CI.

For full rendering specs (Track 2) a MySQL service container is needed — add when the `spec/views/` suite is populated:

```yaml
    services:
      mysql:
        image: mysql:8.0
        env:
          MYSQL_ROOT_PASSWORD: root
          MYSQL_DATABASE: decko_test
        ports: ['3306:3306']
        options: --health-cmd="mysqladmin ping" --health-interval=10s --health-timeout=5s --health-retries=3
    env:
      DATABASE_URL: mysql2://root:root@127.0.0.1/decko_test
```

---

# ADDING OR MODIFYING MODS

## Mod Structure

```
mod/
  my_mod/
    mod.rb                        # registers the mod
    set/
      all/my_feature.rb           # view overrides applied to all cards
      type/rich_text/my_view.rb   # view overrides applied to one type
    assets/
      script/my_feature.js.coffee
      style/my_feature.scss
spec/mod/my_mod_spec.rb           # structural spec
```

## Adding a New Mod

```bash
bundle exec decko new_mod mod/my_mod
# Edit mod/my_mod/mod.rb to set name/description
bundle exec rake card:mod:install  # register with Decko
bundle exec rake card:assets:wipe
bundle exec rake card:assets:refresh
```

## Overriding a View

```ruby
# mod/my_mod/set/all/my_feature.rb
format :html do
  view :my_view, cache: :never do
    wrap_with :div, class: "my-class" do
      "Hello #{card.name}"
    end
  end
end
```

## Key Decko API Gotchas

| Pitfall | Fix |
|---|---|
| `Card.search({trash: false})` — WQL rejects `trash:` | Use `Card.where(trash: false)` (ActiveRecord) instead; WQL excludes trash by default |
| `link_to(text, url, opts)` — 3-arg form is not standard | Use `link_to(text, href: url, class: "…")` (2-arg, keyword opts) |
| `{{_main\|viewA}}` and `{{_main\|viewB}}` in one layout | `_main` is deduplicated; second reference returns cached first render. Use client-side JS for the second slot |
| Decko strips `id` attributes from card content | Put `id`-bearing elements in LayoutType cards (raw HTML allowed), not in `*sidebar` etc. |
| New SCSS/JS assets don't appear after edit | Run `card:assets:wipe` + `card:assets:refresh` |
| Ruby view changes don't take effect | Send `kill -HUP` to the Thin PID to trigger hot reload |

---

# PROGRESS

## DONE
- TinyMCE fullscreen button enabled (`mod/hyperon_ui/assets/script/tinymce_fullscreen.js.coffee`)
- Decko modal made full screen (`mod/hyperon_ui/set/all/edit_modal.rb` + `hyperon_ui.scss`)
- `wiki_nav_tree` mod implemented (`mod/wiki_nav_tree/`) — lazy-loads child pages via slotter, respects read permissions, filters system/metadata cards via `NAV_BLOCKED_RIGHTS`
- **Two-sidebar CSS Grid layout** (`body.wiki-layout`) — left sidebar, article, right sidebar, sticky header
- **Dark/light theme toggle** — `theme_toggle.js.coffee`; persists in `localStorage`; syncs `data-bs-theme` on `<html>` and navbar
- **Solid theme-aware navbar** — `--bs-secondary-bg` (dark: `#343a40`, light: `#e9ecef`) via `.wiki-header-nav` CSS override
- **Logo size constrained** — `max-height: 30px` via `.nav-logo img` CSS
- **Left sidebar nav tree wired** — `*sidebar` card set to `{{_|view:wiki_nav_tree}}`
- **Nav tree: section cards only** — top-level shows only content cards with compound children; all others in "Other (N)" lazy group
- **Nav tree: system cards hidden** — `NAV_BLOCKED_RIGHTS` excludes `tag`, `tags`, `content`, `discussion`, `approved by/at`, `expert approved by/at`, `table of contents`
- **Nav tree: active ancestor expansion** — current page's ancestor path is pre-expanded on load; current item highlighted with blue accent + `fw-semibold`
- **Nav tree: descending-opacity item backgrounds** — root items `--bs-secondary-bg`, children `--bs-tertiary-bg`
- **Nav tree: Focus Mode** — `?nav_root=CardName` URL param focuses tree; `⊙` icon per item to set; banner with `✕ clear` resets
- **Left sidebar breadcrumb** — `#sidebar-breadcrumb` populated by `page_sidebar.js.coffee` for compound-name pages; hidden when empty
- **Right sidebar TOC** — client-side JS builds `h2/h3/h4` anchor list; empty `<aside id="sidebar-right">` in layout populated by JS

## IN PROGRESS
- Production server needs `git pull origin main` + restart to pick up Ruby fixes (nav tree rewrite). All code is committed; layout cards already updated via MCP.

## PLANNED — Phased Implementation

See full design spec in [UI LAYOUT](#ui-layout) below.

### Phase 1 — Zero/Minimal Code (Config + CSS only)

- [x] **Wire wiki_nav_tree into left sidebar** — `*sidebar` card content set
- [x] **Sticky navbar + sticky sidebars** — CSS Grid layout in `hyperon_ui.scss`
- [ ] **Rename navbox menu items** — Edit `*navbox` card: "Getting started" → "Start", "Recent Changes" → "Recent"
- [ ] **Override Sign in/out/up labels** — Add `mod/hyperon_ui/set/self/account_links.rb`

### Phase 2 — View Overrides in `hyperon_ui` mod (Small Code)

- [x] **Two-sidebar layout** — CSS Grid in `hyperon_ui.scss`; layout card updated
- [x] **Breadcrumbs view** — Client-side in `page_sidebar.js.coffee`
- [x] **Page TOC view** — Client-side in `page_sidebar.js.coffee`
- [x] **Dark/light theme toggle** — `theme_toggle.js.coffee`
- [x] **Focus Mode** — URL param `?nav_root=CardName` in `wiki_nav_tree.rb`
- [x] **Active ancestor expansion in nav tree** — `nav_ancestor_of_current?` pre-expands on load
- [x] **Logo size** — Constrained via CSS
- [ ] **Logo: icon + text, responsive hide** — Override header brand view; `<img>` icon + `<span class="d-none d-md-inline">` text
- [ ] **Collapsible search field** — Override navbox search view; JS expand/collapse toggle

### Phase 3 — New Features via Existing Mods (Moderate Code)

- [ ] **Comments via `card-mod-comment`** — Nest `{{+*discussion|view:comment_box}}`; configure role permissions via rule cards
- [ ] **User avatars** — `UserName+avatar` Image card; override `account_dropdown_label`

### Phase 4 — New Mods (Higher Effort)

- [ ] **Star/Pin actions (`mod/wiki_actions/`)** — `CardName+*stars` Pointer card; `CardName+*pinned` Basic card
- [ ] **Local graph (`mod/local_graph/`)** — Cytoscape.js/vis.js initialized from CQL link data

---

# TESTING

## Track 1 — Structural / Behavioral Specs (RSpec, no database)

**What they verify:** View definitions, permission guards, slotter wiring, SCSS class presence. ~70ms, no Rails boot.

```bash
bundle exec rspec spec/mod/
```

**Convention:** Every mod with `view :` blocks gets a companion spec in `spec/mod/<mod_name>_spec.rb`.

## Track 2 — View Rendering Specs (RSpec + Capybara, requires test deck)

```bash
RAILS_ENV=test bundle exec rspec spec/views/
```

**When to write:** Add for each new `view :` block that produces non-trivial HTML.

## Track 3 — Cypress End-to-End Specs (requires running server)

```bash
bundle exec thin start         # in one terminal
bundle exec cypress run        # in another
```

Covers JS behaviors: dark mode persistence, focus mode, slotter lazy-load, collapsible search.

## Track 4 — Manual Visual Checklist (per-phase)

### Phase 1 checklist
- [x] Header stays pinned at top when scrolling a long page
- [x] Left sidebar stays pinned and scrolls independently from the article
- [x] Nav tree appears in left sidebar
- [ ] Navbox shows "Login 🔑", "Logout ⏻", "Register", "Account 👤"
- [ ] "Start" and "Recent" appear in place of old labels

### Phase 2 checklist
- [x] Right sidebar appears and stays pinned during article scroll
- [x] Breadcrumbs show correct parent chain for a nested page
- [x] TOC shows all h2/h3/h4 headings; anchor links jump to correct sections
- [x] Dark mode toggle switches theme; preference survives a page reload
- [x] Nav tree auto-expands ancestors of the current page on load
- [x] Focus Mode button narrows the nav tree to the current card's subtree
- [ ] Logo icon stays visible on narrow viewport; text hides below `md` breakpoint
- [ ] Search collapses to 🔎 icon by default; expands on click

### Phase 3 checklist
- [ ] Comment box appears; anonymous and signed-in comments render correctly
- [ ] Avatar upload field visible in account settings; avatar shown in navbar dropdown

### Phase 4 checklist
- [ ] Star button toggles; count increments/decrements correctly
- [ ] Pin badge visible in nav tree for pinned cards
- [ ] Local graph renders for a card with multiple links; nodes are clickable

| Track | Tool | DB needed | Covers |
|---|---|---|---|
| 1 — Structural | `bundle exec rspec spec/mod/` | No | View defined, guards present, SCSS classes |
| 2 — Rendering | `bundle exec rspec spec/views/` | Yes (test deck) | HTML structure, card query output |
| 3 — Cypress | `bundle exec cypress run` | Yes (dev server) | JS toggle/session behaviors |
| 4 — Visual | Browser + checklist | Yes (dev server) | CSS layout, responsive breakpoints |

---

# DECKO

## Design Methodology

- **The Decko Way:** Use Decko's card rules and existing mods before writing new code. Rule cards (`*sidebar`, `*header`, `*layout`) configure behavior without touching Ruby.
- **Make Reusable Mods:** Package new functionality as a mod that is reusable and shareable with the Decko community.
- **Surface Navigational Scaffolding:** UI should make navigation totally clear — sticky TOC, persistent breadcrumbs, visible current-location highlight. See [Wikipedia 2023 redesign research](https://www.mdpi.com/2227-9709/12/3/97).

## Good UI Examples
- Decko: [Wikirate](https://wikirate.org/)
- Non-Decko: [Obsidian Docs](https://docs.obsidian.md/Home)

---

# UI LAYOUT

## Top Navbox

### Logo
- Constrained to `max-height: 30px` via `.nav-logo img` CSS.
- **Planned:** icon + text layout; text hides below `md` breakpoint via `d-none d-md-inline`.

### Dark/Light Theme Toggle
- Button (☀️/🌙) toggles Bootstrap's `data-bs-theme` on `<html>` and `.wiki-header-nav`.
- Persisted in `localStorage`.
- Navbar uses `--bs-secondary-bg` for a solid, theme-aware background.

## Left Sidebar — Wiki Nav Tree

Implemented in `mod/wiki_nav_tree/`. Content sections with compound children are top-level items; leaf cards go in a lazy "Other (N)" group. Focus Mode via `?nav_root=CardName`.

### Nav Tree Environment Variables
| Variable | Default | Meaning |
|---|---|---|
| `WIKI_NAV_ROOT` | (none) | If set, tree starts with that card's children |
| `WIKI_NAV_CHILD_LIMIT` | 250 | Max children per parent |

## Right Sidebar

Populated client-side by `page_sidebar.js.coffee`. Renders breadcrumbs and a TOC from `h2/h3/h4` headings in the article. The layout places an empty `<aside id="sidebar-right">` which JS fills after load.

**Planned:** Local graph (`mod/local_graph/`), star/pin actions (`mod/wiki_actions/`), comment box.

---

# FEEDBACK

## Ben's Feedback (Early April 2026)

> "I wonder if there is a way to select the topic of interest and click to make it the TOP of the page for a while, so one is not trapped by the right margin of the page..."

**Status:** Implemented as Focus Mode — the `⊙` icon next to each nav item sets `?nav_root=CardName`, making that card the tree root. `✕ clear` resets.
