# Fixture sources

- `v2-*.aes` were produced by the AES Crypt 3.14 command line tool bundled in
  `/Applications/AESCrypt.app` (September 2018 build).
- `v3-hello.aes` is the official AES Crypt stream format 3 sample from
  https://www.aescrypt.com/hello_world.txt, decoded from its hex dump.
  Password `apples`, plaintext `Hello, World!\n`.
- `vectors/v0.json` through `vectors/v3.json` are the 84 AES Crypt
  known-answer vectors from https://github.com/Slurp9187/aescrypt-rs
  (MIT, see `vectors/LICENSE-MIT-aescrypt-rs`), password `Hello`.
