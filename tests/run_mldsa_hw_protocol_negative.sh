#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TKEY_SIGN_BIN_DEFAULT="${REPO_ROOT}/../tkey-sign-cli-pq/tkey-sign-pq"
TKEY_SIGN_BIN="${TKEY_SIGN_BIN:-${TKEY_SIGN_BIN_DEFAULT}}"

PORT="${PORT:-}"
SPEED="${SPEED:-}"
KEEP_WORKDIR="${KEEP_WORKDIR:-0}"
FAILED_STATE_RETRIES="${FAILED_STATE_RETRIES:-3}"

START_EPOCH="$(date +%s)"
START_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RESULT_DIR_DEFAULT="${REPO_ROOT}/tests/results"
RESULT_JSON="${RESULT_JSON:-${RESULT_DIR_DEFAULT}/mldsa_hw_protocol_negative_$(date -u +%Y%m%dT%H%M%SZ).json}"

RUN_STATUS="failed"
FAIL_REASON=""
cases_passed=0
failed_state_checks=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Destructive protocol-state negative tests for TKey ML-DSA signer.
These tests intentionally trigger protocol errors that move the app to failed
state. Power-cycle is required between cases.

Options:
  --bin PATH         Path to tkey-sign-pq binary
  --port DEV         Serial device passed to tkey-sign-pq (-d)
  --speed BAUD       Serial speed passed to tkey-sign-pq (-s)
  --failed-retries N Number of repeated getkey failures to confirm failed state (default: ${FAILED_STATE_RETRIES})
  --result-json PATH Output JSON result path (default: ${RESULT_JSON})
  --keep-workdir     Keep temporary test directory
  --help             Show this help

Environment overrides:
  TKEY_SIGN_BIN, PORT, SPEED, KEEP_WORKDIR, FAILED_STATE_RETRIES, RESULT_JSON
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      TKEY_SIGN_BIN="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --speed)
      SPEED="$2"
      shift 2
      ;;
    --failed-retries)
      FAILED_STATE_RETRIES="$2"
      shift 2
      ;;
    --result-json)
      RESULT_JSON="$2"
      shift 2
      ;;
    --keep-workdir)
      KEEP_WORKDIR=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ ! -x "${TKEY_SIGN_BIN}" ]]; then
  echo "tkey-sign-pq binary not found or not executable: ${TKEY_SIGN_BIN}" >&2
  echo "Build it first in ../tkey-sign-cli-pq using: make" >&2
  exit 1
fi

if ! [[ "${FAILED_STATE_RETRIES}" =~ ^[0-9]+$ ]]; then
  echo "FAILED_STATE_RETRIES must be a non-negative integer, got: ${FAILED_STATE_RETRIES}" >&2
  exit 1
fi

if [[ "${FAILED_STATE_RETRIES}" -eq 0 ]]; then
  echo "FAILED_STATE_RETRIES must be >= 1" >&2
  exit 1
fi

result_dir="$(dirname "${RESULT_JSON}")"
mkdir -p "${result_dir}"

workdir="$(mktemp -d -t tkey-mldsa-proto-neg-XXXXXX)"
key_file="${workdir}/key.pub"

cleanup() {
  local exit_code=$?

  write_result "${exit_code}"

  if [[ "${KEEP_WORKDIR}" == "1" ]]; then
    echo "Keeping workdir: ${workdir}"
    return "${exit_code}"
  fi
  rm -rf "${workdir}"

  return "${exit_code}"
}
trap cleanup EXIT

SIGN_ARGS=()
if [[ -n "${PORT}" ]]; then
  SIGN_ARGS+=("-d" "${PORT}")
fi
if [[ -n "${SPEED}" ]]; then
  SIGN_ARGS+=("-s" "${SPEED}")
fi

log() {
  echo "[INFO] $*"
}

pass() {
  echo "[PASS] $*"
}

