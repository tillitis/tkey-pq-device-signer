#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TKEY_SIGN_BIN_DEFAULT="${REPO_ROOT}/../tkey-sign-cli-pq/tkey-sign-pq"
TKEY_SIGN_BIN="${TKEY_SIGN_BIN:-${TKEY_SIGN_BIN_DEFAULT}}"

PORT="${PORT:-}"
SPEED="${SPEED:-}"
RANDOM_CASES="${RANDOM_CASES:-100}"
STRESS_CASES="${STRESS_CASES:-1000}"
RUN_STRESS="${RUN_STRESS:-1}"
KEEP_WORKDIR="${KEEP_WORKDIR:-0}"

START_EPOCH="$(date +%s)"
START_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RESULT_DIR_DEFAULT="${REPO_ROOT}/tests/results"
RESULT_JSON="${RESULT_JSON:-${RESULT_DIR_DEFAULT}/mldsa_hw_local_$(date -u +%Y%m%dT%H%M%SZ).json}"

signed_verify_cases=0
negative_checks=0
stress_passed=0
RUN_STATUS="failed"
FAIL_REASON=""

BOUNDARY_SIZES=(1 2 31 32 33 126 127 128 129 255 256 257 4095 4096)

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Local ML-DSA hardware validation for TKey signer.

Options:
  --bin PATH           Path to tkey-sign-pq binary
  --port DEV           Serial device passed to tkey-sign-pq (-d)
  --speed BAUD         Serial speed passed to tkey-sign-pq (-s)
  --random N           Number of random-size sign/verify cases (default: ${RANDOM_CASES})
  --stress N           Number of stress sign/verify cases (default: ${STRESS_CASES})
  --result-json PATH   Output JSON result path (default: ${RESULT_JSON})
  --skip-stress        Skip stress phase
  --keep-workdir       Keep temporary test directory
  --help               Show this help

Environment overrides:
  TKEY_SIGN_BIN, PORT, SPEED, RANDOM_CASES, STRESS_CASES, RUN_STRESS, KEEP_WORKDIR, RESULT_JSON

Notes:
  - Touch confirmation may be required on each signature depending on firmware build.
  - This script validates signatures by verification, not signature byte equality.
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
    --random)
      RANDOM_CASES="$2"
      shift 2
      ;;
    --stress)
      STRESS_CASES="$2"
      shift 2
      ;;
    --result-json)
      RESULT_JSON="$2"
      shift 2
      ;;
    --skip-stress)
      RUN_STRESS=0
      shift
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

if ! command -v base64 >/dev/null 2>&1; then
  echo "Missing required command: base64" >&2
  exit 1
fi

if ! command -v od >/dev/null 2>&1; then
  echo "Missing required command: od" >&2
  exit 1
fi

result_dir="$(dirname "${RESULT_JSON}")"
mkdir -p "${result_dir}"

workdir="$(mktemp -d -t tkey-mldsa-hw-XXXXXX)"
pubkey_file="${workdir}/key.pub"

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

fail() {
  FAIL_REASON="$*"
  echo "[FAIL] $*" >&2
  exit 1
}

log() {
  echo "[INFO] $*"
}

