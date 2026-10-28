# AES Open Crypt

A free, open-source macOS app for AES Crypt `.aes` files. It opens files made
by AES Crypt 3.14 and writes new files that AES Crypt can read back. No
telemetry, no network access, no password storage.

This is an independent implementation of the public
[AES Crypt stream format](https://www.aescrypt.com/aes_file_format.html), not
a wrapper around AES Crypt.

## What works

- Drag a file onto the window, or use **Open File…** (⌘O).
- `.aes` files open in decrypt mode; anything else opens in encrypt mode.
- Encrypt writes stream format 2 by default (opens in every AES Crypt
  release) or format 3 (AES Crypt 4.x and this app, stronger password
  hashing).
- Decrypt reads stream formats 0 through 3, including files made by the
  Intel-only AES Crypt 3.14.1 for Mac.
- Passwords are never written to disk. Output is written to a temporary file
  and only moved into place after the HMAC verifies, so a wrong password or a
  corrupted file leaves nothing behind.
- Existing files are never overwritten. The app picks `name (1).aes` or
  `name (1)` instead.
- Finder Services: **Encrypt with AES Open Crypt** and
  **Decrypt with AES Open Crypt**.
- Files are handled one at a time in this version.

## Build and run

Requires macOS 13 or later and Xcode 26 (Swift 6.2).

```bash
swift test
./scripts/build-app.sh
open "dist/AES Open Crypt.app"
```

`scripts/build-app.sh` builds a release binary, assembles the `.app` bundle,
copies the icon, and ad-hoc signs it. There is no Xcode project and no
third-party dependency. To rebuild the icon, run
`swift scripts/make-icon.swift` and then `iconutil`.

Because the app is ad-hoc signed, the first launch on another Mac needs
**System Settings → Privacy & Security → Open Anyway**. Signing and
notarization are not set up yet.

## Command line

The same engine ships as `aesopen` for scripts and for checking files without
the GUI.

```bash
swift build -c release
BIN=.build/release/aesopen

$BIN info secret.aes
$BIN decrypt secret.aes                  # prompts for the password
$BIN encrypt notes.txt --format v2       # writes notes.txt.aes
$BIN encrypt notes.txt --format v3 --iterations 600000
```

`--password` exists for scripting, but it is visible in the process list.
Prefer the prompt. Exit codes: `1` usage, `2` wrong password, `3` corrupt or
not an AES Crypt file, `4` unsupported format, `5` file error, `130`
cancelled.

## Compatibility

| Stream format | Read | Write |
|---|:-:|:-:|
| 0 | yes | no |
| 1 | yes | no |
| 2 | yes | yes (default) |
| 3 | yes | yes (option) |

The test suite decrypts all 84 official AES Crypt known-answer vectors (21
each for formats 0 through 3), the official format 3 sample, and fixtures
produced by the real AES Crypt 3.14 command line tool. It also encrypts with
this implementation and decrypts the result with AES Crypt 3.14 itself.

## Security notes

- AES-256 in CBC mode. Format 2 derives the key with the original AES Crypt
  construction (8192 rounds of SHA-256 over the IV and the UTF-16LE
  password); format 3 uses PBKDF2-HMAC-SHA512 with the IV as salt.
- Format 2 does not authenticate the final size-modulo-16 byte. An attacker
  with write access to a `.aes` file can change the decrypted length by up to
  15 bytes. This is part of the format, not this implementation. Use format 3
  when you control both ends.
- CBC with a random IV per file, plus a random session key wrapped under the
  password-derived key. The header and payload each carry an HMAC-SHA256.
- Temporary files are created with mode `0600` next to the destination.
  Decrypted files stay `0600`; encrypted files are `0644`.
- Input files are opened read-only and are never written to. The engine
  refuses to run when the output resolves to the same file as the input,
  including symlinks and hard links. Tests snapshot the input bytes, inode,
  permissions, timestamps, flags and extended attributes before and after
  encryption, decryption, wrong passwords, tampering and cancellation.
- The app is not sandboxed and does not use the network.

## Layout

```
Sources/AESCryptKit/     format parsing, KDF, AES-CBC, HMAC, streaming
Sources/aesopen/         command line tool
Sources/AESOpenCrypt/    SwiftUI app
Tests/AESCryptKitTests/  vectors and compatibility tests
scripts/build-app.sh     assembles dist/AES Open Crypt.app
App/Info.plist           bundle, document type, Services entries
```

## License

MIT. Not affiliated with AES Crypt or Packetizer. "AES Crypt" is the name of
the original project; this app is an independent reader and writer for its
file format.