fail() {
  FAIL_REASON="$*"
  echo "[FAIL] $*" >&2
  exit 1
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

write_result() {
  local exit_code="$1"
  local end_epoch
  local end_ts
  local duration_sec
  local status
  local fail_reason_json

  end_epoch="$(date +%s)"
  end_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  duration_sec=$(( end_epoch - START_EPOCH ))

  if [[ "${exit_code}" -eq 0 ]]; then
    status="passed"
  else
    status="failed"
  fi

  fail_reason_json="$(json_escape "${FAIL_REASON}")"

  cat > "${RESULT_JSON}" <<EOF
{
  "suite": "mldsa-hw-protocol-negative",
  "status": "${status}",
  "start_utc": "${START_TS}",
  "end_utc": "${end_ts}",
  "duration_sec": ${duration_sec},
  "config": {
    "binary": "$(json_escape "${TKEY_SIGN_BIN}")",
    "port": "$(json_escape "${PORT}")",
    "speed": "$(json_escape "${SPEED}")",
    "failed_state_retries": ${FAILED_STATE_RETRIES}
  },
  "counts": {
    "destructive_cases_passed": ${cases_passed},
    "failed_state_checks": ${failed_state_checks}
  },
  "artifacts": {
    "result_json": "$(json_escape "${RESULT_JSON}")",
    "workdir": "$(json_escape "${workdir}")"
  },
  "failure_reason": "${fail_reason_json}"
}
EOF
}

expect_cmd_fail() {
  set +e
  "$@" >/dev/null 2>&1
  local rc=$?
  set -e
  if [[ ${rc} -eq 0 ]]; then
    fail "command unexpectedly succeeded: $*"
  fi
}

expect_getkey_ok() {
  "${TKEY_SIGN_BIN}" "${SIGN_ARGS[@]}" -G -f -p "${key_file}" >/dev/null
}

expect_getkey_fail() {
  expect_cmd_fail "${TKEY_SIGN_BIN}" "${SIGN_ARGS[@]}" -G -f -p "${key_file}"
}

assert_failed_state_persistent() {
  local i
  for ((i=1; i<=FAILED_STATE_RETRIES; i++)); do
    expect_getkey_fail
    failed_state_checks=$(( failed_state_checks + 1 ))
  done
  pass "failed state persisted for ${FAILED_STATE_RETRIES} repeated getkey attempts"
}

wait_for_power_cycle() {
  echo
  echo "Power-cycle required: unplug and replug TKey now."
  read -r -p "Press Enter after reconnect to continue... " _
}

run_case_empty_message() {
  local msg_file="${workdir}/empty.msg"
  : > "${msg_file}"

  log "Case 1: sign empty message (size=0) should fail and force failed state"
  expect_cmd_fail "${TKEY_SIGN_BIN}" "${SIGN_ARGS[@]}" -S -f -m "${msg_file}" -p "${key_file}" -x "${workdir}/empty.sig"
  pass "empty message sign rejected"

  assert_failed_state_persistent
  cases_passed=$(( cases_passed + 1 ))
}

run_case_oversize_message() {
  local msg_file="${workdir}/oversize.msg"
  head -c 4097 /dev/urandom > "${msg_file}"

  log "Case 2: sign oversize message (size>4096) should fail and force failed state"
  expect_cmd_fail "${TKEY_SIGN_BIN}" "${SIGN_ARGS[@]}" -S -f -m "${msg_file}" -p "${key_file}" -x "${workdir}/oversize.sig"
  pass "oversize message sign rejected"

  assert_failed_state_persistent
  cases_passed=$(( cases_passed + 1 ))
}

log "Pre-check: ensure signer app responds before running destructive tests"
expect_getkey_ok
pass "baseline getkey succeeded"

run_case_empty_message
wait_for_power_cycle

log "Re-check after power cycle"
expect_getkey_ok
pass "getkey succeeded after power cycle"

run_case_oversize_message
wait_for_power_cycle

log "Final re-check after power cycle"
expect_getkey_ok
pass "getkey succeeded after final power cycle"

echo
echo "All destructive protocol negative checks passed."
echo "Workdir: ${workdir}"
echo "Result JSON: ${RESULT_JSON}"