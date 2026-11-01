# Fixture sources

- `v2-*.aes` were produced by the AES Crypt 3.14 command line tool bundled in
  `/Applications/AESCrypt.app` (September 2018 build).
- `v3-test-data.aes` was generated with AES Open Crypt from
  `AES Open Crypt test fixture.\n`, password `apples`.
- `vectors/v0.json` through `vectors/v3.json` are the 84 AES Crypt
  known-answer vectors from https://github.com/Slurp9187/aescrypt-rs
  (MIT, see `vectors/LICENSE-MIT-aescrypt-rs`), password `Hello`.
