# Accessing Decko Data via Remote Console

**Created**: 2025-10-25
**Environment**: Production Decko deck (Ubuntu 22.04)
**Last Reviewed**: 2025-10-26

---

## Overview

Administrators occasionally need to run Decko/ActiveRecord scripts against the production deck. Remote shells do not inherit the service environment, so the workflow below standardises how to initialise Ruby, load credentials, and execute a `script/card runner` command without exposing secret infrastructure details in this repository.

---

## Quick Access Defaults (Production)

- SSH host: 54.219.9.17 (Elastic IP)
- SSH user: ubuntu (Ubuntu 22.04 AMI default)
- Deck root: /home/ubuntu/magi-archive
- SSH key: ~/.ssh/magi-archive-key.pem

Tip: Add an SSH config entry so tools and future agents don’t need flags:

```
Host magi-archive
  HostName 54.219.9.17
  User ubuntu
  IdentityFile ~/.ssh/magi-archive-key.pem
  IdentitiesOnly yes
  ServerAliveInterval 60
```

Then use `ssh magi-archive` and omit `-i` everywhere in examples.

## One-Line Command Template

```bash
ssh magi-archive '
  cd /home/ubuntu/magi-archive &&
  set -a && source .env.production && set +a &&
  PATH="/home/<user>/.rbenv/shims:$PATH" \
    script/card runner '\''YOUR_RUBY_CODE'\''
'
```

If not using the SSH alias, replace with explicit values:
- ssh user/host: `ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17`
- deck root: `/home/ubuntu/magi-archive`
- rbenv shims path: `/home/ubuntu/.rbenv/shims`

Key ideas remain:
- enter the deck directory
- export environment from `.env.production`
- prepend the rbenv shims directory to `PATH`
- invoke `script/card runner` with correctly escaped quotes

---

## Step-by-Step Breakdown

1. **SSH**
   ```bash
   # Preferred (with SSH config):
   ssh magi-archive

   # Or explicit flags:
   ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17
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
   PATH="/home/ubuntu/.rbenv/shims:$PATH"
   ```

5. **Run Decko code**
   ```bash
   script/card runner 'Ruby code here'
   ```

---

## Common Snippets (use with placeholders)

### List sample cards
```bash
script/card runner 'Card.all.limit(20).each { |c| puts "#{c.id}: #{c.name} (#{c.type_name})" }'
```

### Count cards
```bash
script/card runner 'puts "Total cards: #{Card.count}"'
```

### Recent cards
```bash
script/card runner 'Card.order(created_at: :desc).limit(20).each { |c| puts "#{c.id}: #{c.name}" }'
```

### Fetch specific card
```bash
script/card runner '
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
script/card runner '\''puts "Hello #{ENV.fetch("USER")}"'\''
```

For multi-line snippets, embed newline characters or use a heredoc on the remote host.

---

## Windows/PowerShell Workflow (stdin runner)

PowerShell quoting can mangle nested quotes in remote SSH commands. The most reliable pattern is to pipe Ruby code to `script/card runner -` via SSH stdin. This avoids complex escaping and CRLF issues.

1) Test the runner

```powershell
$key = "$env:USERPROFILE\.ssh\magi-archive-key.pem"
"puts 123`n" |
  ssh -T -o StrictHostKeyChecking=accept-new -i $key ubuntu@54.219.9.17 \
    'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && \
     export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -'
```

2) Count cards (read-only)

```powershell
$key = "$env:USERPROFILE\.ssh\magi-archive-key.pem"
"puts Card.count`n" |
  ssh -T -o StrictHostKeyChecking=accept-new -i $key ubuntu@54.219.9.17 \
    'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && \
     export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -'
```

3) Fetch a single example card (latest updated) and save locally

```powershell
$key = "$env:USERPROFILE\.ssh\magi-archive-key.pem"
$code = @'
require "json"
card = Card.order(updated_at: :desc).limit(1).first
puts JSON.generate(id: card.id, name: card.name, type: card.type_name, updated_at: card.updated_at)
'@
$code |
  ssh -T -o StrictHostKeyChecking=accept-new -i $key ubuntu@54.219.9.17 \
    'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && \
     export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -' \
  > .\docs\sample-card.json
