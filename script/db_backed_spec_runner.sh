#!/usr/bin/env bash
#
# db_backed_spec_runner.sh — run DB-backed Decko specs against a DISPOSABLE local
# Postgres, with an explicit bootstrap order.
#
# Ported into this repo (hyperon-wiki-phase5-go-live) from the sibling
# hyperon-wiki-local-prod-aligned worktree and retargeted at the Phase 5 /
# POLICY REV5 AtomSpace spec set. The bootstrap sequence and every safety guard
# are carried over unchanged; only the default spec list and the mod fed to
# `card:eat` differ.
#
# WHY THIS EXISTS. The MCP API request specs need a real Decko database. Getting
# one up is not obvious: a fresh schema has to be loaded from the installed
# `card` gem, migrated, seeded, and fed the mods' coded data in a specific order,
# and one unrelated initializer has to sit out the bootstrap. That sequence was
# previously rediscovered by trial and error and lived only in throwaway attempt
# scripts. It lives here now so the gate is reproducible rather than folklore.
#
# SAFETY POSTURE. This script does two destructive things — it `rm -rf`s a
# scratch directory and it DROPS AND RECREATES a database — and both targets are
# env-overridable. Every override is therefore checked against an allowlist-style
# guard before anything destructive runs:
#
#   - Scratch path must canonically resolve outside the repo, must not be a broad
#     root or $HOME, and must be named like a disposable spec worktree.
#   - DB container/name/user must all look explicitly disposable (a test/local
#     marker in the name), and the container must be a running LOCAL Docker
#     container. Remote/prod/dev-looking names are refused outright.
#   - The DB container is additionally refused if it is one of the LIVE local
#     stack containers, or if the target DB name is the live deck database
#     (`hyperon_production`). The prod-aligned local stack must never be touched.
#   - Local secret files (.env*, *.key, *.pem, credentials) are excluded from the
#     tree staged into the container.
#
# No production or dev hostnames, and no real credentials, appear in this file.
# The default password is a throwaway for a local disposable container.
#
# The WORKING TREE (including uncommitted changes) is copied to scratch and run
# from there, so the repo is never written to by the container and an in-progress
# patch can be tested before it is committed.
#
# CONFIGURATION. Everything is env-overridable; every default is local and
# disposable. The container image is the one dependency this script cannot
# provide for you — see DECKO_TEST_IMAGE below.
#
# USAGE. Invoke through bash. Tracked files under script/ in this repo are mode
# 644, so this file is deliberately NOT executable and is not run as ./script/...
#
#   bash script/db_backed_spec_runner.sh                  # the REV5 AtomSpace spec set
#   bash script/db_backed_spec_runner.sh spec/mcp_api/lib/atomspace_grants_spec.rb
#   bash script/db_backed_spec_runner.sh spec/x_spec.rb --example "some name"
#
#   SKIP_BOOTSTRAP=1 bash script/db_backed_spec_runner.sh ...  # reuse the existing DB
#
set -euo pipefail

die() { echo "refusing to run: $*" >&2; exit 2; }

