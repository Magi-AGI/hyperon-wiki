#!/bin/bash
# Offline verifier for the sync wrappers' remote-command construction.
#
# Makes no network connection and needs no credentials. `ssh` and `scp` are
# replaced by shims: one records argv, one executes the remote command locally
# inside a sandbox HOME so tilde expansion and `ln` behaviour are real.
#
# Usage:
#   bash scripts/tests/verify_ssh_quoting.sh
#
# Pins three defects found in review:
#   1. `SSH_CMD="ssh -T -i $SSH_KEY $SSH_TARGET"` invoked unquoted as
#      `$SSH_CMD ...` split a key path containing a space into two arguments.
#   2. `basename $EXPORT_DIR` unquoted produced a wrong basename when the
#      repository path contained a space.
#   3. `ln -sfn '~/exports/dir'` quoted the leading tilde, so the remote shell
#      did not expand it and the `latest` symlink dangled at a literal
#      "~/..." target. The ingesters then found no default directory.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CAPTURE="$WORK/argv.txt"
mkdir -p "$WORK/bin"

# Recording shims: dump argv, do nothing else.
for tool in ssh scp; do
  cat > "$WORK/bin/$tool" <<SHIM
#!/bin/bash
{
  echo "--- $tool"
  for a in "\$@"; do echo "ARG:\$a"; done
} >> "$CAPTURE"
exit 0
SHIM
  chmod +x "$WORK/bin/$tool"
done

# Executing shim: run the remote command for real, in the sandbox HOME.
# The last argument is the remote command string, exactly as ssh would treat it.
cat > "$WORK/bin/ssh_exec" <<'SHIM'
#!/bin/bash
cmd="${@: -1}"
cd "$HOME" || { echo "ssh_exec: no HOME at $HOME" >&2; exit 1; }
bash -c "$cmd" || { echo "ssh_exec: remote command failed: $cmd" >&2; exit 1; }
SHIM
chmod +x "$WORK/bin/ssh_exec"

export PATH="$WORK/bin:$PATH"

# Deliberately awkward values: spaces in the key path and the deck root.
export HYPERON_WIKI_HOST="wiki.example.invalid"
export HYPERON_WIKI_SSH_KEY="$WORK/my keys/wiki key.pem"
export HYPERON_WIKI_SSH_USER="operator"
export HYPERON_WIKI_REMOTE_DIR="~/deck root/hyperon-wiki"
mkdir -p "$WORK/my keys"
: > "$WORK/my keys/wiki key.pem"

# sync_transcripts.sh refuses to run without this, because a real run writes to
# the live wiki. The checks below only evaluate its connection-setup and symlink
# blocks against fake ssh/scp shims - nothing is contacted - so the opt-in is
# set here to let the structural checks proceed. The gate itself is verified
# separately by check_write_gate below.
export TRANSCRIPT_SYNC_CONFIRM=1

fail=0

pass() { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; fail=1; }

# --- Part 1: argument integrity -------------------------------------------
# Evaluate the real connection-setup block from the script under test, up to
# and including the REMOTE_DIR_Q case statement.
check_args() {
  local target="$1"
  local name="${target##*/}"
  : > "$CAPTURE"

  local setup
  setup="$(awk '/^esac$/{print; exit} {print}' "$target" | tr -d '\r')"
  # shellcheck disable=SC1090
  eval "$setup"

  "${SSH_CMD[@]}" "cd $REMOTE_DIR_Q && true"
  "${SCP_CMD[@]}" -r "$WORK/export dir" "$SSH_TARGET:~/remote/"

  grep -qxF "ARG:$HYPERON_WIKI_SSH_KEY" "$CAPTURE" \
    && pass "$name: key path preserved as one argument" \
    || bad  "$name: key path was split or altered"

  grep -qxF "ARG:operator@wiki.example.invalid" "$CAPTURE" \
    && pass "$name: ssh target preserved as one argument" \
    || bad  "$name: ssh target was split or altered"

  grep -qF "deck root/hyperon-wiki'" "$CAPTURE" \
    && pass "$name: remote deck path quoted for the remote shell" \
    || bad  "$name: remote deck path would word-split remotely"

  grep -qxF "ARG:$WORK/export dir" "$CAPTURE" \
    && pass "$name: scp source path preserved as one argument" \
    || bad  "$name: scp source path was split"
}

