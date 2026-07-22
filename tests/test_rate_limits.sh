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

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$label: missing '$needle'"
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

auth_error_json='{"rateLimits":null,"tokenPlanType":"team","rateLimitError":"401 Unauthorized: authentication token has been invalidated; please try signing in again"}'
transient_error_json='{"rateLimits":null,"tokenPlanType":"team","rateLimitError":"temporary transport error"}'
IFS=$'\t' read -r plan state five_left five_reset quota_kind quota_duration quota_left quota_reset reset_left note \
  < <(format_rate_limit_fields "$auth_error_json")
assert_eq "team" "$plan" "auth error plan"
assert_eq "relogin" "$state" "auth error state"
assert_eq "-" "$five_left" "auth error 5h quota"
assert_eq "-" "$quota_kind" "auth error quota kind"
assert_eq "-" "$quota_left" "auth error quota left"

IFS=$'\t' read -r state five_left quota_kind quota_duration quota_left quota_reset note \
  < <(change_candidate_fields "$auth_error_json")
assert_eq "relogin" "$state" "auth error change state"
assert_eq "-1" "$five_left" "auth error numeric 5h quota"
assert_eq "-" "$quota_kind" "auth error change quota kind"
assert_eq "-1" "$quota_left" "auth error numeric quota left"

retry_counter="$TEST_CODEX_HOME/retry-counter"
printf '%s\n' 0 >"$retry_counter"
(
  query_account_status_once() {
    local count
    count="$(sed -n '1p' "$retry_counter")"
    count=$((count + 1))
    printf '%s\n' "$count" >"$retry_counter"
    if (( count == 1 )); then
      printf '%s\n' "$transient_error_json"
    else
      printf '%s\n' "$week_json"
    fi
  }
  CODEX_ACCOUNT_STATUS_ATTEMPTS=2
  CODEX_ACCOUNT_STATUS_RETRY_DELAY=0
  retry_result="$(query_account_status "$TEST_CODEX_HOME/accounts/retry/auth.json")"
  status_has_live_limits "$retry_result" || fail "transient status was not retried"
)
assert_eq "2" "$(sed -n '1p' "$retry_counter")" "status retry count"

mkdir -p "$(account_dir di)" "$(account_dir google3)"
printf '%s\n' '{}' >"$(account_auth di)"
printf '%s\n' '{}' >"$(account_auth google3)"
query_account_status() {
  case "$(basename "$(dirname "$1")")" in
    di) printf '%s\n' "$auth_error_json" ;;
    google3) printf '%s\n' "$week_json" ;;
    *) printf '%s\n' '{"rateLimits":null,"tokenPlanType":"unknown","rateLimitError":"unavailable"}' ;;
  esac
}
list_output="$(cmd_list)"
assert_contains "$list_output" "di(team)" "list keeps failed account visible"
assert_contains "$list_output" "google3(plus)" "list continues after failed account"
assert_contains "$list_output" "login required: di" "list reports login requirement"

query_account_status() {
  printf '%s\n' "$transient_error_json"
}
list_output="$(cmd_list)"
assert_contains "$list_output" "~75%" "list marks cached quota"
assert_contains "$list_output" "cached limits" "list reports cached fallback"
assert_contains "$list_output" "google3" "cached account remains visible"
if jq -e '.status | has("tokens") or has("auth") or has("account")' "$(account_limits_cache google3)" >/dev/null 2>&1; then
  fail "limits cache contains auth-shaped fields"
fi

ensure_dirs
mkdir -p "$(account_dir fixture)"
record_quota_anchor fixture 43800 1900000000
quota_anchor_matches fixture 43800 1900000000 || fail "new monthly anchor did not match"
if quota_anchor_matches fixture 10080 1900000000; then
  fail "monthly anchor matched a weekly duration"
fi

printf '%s\n' '{"verifiedAt":1,"anchoredWeekResetAt":1900000001}' >"$(account_touch_metadata fixture)"
quota_anchor_matches fixture 10080 1900000001 || fail "legacy weekly anchor did not match"

reset_before_json='{"rateLimits":{"limitId":"codex","planType":"team","primary":{"usedPercent":98,"windowDurationMins":10080,"resetsAt":1900000000},"secondary":null},"rateLimitResetCredits":{"availableCount":3}}'
reset_stale_json='{"rateLimits":{"limitId":"codex","planType":"team","primary":{"usedPercent":98,"windowDurationMins":10080,"resetsAt":1900000000},"secondary":null},"rateLimitResetCredits":{"availableCount":2}}'
reset_after_json='{"rateLimits":{"limitId":"codex","planType":"team","primary":{"usedPercent":6,"windowDurationMins":10080,"resetsAt":1900600000},"secondary":null},"rateLimitResetCredits":{"availableCount":2}}'