# Canonicalize a path without requiring it to exist yet.
canonical() {
  local p="$1"
  if [ -d "$p" ]; then (cd "$p" && pwd)
  else
    local parent base
    parent="$(dirname "$p")"; base="$(basename "$p")"
    [ -d "$parent" ] || die "scratch parent directory does not exist: $parent"
    echo "$(cd "$parent" && pwd)/$base"
  fi
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The Decko/Rails runtime image. This is the one piece that is not repo-general:
# it must already contain the bundled gems for this app. Supply your own with
# DECKO_TEST_IMAGE if you do not have the local image this defaults to.
DECKO_TEST_IMAGE="${DECKO_TEST_IMAGE:-hyperon-local-backup-wiki}"

DECKO_TEST_NETWORK="${DECKO_TEST_NETWORK:-cp006c-decko-spec-net}"
DECKO_TEST_DB_CONTAINER="${DECKO_TEST_DB_CONTAINER:-cp006c-decko-spec-postgres}"
DECKO_TEST_DB_NAME="${DECKO_TEST_DB_NAME:-hyperon_test}"
DECKO_TEST_DB_USER="${DECKO_TEST_DB_USER:-hyperon_test}"
# Throwaway password for a local disposable container. Override for your own.
DECKO_TEST_DB_PASSWORD="${DECKO_TEST_DB_PASSWORD:-cp006c_test_password}"
DECKO_TEST_BUNDLE_VOL="${DECKO_TEST_BUNDLE_VOL:-cp006c-decko-spec-bundle}"
DECKO_TEST_BUNDLE_APP_VOL="${DECKO_TEST_BUNDLE_APP_VOL:-cp006c-decko-spec-bundle-app}"
# Mods whose coded data must be eaten before the specs run.
DECKO_TEST_EAT_MODS="${DECKO_TEST_EAT_MODS:-editorial_review}"
# Sibling of the repo rather than /tmp: Docker Desktop on Windows cannot bind
# mount a Git-Bash /tmp path, and this keeps the scratch copy outside the repo
# so it is never picked up by git or by a spec glob.
DECKO_TEST_SCRATCH="${DECKO_TEST_SCRATCH:-$(dirname "$REPO_ROOT")/.decko-spec-worktree}"

# POLICY REV5 / Phase 5 AtomSpace spec set: the grant matrix, the mint path, the
# sidecar read-client contract, and the L9 + card-scoped-quarantine controller.
DEFAULT_SPECS=(
  spec/mcp_api/lib/atomspace_grants_spec.rb
  spec/mcp_api/controllers/auth_controller_atomspace_scope_spec.rb
  spec/mcp_api/atomspace/sidecar_read_client_spec.rb
  spec/mcp_api/controllers/atomspace_mirror_controller_spec.rb
)
SPEC_ARGS=("$@")
[ ${#SPEC_ARGS[@]} -eq 0 ] && SPEC_ARGS=("${DEFAULT_SPECS[@]}")

# --- guard 1: scratch path must be disposable and outside the repo -----------
# This path is `rm -rf`d. Everything below is a refusal, never a correction.
[ -n "${DECKO_TEST_SCRATCH:-}" ] || die "DECKO_TEST_SCRATCH is empty"
SCRATCH_CANON="$(canonical "$DECKO_TEST_SCRATCH")"
REPO_CANON="$(canonical "$REPO_ROOT")"

case "$SCRATCH_CANON" in
  /|/c|/d|/e|/c/|/d/|/e/|[A-Za-z]:|[A-Za-z]:/|/root|/home|/Users|/usr|/var|/etc|/tmp)
    die "scratch path '$SCRATCH_CANON' is a broad root" ;;
esac
[ "$SCRATCH_CANON" != "$REPO_CANON" ] || die "scratch path is the repo itself"
[ "$SCRATCH_CANON" != "${HOME:-/nonexistent}" ] || die "scratch path is \$HOME"
case "$SCRATCH_CANON" in
  "$REPO_CANON"/*) die "scratch path '$SCRATCH_CANON' is inside the repo" ;;
esac
case "$REPO_CANON" in
  "$SCRATCH_CANON"/*) die "scratch path '$SCRATCH_CANON' is a parent of the repo" ;;
esac
# Must be positively identifiable as a disposable spec worktree, not merely
# "not obviously dangerous".
case "$(basename "$SCRATCH_CANON")" in
  *decko-spec*|*.decko-spec-worktree*) : ;;
  *) die "scratch basename must contain 'decko-spec' so it is clearly disposable: '$SCRATCH_CANON'" ;;
esac

# --- guard 2: DB target must be an explicitly disposable LOCAL container -----
# The database is DROPPED AND RECREATED on every run.
for pair in \
  "container:$DECKO_TEST_DB_CONTAINER" \
  "name:$DECKO_TEST_DB_NAME" \
  "user:$DECKO_TEST_DB_USER"
do
  label="${pair%%:*}"; value="${pair#*:}"
  case "$value" in
    *.amazonaws.com|*.rds.*|*prod*|*production*|*hyperon-dev*|*.compute.*|*.internal)
      die "DB $label '$value' looks remote or production" ;;
  esac
  # Positive disposability marker required, not just absence of a red flag.
  case "$value" in
    *decko-spec*|*cp006*|*test*|*local*|*scratch*) : ;;
    *) die "DB $label '$value' must contain a disposable marker (decko-spec/cp006/test/local/scratch)" ;;
  esac
done

# --- guard 3: never the LIVE prod-aligned local stack ------------------------
# The *local* markers accepted above ("local") would otherwise let the live
# hyperon-local-backup-* containers through. The live deck DB is a restored
# production dump: it is read-only territory for this script, always.
case "$DECKO_TEST_DB_CONTAINER" in
  *hyperon-local-backup*|*hyperon-local-mailpit*)
    die "DB container '$DECKO_TEST_DB_CONTAINER' is part of the LIVE local stack (restored prod dump)" ;;
esac
if [ "$DECKO_TEST_DB_NAME" = "hyperon_production" ]; then
  die "DB name 'hyperon_production' is the live deck database"
fi

if ! docker ps --filter "name=^/${DECKO_TEST_DB_CONTAINER}$" --format '{{.Names}}' | grep -q .; then
  die "DB container '${DECKO_TEST_DB_CONTAINER}' is not a running local Docker container.
  start it, or set DECKO_TEST_DB_CONTAINER to your own disposable Postgres."
fi

echo "WARNING: database '${DECKO_TEST_DB_NAME}' on container '${DECKO_TEST_DB_CONTAINER}' will be DROPPED and RECREATED."

# --- stage the working tree (uncommitted changes included) -------------------
# Deliberately a copy, not a bind mount of the repo: the container writes log/
# and tmp/, and the repo under test must not be mutated by a test run.
echo "staging working tree -> ${SCRATCH_CANON}"
rm -rf "$SCRATCH_CANON"
mkdir -p "$SCRATCH_CANON"
# Secret excludes: local credentials must never be copied into a container mount.
# These are all runtime/local-only files; none is needed to boot the app under
# RAILS_ENV=test, which reads its DB settings from the DB_* env vars passed below.
tar -C "$REPO_ROOT" \
    --exclude='./.git' --exclude='./log' --exclude='./tmp' \
    --exclude='./node_modules' --exclude='./files' \
    --exclude='./.env' --exclude='./.env.*' --exclude='*/.env' --exclude='*/.env.*' \
    --exclude='*.pem' --exclude='*.key' \
    --exclude='./config/master.key' --exclude='./config/credentials*.yml.enc' \
    --exclude='./config/credentials' \
    -cf - . | tar -xf - -C "$SCRATCH_CANON"

# Fail loudly rather than silently shipping a secret if an exclude ever regresses.
if find "$SCRATCH_CANON" \( -name '.env' -o -name '.env.*' -o -name '*.pem' \
     -o -name '*.key' -o -name 'credentials*.yml.enc' \) -print -quit | grep -q .; then
  die "a secret-looking file survived staging into '$SCRATCH_CANON'; aborting before docker run"
fi

# --- reset the disposable database ------------------------------------------
if [ "${SKIP_BOOTSTRAP:-0}" != "1" ]; then
  echo "resetting database ${DECKO_TEST_DB_NAME}"
  docker exec "$DECKO_TEST_DB_CONTAINER" bash -lc "
    set -euo pipefail
    export PGPASSWORD='${DECKO_TEST_DB_PASSWORD}'
    dropdb --if-exists -h 127.0.0.1 -U '${DECKO_TEST_DB_USER}' '${DECKO_TEST_DB_NAME}'
    createdb -h 127.0.0.1 -U '${DECKO_TEST_DB_USER}' '${DECKO_TEST_DB_NAME}'
  "
fi

# --- bootstrap + run ---------------------------------------------------------
# Bootstrap order matters and is the whole point of this script:
#   1. bundle sanity (+ `bundle pristine card`, since the gem's db/schema.rb is
#      read straight out of the installed gem below)
#   2. load the card gem's schema into the empty DB
#   3. rake db:migrate
#   4. rake card:seed                       (core cards)
#   5. rake card:eat -- -m <mod> -p real    (each mod's coded data)
#   6. rspec
#
# config/initializers/cardtype_button_fix.rb is moved aside for steps 4-5 only.
# It references a Cardtype HTML-format constant that does not exist until after
# the core seed has run, so with a fresh schema it aborts the bootstrap. It is
# restored (via trap, so also on failure) before any spec runs.
docker run --rm --network "$DECKO_TEST_NETWORK" \
  -v "$SCRATCH_CANON:/app" \
  -v "$DECKO_TEST_BUNDLE_VOL:/bundle" -v "$DECKO_TEST_BUNDLE_APP_VOL:/bundle_app" \
  -w /app \
  -e BUNDLE_PATH=/bundle -e BUNDLE_APP_CONFIG=/bundle_app \
  -e BUNDLE_FROZEN=true -e BUNDLE_SILENCE_ROOT_WARNING=1 \
  -e RAILS_ENV=test \
  -e DB_HOST="$DECKO_TEST_DB_CONTAINER" \
  -e DB_USERNAME="$DECKO_TEST_DB_USER" \
  -e DATABASE_PASSWORD="$DECKO_TEST_DB_PASSWORD" \
  -e DECK_ORIGIN=http://localhost:3000 \
  -e SKIP_BOOTSTRAP="${SKIP_BOOTSTRAP:-0}" \
  -e DECKO_TEST_EAT_MODS="$DECKO_TEST_EAT_MODS" \
  "$DECKO_TEST_IMAGE" bash -lc '
    set -euo pipefail
    ruby -v
    bundle check
    bundle pristine card >/dev/null

    if [ "${SKIP_BOOTSTRAP:-0}" != "1" ]; then
      INIT="config/initializers/cardtype_button_fix.rb"
      DISABLED="${INIT}.bootstrap-disabled"
      restore_init() { [ -f "$DISABLED" ] && mv -f "$DISABLED" "$INIT" || true; }
      trap restore_init EXIT
      mv "$INIT" "$DISABLED"

      bundle exec ruby - <<"RUBY"
require "active_record"
require "erb"
require "yaml"
env = ENV.fetch("RAILS_ENV", "test")
config = YAML.safe_load(ERB.new(File.read("config/database.yml")).result, aliases: true).fetch(env)
ActiveRecord::Base.establish_connection(config)
schema = File.join(Gem::Specification.find_by_name("card").full_gem_path, "db", "schema.rb")
puts "loading_card_schema=#{schema}"
load schema
puts "tables_after_schema=#{ActiveRecord::Base.connection.tables.size}"
RUBY

      bundle exec rake db:migrate
      bundle exec rake card:seed
      for mod in ${DECKO_TEST_EAT_MODS}; do
        bundle exec rake card:eat -- -m "$mod" -p real
      done
      restore_init
      trap - EXIT
      echo "bootstrap_complete=true"
    fi

    bundle exec rspec "$@" --format documentation
  ' _ "${SPEC_ARGS[@]}"