```

4) Fetch a specific named card and save locally

```powershell
$key = "$env:USERPROFILE\.ssh\magi-archive-key.pem"
$code = @'
require "json"
card = Card.fetch("Example+Card")
puts JSON.generate(id: card.id, name: card.name, type: card.type_name, updated_at: card.updated_at)
'@
$code |
  ssh -T -o StrictHostKeyChecking=accept-new -i $key ubuntu@54.219.9.17 \
    'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && \
     export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -' \
  > .\\docs\\sample-card.json
```

Notes:
- Do not wrap the PATH export in quotes on the remote: use `export PATH=/home/ubuntu/.rbenv/shims:$PATH`.
- Prefer stdin `runner -` on Windows to avoid nested quoting and CRLF pitfalls.

---

## Linux/macOS Workflow (stdin runner)

Bash/zsh can also avoid quoting issues by piping code into `script/card runner -`. You can use `printf` for one-liners or a heredoc for multi-line snippets.

1) Test the runner

```bash
printf '%s\n' 'puts 123' \
  | ssh -T -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 \
    'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && \
     export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -'
```

2) Count cards (read-only)

```bash
printf '%s\n' 'puts Card.count' \
  | ssh -T -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 \
    'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && \
     export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -'
```

3) Fetch the latest-updated card and save locally

```bash
ssh -T -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 \
  'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && \
   export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -' \
  > docs/sample-card.json <<'RUBY'
require "json"
card = Card.order(updated_at: :desc).limit(1).first
puts JSON.generate(id: card.id, name: card.name, type: card.type_name, updated_at: card.updated_at)
RUBY
```

4) Fetch a specific named card and save locally

```bash
ssh -T -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 \
  'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && \
   export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -' \
  > docs/sample-card.json <<'RUBY'
require "json"
card = Card.fetch("Example+Card")
puts JSON.generate(id: card.id, name: card.name, type: card.type_name, updated_at: card.updated_at)
RUBY
```

Notes:
- As with Windows, avoid quoting PATH on the remote; use `export PATH=/home/ubuntu/.rbenv/shims:$PATH`.
- The output redirection (`> docs/sample-card.json`) writes to your local machine.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
| --- | --- | --- |
| `/usr/bin/env: 'ruby': No such file or directory` | rbenv shims absent | Prepend the shims directory to `PATH`. |
| `fe_sendauth: no password supplied` | `.env.production` not sourced | Use `set -a && source .env.production && set +a`. |
| `cat: .env.production: No such file or directory` | Wrong working directory | `cd <deck-root>` first. |
| Permission errors when creating cards | Runner executing as default user | Wrap changes in `Card::Auth.as_bot do ... end`. |
| Runner prints nothing or shows Rails help | Shell quoting eaten by PowerShell | Pipe to `script/card runner -` via SSH stdin (see Windows workflow). |
| `/usr/bin/env: ‘ruby’: No such file or directory` even after exporting PATH | PATH export wrapped in quotes in single-quoted SSH string | Use `export PATH=/home/ubuntu/.rbenv/shims:$PATH` (no quotes). |
| `wc: 'file'\r: No such file or directory` | CRLF line endings leaked into remote script/redirect | Use stdin piping or ensure Unix LF endings. |

---

## Backups (masked example)

Use the same environment bootstrap, then call `pg_dump` against the managed PostgreSQL endpoint recorded in your secrets vault:

```bash
ssh -i <ssh-key> <user>@<deck-host> '
  cd <deck-root> &&
  set -a && source .env.production && set +a &&
  pg_dump -h <rds-endpoint> -U <db-user> -d <db-name> \
    > backup-$(date +%Y%m%d-%H%M%S).sql
'
```

Download backups with `scp` using the same placeholder values.

---

## Quick Reference (store securely outside repo)

- SSH key path
- SSH username
- Deck host (public DNS or bastion alias)
- Deck root (e.g., `/home/<user>/magi-archive`)
- rbenv shims path
- Database endpoint, name, and role account

These identifiers are intentionally omitted here to keep the repository free of sensitive infrastructure details.

---

## Change Log

- 2025-10-26: Redacted infrastructure specifics and added placeholder-driven workflow.
- 2025-10-25: Initial guide documenting remote console approach.
- 2025-11-07: Added Windows/PowerShell stdin-runner workflow and Linux/macOS equivalents; added named-card examples; expanded troubleshooting with PATH/CRLF tips.
