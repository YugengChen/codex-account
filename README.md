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
      limits.json
      reset-credits.json
      reset.json
      touch.json
```

`limits.json` is a short-lived cache of the last successful rate-limit response.
It contains quota data and a cache timestamp, but no auth tokens or account
identifiers. `reset-credits.json` caches only the available reset count, credit
status, expiry time, and cache timestamp; it contains no credit IDs, profile
fields, account identifiers, or tokens. `reset.json` stores local reset-credit
metadata. `touch.json` stores only a verified quota-window duration, reset
epoch, and verification time. Existing weekly-only `touch.json` files remain
supported.

## Weekly and Monthly Limit Windows

Current Codex responses can expose a weekly `10080`-minute window as
`rateLimits.primary` with no secondary window. Some accounts instead expose a
monthly window; for example, `43800` minutes is the server's average-month
duration. The utility recognizes monthly durations from 28 through 31 days and
identifies all windows by `windowDurationMins` rather than assuming `primary`
is always a 5-hour window.

`list` reports the long-term window as `quota=week` or `quota=month` with
generic `quota_left` and `quota_reset` fields. `change` compares the remaining
percentage of each account's weekly or monthly quota and uses the earlier reset
time as the tie-breaker.

Live-limit reads retry transient failures once. If both attempts fail, `list`
uses a successful result cached within the last 15 minutes and prefixes the
cached `quota_left` with `~`. It prints a note when cached data is used, when an
account needs another login, or when neither live nor recent cached data is
available. Set `CODEX_ACCOUNT_LIMIT_CACHE_MAX_AGE` to change the cache lifetime
in seconds, or set it to `0` to disable fallback to older results.

Reset-credit details are optional in the live response and can be temporarily
unavailable even when quota fields succeed. `list` first uses reset-credit data
returned by `account/rateLimits/read` and only makes the compatibility request
when those fields are absent. A successful result is cached for one hour by
default. When a later read omits the data, `reset_left` uses the recent cache
and marks cached values with `~`; known expired credits invalidate the cache.
Set `CODEX_ACCOUNT_RESET_CACHE_MAX_AGE` to change this lifetime, or set it to
`0` to disable the fallback.

`touch all` checks every saved account and skips windows whose reset epoch is
already verified. For an unanchored weekly or monthly window, it sends a real
Codex request and compares repeated live `quota_reset` values. Three
consecutive identical reset epochs are recorded as an anchored window. By
default it keeps retrying unstable windows; use `--once` or `--max-attempts N`
to bound usage.

`rest`/`reset` reads a pre-reset snapshot, consumes exactly one reset credit,
and then polls fresh read-only snapshots until the weekly/monthly quota change
is visible. This handles the backend's delayed rate-limit refresh without ever
retrying the consume call. Set `CODEX_ACCOUNT_RESET_VERIFY_ATTEMPTS` (default
`8`) and `CODEX_ACCOUNT_RESET_VERIFY_DELAY` in seconds (default `1`) to tune
the verification wait. If confirmation times out, the command reports that the
credit was consumed and tells you to refresh with `list`; do not run `reset`
again for that attempt.

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
  substantial weekly or monthly allowance.
- `rest` consumes an official rate-limit reset credit when a reset is eligible.
- The script uses `flock` around account-state changes to avoid concurrent
  writes.

## Development Checks

```bash
bash -n bin/codex-account
tests/test_rate_limits.sh
rg -n --hidden --no-ignore -i 'access_token|refresh_token|id_token|OPENAI_API_KEY|bearer|password|secret' .
```
