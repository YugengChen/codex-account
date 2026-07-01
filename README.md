# codex-account

`codex-account` is a local Bash utility for managing multiple Codex login
states on one machine. It saves account auth files under `CODEX_HOME/accounts`,
switches the active `CODEX_HOME/auth.json`, reads live rate limits, and can pick
the best available saved account.

## Status

This repository contains the command-line utility only. It does not include any
saved account data, `auth.json` files, backups, or local Codex runtime state.

The script is primarily written for Linux-like environments with:

- Bash
- `jq`
- `flock`
- GNU `date`
- `timeout`
- the `codex` CLI

macOS may require extra coreutils or script changes because the script uses
Linux/GNU command behavior.

## Install

```bash
install -m 755 bin/codex-account ~/.local/bin/codex-account
```

Make sure `~/.local/bin` is on `PATH`, or install the script into another
directory already on `PATH`.

## Usage

```bash
codex-account list --no
codex-account current
codex-account save work
codex-account use work
codex-account change
codex-account add personal --device-auth
codex-account exec personal -- codex
codex-account remove old-account
```

For the full command list:

```bash
codex-account --help
```

## Data Layout

By default, data is stored under `~/.codex`. Override this with `CODEX_HOME`.

```text
$CODEX_HOME/
  auth.json
  accounts/
    current
    .lock
    backups/
    account-name/
      auth.json
```

Account names may contain only letters, digits, dots, underscores, and dashes.

## Safety Notes

- Do not commit `auth.json`, `$CODEX_HOME`, `$CODEX_HOME/accounts`, backups, or
  temporary runtime directories.
- `list` reads live rate limits through `codex app-server`; it does not send a
  model request.
- `touch` intentionally sends a real `codex exec` request and can consume model
  usage.
- `rest` consumes an official rate-limit reset credit when a reset is eligible.
- The script uses `flock` around account-state changes to avoid concurrent
  writes.

## Development Checks

```bash
bash -n bin/codex-account
rg -n --hidden --no-ignore -i 'access_token|refresh_token|id_token|OPENAI_API_KEY|bearer|password|secret' .
```
