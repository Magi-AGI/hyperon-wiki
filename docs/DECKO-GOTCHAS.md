# Decko Gotchas

**Hard-won rules, collected from this repository's source comments and documentation.**

Every entry here cost someone time. None is generic Rails advice — each is a Decko-specific
behaviour that surprised a contributor working on *this* deck, recorded where it was found.

> **Status:** current, drawn from source comments in `mod/`, from
> [`../README.md`](../README.md), and from documented investigations. Where a comment records
> the date it was verified, that date is carried through; Decko changes, so a rule from 2026
> is a strong prior rather than a guarantee.

**Read the source comments too.** This page collects what generalizes; the files carry more
context for the specific thing they guard.

---

## Naming and card identity

**Name keys fold more than you expect.** Case, space against hyphen, and singular against
plural all fold together. Two names that look different can resolve to the same card.

**A case-only rename is a no-op.** The two names share a key, so nothing happens. Renaming
across case needs a two-step through a distinct intermediate key.

**A rename can silently collide.** Because of plural folding, renaming a compound card's part
can land on an existing card rather than creating a new one. **Ask before renaming a compound
card if you are not certain.**

**Compound cards store `name` and `key` as NULL.** They are computed from the left and right
card ids. Raw SQL using `name ILIKE`, and some query counts, therefore return false negatives
on compound cards. Fetch by name, query by `left_id`, or list children instead.

---

## Set files and loading

**A relative `require` inside a set file silently drops the whole set.** Set files have no
stable `__FILE__`; the require raises and the events in that file never register — with no
error you will notice. Both the proposal and merge-draft set files carry this warning
explicitly.

**Set constants shadow top-level constants.** Inside a set, `File` resolves to
`Card::Set::All::File`, not Ruby's `File`. Qualify every top-level constant you use.

**Decko does not auto-load a deck-local mod's Ruby.** A `lib/card/mod/<name>.rb` entry plus a
`Rails::Engine` are never loaded at boot. Deck-local mods in this deck are wired by explicit
requires in the deck configuration.

**Decko does not auto-load a mod's `config/initializers/*.rb` either** — verified on dev for
both routes and the read-client binding. A mod initializer that looks like it will run on
boot does not.

**`decko update` does not run a mod's `db/migrate`.** Its schema-migration step ignores
ActiveRecord's migration path, which is why one mod's migration never ran. Wire the migration
path explicitly and run `rake db:migrate`.

**Singular table names need `self.table_name`.** Rails pluralizes by default, so a model over
a singular table silently looks in the wrong place.

---

## Queries and search

**`Card.search({trash: false})` is rejected** — CQL has no `trash:` term. Use
`Card.where(trash: false)` through ActiveRecord; CQL excludes trash by default anyway.

**CQL's date handling is narrower than it looks, and the MCP query endpoint works around
it.** Raw CQL honours only the keyword operators `gt` and `lt`, and only with a **string**
date value. Passing `[">=", date]` is parsed as an IN-list rather than a comparison, and
passing a `Time` object is rejected outright as an invalid value type.

The MCP `run_query` endpoint translates around this: `>`, `>=`, and `gt` all fold to `gt`;
`<`, `<=`, and `lt` fold to `lt`; `between` becomes an internal `and` of a lower and an upper
bound; and the date is normalized to a UTC timestamp string. **So date filtering works
through that endpoint** — but read the next paragraph before trusting a boundary date.

**`>=` and `<=` are not inclusive, and the asymmetry bites.** CQL has no inclusive operator,
so both fold to a strict comparison against the normalized timestamp, and a bare date
normalizes to **midnight**. `<= "2026-09-15"` therefore becomes `< "2026-09-15 00:00:00"` and
**excludes the whole of September 15**, which is almost never what the caller meant. `>=` is
the gentler case — `> "2026-09-15 00:00:00"` includes the rest of that day but drops anything
stamped exactly at midnight. If you need a boundary day included, ask for the day after it,
or use `between` with bounds you have chosen deliberately.

If you are writing raw CQL rather than going through the endpoint, none of this translation
applies — build `gt`/`lt` with string values yourself.

**The MCP query endpoint fails closed on unrecognized filters.** It accepts exactly five
filter keys: `name`, `type`, `content`, `updated_at`, and `created_at`. Anything else is
dropped, and if nothing recognized survives, the query is rejected with a validation error
naming those five. Raw CQL strings such as `name ~ 'x'` are refused rather than
reinterpreted.

Two shape constraints on those keys: `type` is an exact match only, while `name` and
`content` are match operations — a bare string is wrapped as `["match", value]` for you.
**`and` is not something you pass in**; the controller generates it internally when
expanding a `between` date range.