# --- Part 2: the 'latest' symlink actually resolves ------------------------
# Extracts the real symlink block, runs it against the executing shim, and
# checks the resulting link on disk rather than grepping command text.
check_symlink() {
  local target="$1" subdir="$2"
  local name="${target##*/}"

  local snippet
  snippet="$(awk '/^EXPORT_BASENAME=/{found=1} found{print} found && /ln -sfn/{exit}' "$target" | tr -d '\r')"
  if [ -z "$snippet" ]; then
    bad "$name: could not locate the symlink block"
    return
  fi

  local fake_home="$WORK/home_${subdir}"
  local export_dir="$WORK/exports with spaces/sync 20260101 120000"
  mkdir -p "$fake_home/$subdir" "$export_dir"
  # Stand in for the scp that would have run in step 2.
  cp -r "$export_dir" "$fake_home/$subdir/"
  : > "$fake_home/$subdir/sync 20260101 120000/marker.json"

  # (a) Inspect the remote command string the wrapper builds.
  : > "$CAPTURE"
  (
    SSH_CMD=("$WORK/bin/ssh")
    EXPORT_DIR="$export_dir"
    # shellcheck disable=SC1090
    eval "$snippet"
  )
  local remote_cmd
  remote_cmd="$(grep '^ARG:ln -sfn' "$CAPTURE" | head -1)"
  remote_cmd="${remote_cmd#ARG:}"

  if [ -z "$remote_cmd" ]; then
    bad "$name: no ln command was issued"
    return
  fi

  case "$remote_cmd" in
    *"'~/"*|*"'~"*) bad "$name: symlink target quotes a leading tilde ($remote_cmd)" ;;
    *)              pass "$name: symlink target does not quote a leading tilde" ;;
  esac

  case "$remote_cmd" in
    *"ln -sfn 'sync 20260101 120000' ~/$subdir/latest"*)
      pass "$name: basename with spaces quoted correctly, link path left expandable" ;;
    *)
      bad "$name: unexpected ln command ($remote_cmd)" ;;
  esac

  # (b) Execute it for real and confirm `latest` resolves to the export.
  # `-e`/`-d` rather than `-L`: on some platforms `ln -s` copies instead of
  # linking, and either way the ingester only needs `latest` to resolve.
  (
    export HOME="$fake_home"
    SSH_CMD=("$WORK/bin/ssh_exec")
    EXPORT_DIR="$export_dir"
    # shellcheck disable=SC1090
    eval "$snippet"
  )

  local link="$fake_home/$subdir/latest"
  if [ -d "$link" ] && [ -f "$link/marker.json" ]; then
    pass "$name: latest resolves to the uploaded export directory"
  else
    bad "$name: latest does not resolve; the ingester default would fail"
  fi

  if [ -L "$link" ]; then
    local link_target
    link_target="$(readlink "$link")"
    [ "$link_target" = "sync 20260101 120000" ] \
      && pass "$name: link target is the exact basename" \
      || bad  "$name: wrong link target ($link_target)"
  fi
}

# --- Part 3: line endings --------------------------------------------------
# A CRLF shell script fails on the Linux wiki host: the trailing \r becomes part
# of the last token. Assert it explicitly rather than discovering it in prod.
check_line_endings() {
  local target="$1"
  local name="${target##*/}"
  if grep -qU $'\r' "$target"; then
    bad "$name: has CRLF line endings; must be LF to run on the wiki host"
  else
    pass "$name: LF line endings"
  fi
}

# --- Part 4: the production write gate -------------------------------------
# sync_transcripts.sh performs a real production ingest, so it must refuse to
# run unless explicitly opted into. Verified by running it with the opt-in
# cleared and no credentials: it must exit non-zero and say so before doing
# anything. Nothing is contacted - the gate fires first.
check_write_gate() {
  local target="$1"
  local name="${target##*/}"
  local out rc

  out="$(env -u TRANSCRIPT_SYNC_CONFIRM \
         -u HYPERON_WIKI_HOST -u HYPERON_WIKI_SSH_KEY \
         bash "$target" 2>&1)" && rc=0 || rc=$?

  if [ "$rc" -eq 0 ]; then
    bad "$name: ran without TRANSCRIPT_SYNC_CONFIRM=1"
    return
  fi
  pass "$name: refuses to run without TRANSCRIPT_SYNC_CONFIRM=1"

  case "$out" in
    *"Refusing to run"*)
      pass "$name: explains why it refused" ;;
    *)
      bad "$name: refused without explaining ($out)" ;;
  esac

  # The refusal must come before any export/upload step announces itself.
  case "$out" in
    *"[Step 1/3]"*|*"[Step 2/3]"*|*"[Step 3/3]"*)
      bad "$name: started a sync step before the gate fired" ;;
    *)
      pass "$name: gate fires before any export or upload step" ;;
  esac
}

for s in sync_mattermost.sh sync_transcripts.sh server_sync_mattermost.sh; do
  check_line_endings "$REPO_ROOT/scripts/$s"
done

check_args "$REPO_ROOT/scripts/sync_mattermost.sh"
check_args "$REPO_ROOT/scripts/sync_transcripts.sh"
check_symlink "$REPO_ROOT/scripts/sync_mattermost.sh" "mattermost_exports"
check_symlink "$REPO_ROOT/scripts/sync_transcripts.sh" "transcript_exports"
check_write_gate "$REPO_ROOT/scripts/sync_transcripts.sh"

if [ "$fail" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
else
  echo "CHECKS FAILED"
fi
exit "$fail"