if reset_effect_observed "$reset_before_json" "$reset_stale_json"; then
  fail "credit-count decrease incorrectly confirmed a quota reset"
fi
reset_effect_observed "$reset_before_json" "$reset_after_json" || fail "changed quota window was not recognized as a reset"

refresh_counter="$TEST_CODEX_HOME/reset-refresh-counter"
printf '%s\n' 0 >"$refresh_counter"
(
  query_account_status() {
    local count
    count="$(sed -n '1p' "$refresh_counter")"
    count=$((count + 1))
    printf '%s\n' "$count" >"$refresh_counter"
    if (( count == 1 )); then
      printf '%s\n' "$reset_stale_json"
    else
      printf '%s\n' "$reset_after_json"
    fi
  }
  CODEX_ACCOUNT_RESET_VERIFY_ATTEMPTS=3
  CODEX_ACCOUNT_RESET_VERIFY_DELAY=0
  refreshed_json="$(wait_for_reset_refresh /unused/auth.json "$reset_before_json" "$reset_stale_json")" || fail "delayed reset refresh was not confirmed"
  reset_effect_observed "$reset_before_json" "$refreshed_json" || fail "refresh returned an unchanged quota window"
)
assert_eq "2" "$(sed -n '1p' "$refresh_counter")" "reset refresh poll count"

mkdir -p "$(account_dir resetfixture)"
printf '%s\n' '{}' >"$(account_auth resetfixture)"
consume_counter="$TEST_CODEX_HOME/reset-consume-counter"
command_query_counter="$TEST_CODEX_HOME/reset-command-query-counter"
printf '%s\n' 0 >"$consume_counter"
printf '%s\n' 0 >"$command_query_counter"
reset_command_output="$({
  query_account_status() {
    local count
    count="$(sed -n '1p' "$command_query_counter")"
    count=$((count + 1))
    printf '%s\n' "$count" >"$command_query_counter"
    case "$count" in
      1|2) printf '%s\n' "$reset_before_json" ;;
      *) printf '%s\n' "$reset_after_json" ;;
    esac
  }
  consume_reset_credit() {
    local count
    count="$(sed -n '1p' "$consume_counter")"
    printf '%s\n' "$((count + 1))" >"$consume_counter"
    jq -c '. + {outcome:"reset",resetError:null}' <<<"$reset_stale_json"
  }
  CODEX_ACCOUNT_RESET_VERIFY_ATTEMPTS=3
  CODEX_ACCOUNT_RESET_VERIFY_DELAY=0
  cmd_rest resetfixture
})"
assert_eq "1" "$(sed -n '1p' "$consume_counter")" "reset consume count"
assert_contains "$reset_command_output" "reset confirmed" "reset command confirmation"
assert_contains "$reset_command_output" "quota_left=94%" "reset command refreshed quota"
assert_eq "1900600000" "$(jq -r '.lastResetQuotaExpiresAt' "$(account_reset_metadata resetfixture)")" "confirmed reset metadata"
assert_eq "1900600000" "$(jq -r '.anchoredResetAt' "$(account_touch_metadata resetfixture)")" "confirmed reset anchor"

mkdir -p "$(account_dir pendingfixture)"
printf '%s\n' '{}' >"$(account_auth pendingfixture)"
pending_consume_counter="$TEST_CODEX_HOME/pending-consume-counter"
printf '%s\n' 0 >"$pending_consume_counter"
pending_output="$({
  query_account_status() {
    printf '%s\n' "$reset_before_json"
  }
  consume_reset_credit() {
    local count
    count="$(sed -n '1p' "$pending_consume_counter")"
    printf '%s\n' "$((count + 1))" >"$pending_consume_counter"
    jq -c '. + {outcome:"reset",resetError:null}' <<<"$reset_stale_json"
  }
  CODEX_ACCOUNT_RESET_VERIFY_ATTEMPTS=2
  CODEX_ACCOUNT_RESET_VERIFY_DELAY=0
  cmd_rest pendingfixture
} 2>&1)"
assert_eq "1" "$(sed -n '1p' "$pending_consume_counter")" "pending reset consume count"
assert_contains "$pending_output" "quota refresh still pending" "pending reset status"
assert_contains "$pending_output" "do not consume another reset credit" "pending reset retry warning"

printf 'PASS: rate-limit parsing, retries, cache fallback, reset verification, error isolation, and anchor compatibility\n'