*Historical, and the reason that guard exists:* without it the query degraded to
`Card.search(limit/offset)` and silently returned **every** card. That failure mode is closed
on this endpoint, but it is a useful shape to recognize — a query that returns far more than
expected is worth suspecting before it is trusted.

**Ripgrep and other ignore-aware tools honour `.gitignore`.** `scripts/archive/` is ignored,
so a scan of that path can return a near-empty result and look like a clean pass while
reading almost nothing. Use `grep -r`, `rg --no-ignore`, or a filesystem walk when scanning
ignored paths.

---

## Views, layouts, and rendering

**`{{_main|viewA}}` and `{{_main|viewB}}` in one layout deduplicate.** The second reference
returns the cached first render. Use client-side JS for the second slot.

**`link_to(text, url, opts)` is not the supported form.** Use
`link_to(text, href: url, class: "…")` — two arguments, keyword options.

**Decko does not fall back to the home view** when breadcrumbs and the table of contents are
involved; the `hyperon_ui` layout handles that case explicitly.

**Bundle-member CSS cards are SASS-compiled.** `hsl(var(--x))` raises a `Card::Error` on
create or update. Use literal `hsl()` values.

**The markdown formatter strips `<word…>` spans from the Markdown source** silently, which is
what `markdown_fixes` exists to correct.

---

## Events and the save pipeline

**Do not nest `Card#save!` of an existing card mid-act.** This was a Phase 6 lesson in the
merge editor: compute the result and write it as part of the surrounding act, or use a
dedicated `:integrate` step that runs only on the real path.

**Watch for shared simple-card subcards colliding.** A `+applied`-style subcard name shared
across parents collides in ways that are not obvious until two cards use it.

**Permission propagation has a known gap.** When a `+*read` rule is created or updated
directly on a card, a finalize hook repairs the cached read-permission state on that card and
all its descendants. The `*right`-rule case is marked **TODO** in the mod's own source — do
not assume its behaviour without checking the current code. Changing a `*read` rule on a card
with descendants can change visibility for all of them; verify the rendered result for the
audience you intend.

---

## Roles and permissions

**Roles resolve from the role card, not the user card.** `<Role>+*members` is the source of
truth. Saving it updates Decko's cached role hash automatically.

**Creating a `<User>+*roles` card grants nothing.** Decko computes it as a virtual card
reflecting membership — it is a view, not an input. Reading it is a fair way to check what
someone has; writing one is not a way to give it to them.

**Administrator membership is tracked separately** and is not reliably visible through
`<User>+*roles`. Check `Administrator+*members` directly when that is the role in question.

**A narrower rule always wins.** A permission surprise is usually a rule on a more specific
card than the one you are looking at. Check the card's own rules before checking the person's
roles.

**The seed file is not the running site.** `mod/editorial_review/data/real.yml` and
production have diverged on `Draft` read visibility and on `RawData` read scope. Re-read the
live rule cards for any access decision — see
[`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §4.

---

## Agents and the MCP surface

**An "already exists" error on create can be spurious.** Check with a read before acting on
it — the server can return it after a successful create.

**Read your writes.** Every write gets a follow-up read of the same card before it is treated
as done. Trusting the API response is how silent failures survive.

**One writer at a time.** When several sessions are active on the same wiki, the orchestrating
session performs the writes; advisory sessions do not write wiki state. Sequential calls, not
parallel batches.

**Backslashes can be eaten in inserted content.** Find-and-replace and append paths have
collapsed `\\` to `\` in embedded JavaScript, breaking regex character classes and killing
the whole script with a syntax error. Avoid literal double backslashes in inserted code, and
syntax-check rendered scripts.

---

## File uploads

**A Decko 0.19.1 bug** caused the `assign_attachment_on_create` event not to run in the
expected context, patched in this deck via a Rails initializer. The investigation is in
[`archive/DECKO-FILE-UPLOAD-BUG.md`](archive/DECKO-FILE-UPLOAD-BUG.md) and is marked
resolved — but **the fix may still be load-bearing.** Confirm the initializer is present
before assuming uploads work without it, and test an actual browser upload rather than
relying on the record. A Decko upgrade could reintroduce the underlying condition.

---

## Where to go next

| Question | Document |
|---|---|
| How is the system put together? | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
| Setup, tests, adding a mod, overriding a view | [`../README.md`](../README.md) |
| What is a card, and what metadata does it carry? | [`CONTENT-MODEL.md`](CONTENT-MODEL.md) |
| Who can do what? | [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) |
| Conventions for agents working in this repository | [`../CLAUDE.md`](../CLAUDE.md) |

Found a new one? Add it here with enough context that the next person understands *why*,
not just *what*.
