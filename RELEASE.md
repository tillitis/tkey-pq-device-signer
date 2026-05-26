# Release notes

## v1.0.0

Migrated from https://github.com/tillitis/tkey-device-signer and renamed to tkey-device-pqsigner

- Upgraded signing algorithm to [ML-DSA-44](https://csrc.nist.gov/pubs/fips/204/final)
  (post-quantum signature scheme, FIPS 204) (uses MLDSA-pure)
- Uses library [mldsa-native](https://github.com/pq-code-package/mldsa-native/tree/v1.0.0-beta) library
- Implemented functions for random number generation for mldsa-native library
