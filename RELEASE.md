# Release notes

## v1.0.0

Migrated from https://github.com/tillitis/tkey-device-signer and renamed to tkey-device-pqsigner

- Upgraded signing algorithm to [ML-DSA-44](https://csrc.nist.gov/pubs/fips/204/final)
  (post-quantum signature scheme, FIPS 204) (uses MLDSA-pure)
- Uses library [mldsa-native](https://github.com/pq-code-package/mldsa-native/tree/v1.0.0-beta) library
- Implemented functions for random number generation for mldsa-native library to support "hedged"-signing. [MLDSA Draft](https://www.ietf.org/archive/id/draft-connolly-cfrg-ml-dsa-security-considerations-01.html#section-2.2.1-1)
- Implemented use of external mu computation instead of internal by the signer function itself for optimization. [MLDSA Draft](https://www.ietf.org/archive/id/draft-connolly-cfrg-ml-dsa-security-considerations-01.html#name-external-mu)
  - Optimizes time for signing
  - Less RAM usage
  - Files of any size can be signed as the MU value is done externally in the client app
  - Uses MLDSA-pure over Hash-MLDSA
