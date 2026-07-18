#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_CODEX_HOME="$(mktemp -d "${TMPDIR:-/tmp}/codex-account-tests.XXXXXX")"
trap 'rm -rf "$TEST_CODEX_HOME"' EXIT
export CODEX_HOME="$TEST_CODEX_HOME"

# shellcheck source=../bin/codex-account
source "$REPO_DIR/bin/codex-account"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

now_epoch="$(date +%s)"
month_probe_reset=$((now_epoch + 43800 * 60))
month_probe_json="$(jq -cn --argjson reset "$month_probe_reset" '
  {
    rateLimits: {
      planType: "team",
      primary: {usedPercent: 0, windowDurationMins: 43800, resetsAt: $reset},
      secondary: null
    }
  }
')"

IFS=$'\t' read -r plan state five_left five_reset quota_kind quota_duration quota_left quota_reset reset_left note \
  < <(format_rate_limit_fields "$month_probe_json")
assert_eq "team" "$plan" "monthly plan"
assert_eq "probemonth" "$state" "monthly probe state"
assert_eq "month" "$quota_kind" "monthly quota kind"
assert_eq "43800" "$quota_duration" "monthly quota duration"
assert_eq "100%" "$quota_left" "monthly quota left"
assert_eq "$month_probe_reset" "$quota_reset" "monthly quota reset"
assert_eq "monthly-only" "$(rate_limit_layout "$month_probe_json")" "monthly layout"

IFS=$'\t' read -r state five_left quota_kind quota_duration quota_left quota_reset note \
  < <(change_candidate_fields "$month_probe_json")
assert_eq "probemonth" "$state" "monthly change state"
assert_eq "month" "$quota_kind" "monthly change kind"
assert_eq "100" "$quota_left" "monthly numeric quota left"

month_fixed_json='{"rateLimits":{"planType":"team","primary":{"usedPercent":37,"windowDurationMins":43200,"resetsAt":1900000000},"secondary":null}}'
IFS=$'\t' read -r plan state five_left five_reset quota_kind quota_duration quota_left quota_reset reset_left note \
  < <(format_rate_limit_fields "$month_fixed_json")
assert_eq "ok" "$state" "fixed monthly state"
assert_eq "month" "$quota_kind" "fixed monthly kind"
assert_eq "63%" "$quota_left" "fixed monthly quota left"

week_json='{"rateLimits":{"planType":"plus","primary":{"usedPercent":25,"windowDurationMins":10080,"resetsAt":1900000000},"secondary":null}}'
IFS=$'\t' read -r plan state five_left five_reset quota_kind quota_duration quota_left quota_reset reset_left note \
  < <(format_rate_limit_fields "$week_json")
assert_eq "ok" "$state" "weekly state"
assert_eq "week" "$quota_kind" "weekly quota kind"
assert_eq "10080" "$quota_duration" "weekly quota duration"
assert_eq "75%" "$quota_left" "weekly quota left"
assert_eq "weekly-only" "$(rate_limit_layout "$week_json")" "weekly layout"

five_month_json='{"rateLimits":{"planType":"pro","primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1900000000},"secondary":{"usedPercent":30,"windowDurationMins":44640,"resetsAt":1901000000}}}'
IFS=$'\t' read -r plan state five_left five_reset quota_kind quota_duration quota_left quota_reset reset_left note \
  < <(format_rate_limit_fields "$five_month_json")
assert_eq "90%" "$five_left" "5h quota left"
assert_eq "month" "$quota_kind" "31-day monthly kind"
assert_eq "70%" "$quota_left" "31-day monthly quota left"
assert_eq "five-and-month" "$(rate_limit_layout "$five_month_json")" "5h/month layout"

ensure_dirs
mkdir -p "$(account_dir fixture)"
record_quota_anchor fixture 43800 1900000000
quota_anchor_matches fixture 43800 1900000000 || fail "new monthly anchor did not match"
if quota_anchor_matches fixture 10080 1900000000; then
  fail "monthly anchor matched a weekly duration"
fi

printf '%s\n' '{"verifiedAt":1,"anchoredWeekResetAt":1900000001}' >"$(account_touch_metadata fixture)"
quota_anchor_matches fixture 10080 1900000001 || fail "legacy weekly anchor did not match"

printf 'PASS: weekly/monthly rate-limit parsing and anchor compatibility\n'
