# Hardware ML-DSA Local Tests

This folder contains a local hardware validation harness for the TKey ML-DSA signer.

The goal is to verify end-to-end behavior on real hardware:

- Public key retrieval from device
- Sign and verify across boundary message sizes
- Randomized sign and verify runs
- Negative verification checks (tampered message and tampered signature)
- Long-running stress loops

## Prerequisites

1. Build the signer app in this repository.
2. Build the host CLI in the neighboring repository:

   cd ../tkey-sign-cli-pq
   make

3. Connect a TKey device.

Depending on firmware build flags, touch confirmation may be required for every signature operation.

## Run

From this repository root:

make test-hw-mldsa

Optional direct invocation:

bash tests/run_mldsa_hw_local.sh --port /dev/ttyACM0 --speed 62500

Result artifact:

- By default, a timestamped JSON file is written to tests/results/
- Override output path with --result-json PATH

## Destructive protocol negative tests

There is a separate script for protocol/state-machine negative checks that
intentionally put the signer into failed state.

From repository root:

make test-hw-mldsa-protocol-negative

or directly:

bash tests/run_mldsa_hw_protocol_negative.sh --port /dev/ttyACM0 --speed 62500

What it does:

- Attempts to sign an empty message (size 0), expects rejection
- Attempts to sign an oversize message (>4096), expects rejection
- Verifies the signer no longer responds until power-cycle (repeated getkey attempts)
- Prompts you to unplug/replug between destructive cases

Useful option for this script:

- --failed-retries N
- --result-json PATH

Example:

bash tests/run_mldsa_hw_protocol_negative.sh --failed-retries 5

Result artifact:

- By default, a timestamped JSON file is written to tests/results/
- Override output path with --result-json PATH

Use this script when you want to validate failed-state behavior and recovery,
not for normal fast sign/verify coverage.

## Useful options

- --random N
- --stress N
- --skip-stress
- --keep-workdir
- --bin /path/to/tkey-sign-pq
- --result-json /tmp/mldsa-local-result.json

Example quick run:

bash tests/run_mldsa_hw_local.sh --random 20 --stress 100

Example with explicit result path:

bash tests/run_mldsa_hw_local.sh --random 20 --stress 100 --result-json /tmp/mldsa-local-result.json

## Expected behavior

- Valid signatures always verify successfully.
- Tampered messages and signatures always fail verification.
- Results are judged by verification correctness, not byte-identical signatures.

ML-DSA signing is randomized, so signature bytes are expected to differ between runs.

## Scope and limits

This harness covers practical end-to-end hardware correctness. It does not implement a full ACVP-on-device harness.

For algorithm conformance vectors, keep using:

cd mldsa-native
make run_acvp
