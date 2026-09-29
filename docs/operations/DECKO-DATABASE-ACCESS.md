# Accessing Decko Data via Remote Console

**Created**: 2025-10-25
**Environment**: A production Decko deck (Ubuntu 22.04)
**Last Reviewed**: 2026-09-08
**Verified against the Hyperon Wiki production deployment**: 2026-09-15

> **Verified procedure; placeholders for values.** This procedure has been confirmed
> against the Hyperon Wiki's actual production deployment via a read-only remote-console
> check on 2026-09-15 (see *Verified against this deployment* below for what that check
> found). Every host, user, key path, and deck root below remains a placeholder in
> `<angle-brackets>` — this repository deliberately does not record concrete values for any
> deck. Obtain them from the **server-access handoff** — the Administrator card and its
> children — not from a repository file.
>
> This guide originated on a sibling Decko deck as a reusable *procedure*. It has since been
> exercised and confirmed to work, with one correction, on this deployment. For reference,
> the Hyperon Wiki is served at `wiki.hyperon.dev` and is PostgreSQL-backed.

## Verified against this deployment (2026-09-15)

A read-only remote-console check confirmed the following for the Hyperon Wiki's production
deployment. No writes, restarts, or deploys were performed.

- The deck root exists and the repository checkout is present at `<deck-root>`.
- `.env.production` exists at the deck root.
- `~/.rbenv/shims` and `~/.rbenv/bin` exist, and **must be prepended to `PATH`** — `ruby`
  and `bundle` are not found on `PATH` otherwise.
- **`script/card` is not executable** in this checkout. Running it directly
  (`script/card runner -`) fails with `Permission denied`. The wrapper's first line is
  `#!/usr/bin/env ruby`, so invoking it explicitly through the Ruby interpreter —
  `ruby script/card runner -` or `ruby script/card runner '...'` — works around this
  without needing to change the file's permissions. **Use the `ruby script/card runner`
  form below, not the bare `script/card runner` form**, unless you have confirmed the
  wrapper is executable on the box you're working against.
- With rbenv paths prepended and `.env.production` sourced, `ruby script/card runner -`
  succeeded: Rails env `production`, Ruby version `3.2.3`, and a `Card.count` query
  returned successfully (the count itself is not recorded here — it changes constantly and
  is not a useful fact to freeze into documentation).

The templates below have been updated to use `ruby script/card runner`. What this check
actually exercised: the environment bootstrap sequence (rbenv PATH prepend, sourcing
`.env.production`), and the stdin form of the runner (`ruby script/card runner -`), both via
a direct SSH session — not through the PowerShell or Linux/macOS example scripts below as
written. The quoting rules and the rest of the troubleshooting table are carried over from
the inherited template and have not each been individually exercised against this
deployment.

---

## Overview

Administrators occasionally need to run Decko/ActiveRecord scripts against a production deck. Remote shells do not inherit the service environment, so the workflow below standardises how to initialise Ruby, load credentials, and execute a `ruby script/card runner` command without recording infrastructure details in this repository.

---

## What you need before you start

Obtain these from the access handoff and keep them outside the repository:

| Value | Placeholder used below |
|---|---|
| SSH host (public DNS or bastion alias) | `<deck-host>` |
| SSH user | `<ssh-user>` |
| SSH private key path | `<ssh-key>` |
| Deck root directory on the server | `<deck-root>` |
| rbenv shims path | `<rbenv-shims>` |

Tip: Add an SSH config entry so tools and future agents don’t need flags. The alias is a
client-side name only — pick anything:

```
Host <deck-alias>
  HostName <deck-host>
  User <ssh-user>
  IdentityFile <ssh-key>
  IdentitiesOnly yes
  ServerAliveInterval 60
```

Then use `ssh <deck-alias>` and omit `-i` everywhere in examples.

## One-Line Command Template

```bash
ssh <deck-alias> '
  cd <deck-root> &&
  set -a && source .env.production && set +a &&
  PATH="<rbenv-shims>:$PATH" \
    ruby script/card runner '\''YOUR_RUBY_CODE'\''
'
```

If not using the SSH alias, replace with explicit values:
- ssh user/host: `ssh -i <ssh-key> <ssh-user>@<deck-host>`
- deck root: `<deck-root>`
- rbenv shims path: `<rbenv-shims>`

Key ideas remain:
- enter the deck directory
- export environment from `.env.production`
- prepend the rbenv shims directory to `PATH`
- invoke `ruby script/card runner` (not the bare `script/card runner` — the wrapper is not
  executable on this deployment) with correctly escaped quotes

---

## Step-by-Step Breakdown