pass() {
  echo "[PASS] $*"
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
  local stress_enabled

  end_epoch="$(date +%s)"
  end_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  duration_sec=$(( end_epoch - START_EPOCH ))

  if [[ "${exit_code}" -eq 0 ]]; then
    status="passed"
  else
    status="failed"
  fi

  fail_reason_json="$(json_escape "${FAIL_REASON}")"
  stress_enabled="false"
  if [[ "${RUN_STRESS}" == "1" ]]; then
    stress_enabled="true"
  fi

  cat > "${RESULT_JSON}" <<EOF
{
  "suite": "mldsa-hw-local",
  "status": "${status}",
  "start_utc": "${START_TS}",
  "end_utc": "${end_ts}",
  "duration_sec": ${duration_sec},
  "config": {
    "binary": "$(json_escape "${TKEY_SIGN_BIN}")",
    "port": "$(json_escape "${PORT}")",
    "speed": "$(json_escape "${SPEED}")",
    "random_cases": ${RANDOM_CASES},
    "stress_cases": ${STRESS_CASES},
    "run_stress": ${stress_enabled}
  },
  "counts": {
    "boundary_cases": ${#BOUNDARY_SIZES[@]},
    "random_cases": ${RANDOM_CASES},
    "signed_verify_cases": ${signed_verify_cases},
    "negative_verification_checks": ${negative_checks},
    "stress_cases_passed": ${stress_passed}
  },
  "artifacts": {
    "result_json": "$(json_escape "${RESULT_JSON}")",
    "workdir": "$(json_escape "${workdir}")"
  },
  "failure_reason": "${fail_reason_json}"
}
EOF
}

flip_first_byte_in_file() {
  local file="$1"
  local first
  local flipped

  first="$(od -An -t u1 -N1 "${file}" | tr -d ' ')"
  if [[ -z "${first}" ]]; then
    fail "cannot flip first byte in empty file: ${file}"
  fi

  flipped=$(( first ^ 1 ))
  printf "\\$(printf '%03o' "${flipped}")" | dd of="${file}" bs=1 seek=0 conv=notrunc status=none
}

tamper_signature_file() {
  local sig_file="$1"
  local raw_file="${workdir}/sig.raw"
  local b64_file="${workdir}/sig.b64"
  local comment
  local first flipped

  comment="$(sed -n '1p' "${sig_file}")"
  sed -n '2p' "${sig_file}" | base64 -d > "${raw_file}"

  # The raw binary layout is Alg[2] + KeyNum[8] + Sig[...].
  # verifySignature only checks the Sig field, so we must flip a byte
  # inside Sig (offset 10) rather than in the ignored header.
  local sig_offset=10
  first="$(od -An -t u1 -N1 -j "${sig_offset}" "${raw_file}" | tr -d ' ')"
  if [[ -z "${first}" ]]; then
    fail "cannot flip byte in signature file: ${raw_file}"
  fi
  flipped=$(( first ^ 0xFF ))
  printf "\\$(printf '%03o' "${flipped}")" | dd of="${raw_file}" bs=1 seek="${sig_offset}" conv=notrunc status=none

  base64 -w0 "${raw_file}" > "${b64_file}"

  {
    echo "${comment}"
    cat "${b64_file}"
    echo
  } > "${sig_file}"
}

expect_verify_fail() {
  local msg_file="$1"
  local sig_file="$2"
  local context="$3"

  set +e
  "${TKEY_SIGN_BIN}" -V -m "${msg_file}" -p "${pubkey_file}" -x "${sig_file}" >/dev/null 2>&1
  local rc=$?
  set -e

  if [[ ${rc} -eq 0 ]]; then
    fail "verify unexpectedly succeeded (${context})"
  fi
  pass "verify failed as expected (${context})"
}

run_case() {
  local case_name="$1"
  local msg_size="$2"

  local msg_file="${workdir}/${case_name}.msg"
  local sig_file="${workdir}/${case_name}.sig"
  local bad_msg_file="${workdir}/${case_name}.msg.bad"
  local bad_sig_file="${workdir}/${case_name}.sig.bad"

  head -c "${msg_size}" /dev/urandom > "${msg_file}"

  "${TKEY_SIGN_BIN}" "${SIGN_ARGS[@]}" -S -f -m "${msg_file}" -p "${pubkey_file}" -x "${sig_file}" >/dev/null
  "${TKEY_SIGN_BIN}" -V -m "${msg_file}" -p "${pubkey_file}" -x "${sig_file}" >/dev/null

  cp "${msg_file}" "${bad_msg_file}"
  flip_first_byte_in_file "${bad_msg_file}"
  expect_verify_fail "${bad_msg_file}" "${sig_file}" "tampered message"
  negative_checks=$(( negative_checks + 1 ))

  cp "${sig_file}" "${bad_sig_file}"
  tamper_signature_file "${bad_sig_file}"
  expect_verify_fail "${msg_file}" "${bad_sig_file}" "tampered signature"
  negative_checks=$(( negative_checks + 1 ))

  signed_verify_cases=$(( signed_verify_cases + 1 ))
  pass "${case_name} (size=${msg_size})"
}

log "Fetching public key from device"
"${TKEY_SIGN_BIN}" "${SIGN_ARGS[@]}" -G -f -p "${pubkey_file}" >/dev/null
pass "public key retrieval"

log "Running boundary-size cases"
for size in "${BOUNDARY_SIZES[@]}"; do
  run_case "boundary_${size}" "${size}"
done

log "Running ${RANDOM_CASES} random-size cases"
for ((i=1; i<=RANDOM_CASES; i++)); do
  size=$(( (RANDOM % 4096) + 1 ))
  run_case "random_${i}" "${size}"
done

if [[ "${RUN_STRESS}" == "1" ]]; then
  log "Running stress loop (${STRESS_CASES} cases)"
  for ((i=1; i<=STRESS_CASES; i++)); do
    size=$(( (RANDOM % 4096) + 1 ))
    msg_file="${workdir}/stress_${i}.msg"
    sig_file="${workdir}/stress_${i}.sig"

    head -c "${size}" /dev/urandom > "${msg_file}"
    "${TKEY_SIGN_BIN}" "${SIGN_ARGS[@]}" -S -f -m "${msg_file}" -p "${pubkey_file}" -x "${sig_file}" >/dev/null
    "${TKEY_SIGN_BIN}" -V -m "${msg_file}" -p "${pubkey_file}" -x "${sig_file}" >/dev/null
    signed_verify_cases=$(( signed_verify_cases + 1 ))
    stress_passed=$(( stress_passed + 1 ))

    if (( i % 100 == 0 )); then
      pass "stress progress: ${i}/${STRESS_CASES}"
    fi
  done
fi

echo
echo "All hardware ML-DSA checks passed."
echo "Workdir: ${workdir}"
echo "Result JSON: ${RESULT_JSON}"