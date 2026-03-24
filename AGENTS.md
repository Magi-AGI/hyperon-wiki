# Repository Guidelines

## Project Structure & Module Organization
- Magi Archive is a Decko (Rails) deck. Core config in `config/` (mail, caching, storage in `config/application.rb`; DB per environment in `config/database.yml`).
- Custom features live in `mod/<feature>/` (Ruby sets in `mod/<feature>/set/`, assets in `mod/<feature>/assets/`, Rake tasks in `mod/<feature>/lib/tasks/`).
- Generated uploads sync to `files/` — treat as build output; never edit directly.
- Tests in `spec/`; browser harness utilities in `spec/javascripts/support/`.
- Use provided wrappers in `script/` (`script/decko`, `script/card`, `script/decko_rspec`) instead of direct Rails binaries.

## Build, Test, and Development Commands
- `bundle install` — install/update gems after `Gemfile` changes.
- `bundle exec decko server` — start dev server (http://localhost:3000).
- `bundle exec decko update` — apply schema/card migrations and sync `files/` after mod or migration changes.
- `bundle exec decko console` — Rails console in deck context.
- `script/card create "Card Name"` — scaffold a card.
- `bundle exec thin start -R config.ru` — production-like smoke test.
- Tests: `bundle exec rspec` or `script/decko_rspec`.
- Remote runner (Decko host): `cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && export PATH=/home/ubuntu/.rbenv/shims:/home/ubuntu/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && script/card runner ...` (avoids PATH/env issues when calling via SSH).

## Coding Style & Naming Conventions
- Ruby: idiomatic, 2-space indentation, trailing newline, snake_case filenames (e.g., `mod/agents/set/self.rb`).
- Constants CamelCase; card titles Title Case.
- Prefer sets/helpers over ERB for non-trivial logic.
- JavaScript: ES6 modules; camelCase functions; PascalCase components.

## Testing Guidelines
- RSpec is primary. Mirror mods/services in `spec/` (e.g., `spec/mod/search_spec.rb`).
- Use explicit `describe Card["Name"]` for card behavior.
- Browser interactions in `spec/javascripts/` with shared utils from `spec/javascripts/support/`.
- SimpleCov is set via `.simplecov`; review `coverage/` and address meaningful gaps before merging.

## Commit & Pull Request Guidelines
- Commits: short, imperative subjects (e.g., "Add deck import job"); optional context body; reference issues (e.g., `Refs #123`).
- PRs: summarize intent, list commands used to test, include screenshots/GIFs for UI changes, call out schema/migration changes, link supporting docs (e.g., `DECKO-DATABASE-ACCESS.md`), and note any manual deployment steps.

## Security & Configuration Tips
- Keep secrets out of the repo; use env vars or `.env.local`.
- Coordinate with ops when changing mail/storage in `config/application.rb`; validate target services and document required credentials in the PR.
- Ensure exports/backups remain ignored (e.g., `backup-*.sql`).
