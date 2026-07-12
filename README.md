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
codex-account list
codex-account touch all
codex-account rest work --dry-run
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
      reset.json
      touch.json
```

`reset.json` stores local reset-credit metadata. `touch.json` stores only the
verified weekly reset epoch and verification time; it does not contain auth
tokens or account identifiers.

## Weekly Limit Windows

Current Codex responses can expose a weekly `10080`-minute window as
`rateLimits.primary` with no secondary window. The utility identifies windows
by `windowDurationMins` rather than assuming `primary` is always a 5-hour
window.

`touch all` checks every saved account and skips windows whose reset epoch is
already verified. For an unanchored weekly window, it sends a real Codex
request and compares repeated live `week_reset` values. Three consecutive
identical reset epochs are recorded as an anchored window. By default it keeps
retrying unstable windows; use `--once` or `--max-attempts N` to bound usage.

Account names may contain only letters, digits, dots, underscores, and dashes.

## Safety Notes

- Do not commit `auth.json`, `$CODEX_HOME`, `$CODEX_HOME/accounts`, backups, or
  temporary runtime directories.
- Never paste command output containing tokens, raw `auth.json` content, or
  private account identifiers into issues, commits, or pull requests.
- `list` reads live rate limits through `codex app-server`; it does not send a
  model request.
- `touch` intentionally sends a real `codex exec` request and can consume model
  usage. Its default strong prompt is 100,000 characters and retries can consume
  substantial weekly allowance.
- `rest` consumes an official rate-limit reset credit when a reset is eligible.
- The script uses `flock` around account-state changes to avoid concurrent
  writes.

## Development Checks

```bash
bash -n bin/codex-account
rg -n --hidden --no-ignore -i 'access_token|refresh_token|id_token|OPENAI_API_KEY|bearer|password|secret' .
```