1. **SSH**
   ```bash
   # Preferred (with SSH config):
   ssh <deck-alias>

   # Or explicit flags:
   ssh -i <ssh-key> <ssh-user>@<deck-host>
   ```

2. **Deck root**
   ```bash
   cd <deck-root>
   ```

3. **Load environment**
   ```bash
   set -a
   source .env.production
   set +a
   ```

4. **Expose rbenv shims**
   ```bash
   PATH="<rbenv-shims>:$PATH"
   ```

5. **Run Decko code**
   ```bash
   ruby script/card runner 'Ruby code here'
   ```
   (`script/card` is not executable in this deployment's checkout — invoking it through
   `ruby` works around that without changing file permissions.)

---

## Common Snippets (use with placeholders)

### List sample cards
```bash
ruby script/card runner 'Card.all.limit(20).each { |c| puts "#{c.id}: #{c.name} (#{c.type_name})" }'
```

### Count cards
```bash
ruby script/card runner 'puts "Total cards: #{Card.count}"'
```

### Recent cards
```bash
ruby script/card runner 'Card.order(created_at: :desc).limit(20).each { |c| puts "#{c.id}: #{c.name}" }'
```

### Fetch specific card
```bash
ruby script/card runner '
  card = Card.fetch("Example+Card")
  puts "#{card.id}: #{card.name}"
'
```

Wrap modifications with `Card::Auth.as_bot` when elevated permissions are required.

---

## Quote Escaping Tips

Remote execution requires three layers of quoting:
1. outer single quotes for the SSH command
2. escaped inner single quotes for the `runner` argument (`'\'' ... '\''`)
3. double quotes inside Ruby for interpolation

Example:
```bash
ruby script/card runner '\''puts "Hello #{ENV.fetch("USER")}"'\''
```

For multi-line snippets, embed newline characters or use a heredoc on the remote host.

---

## Windows/PowerShell Workflow (stdin runner)

PowerShell quoting can mangle nested quotes in remote SSH commands. The most reliable pattern is to pipe Ruby code to `ruby script/card runner -` via SSH stdin. This avoids complex escaping and CRLF issues.

PowerShell does not support `\` line continuation the way bash does, so the examples below
keep the remote SSH command (and any output redirection) on one physical line. These
examples show the correct invocation shape; they have not themselves been run end-to-end on
Windows against this deployment — only the underlying bootstrap-and-stdin-runner approach was
verified (see *Verified against this deployment* above), via a direct SSH session, not via
PowerShell specifically.

1) Test the runner

```powershell
$key = "<ssh-key>"
"puts 123`n" | ssh -T -o StrictHostKeyChecking=accept-new -i $key <ssh-user>@<deck-host> 'cd <deck-root> && set -a && . .env.production && set +a && export PATH=<rbenv-shims>:$PATH && ruby script/card runner -'
```

2) Count cards (read-only)

```powershell
$key = "<ssh-key>"
"puts Card.count`n" | ssh -T -o StrictHostKeyChecking=accept-new -i $key <ssh-user>@<deck-host> 'cd <deck-root> && set -a && . .env.production && set +a && export PATH=<rbenv-shims>:$PATH && ruby script/card runner -'
```

3) Fetch a single example card (latest updated) and save locally

```powershell
$key = "<ssh-key>"
$code = @'
require "json"
card = Card.order(updated_at: :desc).limit(1).first
puts JSON.generate(id: card.id, name: card.name, type: card.type_name, updated_at: card.updated_at)
'@
$code | ssh -T -o StrictHostKeyChecking=accept-new -i $key <ssh-user>@<deck-host> 'cd <deck-root> && set -a && . .env.production && set +a && export PATH=<rbenv-shims>:$PATH && ruby script/card runner -' > .\docs\sample-card.json
```

4) Fetch a specific named card and save locally

```powershell
$key = "<ssh-key>"
$code = @'
require "json"
card = Card.fetch("Example+Card")
puts JSON.generate(id: card.id, name: card.name, type: card.type_name, updated_at: card.updated_at)
'@
$code | ssh -T -o StrictHostKeyChecking=accept-new -i $key <ssh-user>@<deck-host> 'cd <deck-root> && set -a && . .env.production && set +a && export PATH=<rbenv-shims>:$PATH && ruby script/card runner -' > .\docs\sample-card.json
```

Notes:
- Do not wrap the PATH export in quotes on the remote: use `export PATH=<rbenv-shims>:$PATH`.
- Prefer stdin `runner -` on Windows to avoid nested quoting and CRLF pitfalls.

---

## Linux/macOS Workflow (stdin runner)

Bash/zsh can also avoid quoting issues by piping code into `ruby script/card runner -`. You can use `printf` for one-liners or a heredoc for multi-line snippets.

1) Test the runner

```bash
printf '%s\n' 'puts 123' \
  | ssh -T -i <ssh-key> <ssh-user>@<deck-host> \
    'cd <deck-root> && set -a && . .env.production && set +a && \
     export PATH=<rbenv-shims>:$PATH && ruby script/card runner -'
```

2) Count cards (read-only)

```bash
printf '%s\n' 'puts Card.count' \
  | ssh -T -i <ssh-key> <ssh-user>@<deck-host> \
    'cd <deck-root> && set -a && . .env.production && set +a && \
     export PATH=<rbenv-shims>:$PATH && ruby script/card runner -'
```

3) Fetch the latest-updated card and save locally

```bash
ssh -T -i <ssh-key> <ssh-user>@<deck-host> \
  'cd <deck-root> && set -a && . .env.production && set +a && \
   export PATH=<rbenv-shims>:$PATH && ruby script/card runner -' \
  > docs/sample-card.json <<'RUBY'
require "json"
card = Card.order(updated_at: :desc).limit(1).first
puts JSON.generate(id: card.id, name: card.name, type: card.type_name, updated_at: card.updated_at)
RUBY
```

4) Fetch a specific named card and save locally

```bash
ssh -T -i <ssh-key> <ssh-user>@<deck-host> \
  'cd <deck-root> && set -a && . .env.production && set +a && \
   export PATH=<rbenv-shims>:$PATH && ruby script/card runner -' \
  > docs/sample-card.json <<'RUBY'
require "json"
card = Card.fetch("Example+Card")
puts JSON.generate(id: card.id, name: card.name, type: card.type_name, updated_at: card.updated_at)
RUBY
```

Notes:
- As with Windows, avoid quoting PATH on the remote; use `export PATH=<rbenv-shims>:$PATH`.
- The output redirection (`> docs/sample-card.json`) writes to your local machine.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
| --- | --- | --- |
| `Permission denied` running `script/card runner -` | `script/card` is not executable on this deployment | Invoke it through the Ruby interpreter instead: `ruby script/card runner -`. |
| `/usr/bin/env: 'ruby': No such file or directory` | rbenv shims absent | Prepend the shims directory to `PATH`. |
| `fe_sendauth: no password supplied` | `.env.production` not sourced | Use `set -a && source .env.production && set +a`. |
| `cat: .env.production: No such file or directory` | Wrong working directory | `cd <deck-root>` first. |
| Permission errors when creating cards | Runner executing as default user | Wrap changes in `Card::Auth.as_bot do ... end`. |
| Runner prints nothing or shows Rails help | Shell quoting eaten by PowerShell | Pipe to `ruby script/card runner -` via SSH stdin (see Windows workflow). |
| `/usr/bin/env: ‘ruby’: No such file or directory` even after exporting PATH | PATH export wrapped in quotes in single-quoted SSH string | Use `export PATH=<rbenv-shims>:$PATH` (no quotes). |
| `wc: 'file'\r: No such file or directory` | CRLF line endings leaked into remote script/redirect | Use stdin piping or ensure Unix LF endings. |

---

## Backup and restore procedures are out of scope here

This document confirms the Decko remote-console runner shape. It does **not** define the
supported backup, restore, retention, or download procedure for this deployment.

Those answers belong in the server-access handoff, not in the repository. Do not infer from
the runner examples above that `pg_dump`, `scp`, or any particular storage location is the
approved backup path. When an approved backup runbook exists, keep concrete endpoints,
paths, accounts, retention policy, and restore-test evidence outside this document; at most,
record here that the private runbook has been verified.

---

## Quick Reference (store securely outside repo)

- SSH key path
- SSH username
- Deck host (public DNS or bastion alias)
- Deck root
- rbenv shims path
- Database endpoint, name, and role account

These identifiers are intentionally omitted here to keep the repository free of sensitive infrastructure details.

---

## Change Log

- 2026-09-15: Verified the procedure against the Hyperon Wiki's production deployment via a
  read-only remote-console check. Corrected all command templates from `script/card runner`
  to `ruby script/card runner`, since `script/card` is not executable in this deployment's
  checkout. Confirmed the rbenv-prepend and `.env.production`-source steps are both
  required. Dropped the inherited-template banner in favor of a verified-procedure note.
- 2025-10-26: Redacted infrastructure specifics and added placeholder-driven workflow.
- 2025-10-25: Initial guide documenting remote console approach.
- 2025-11-07: Added Windows/PowerShell stdin-runner workflow and Linux/macOS equivalents; added named-card examples; expanded troubleshooting with PATH/CRLF tips.
