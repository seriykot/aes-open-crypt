# AES Open Crypt

A free, open-source macOS app for AES Crypt `.aes` files. It opens files made
by AES Crypt 3.14 and writes new files that AES Crypt can read back. No
telemetry, no network access, no password storage.

This is an independent implementation of the public
[AES Crypt stream format](https://www.aescrypt.com/aes_file_format.html), not
a wrapper around AES Crypt.

## Install

Download `AES Open Crypt 0.2.0.pkg` and open it. The installer puts the app in
`/Applications` and links the command line tool at `/usr/local/bin/aesopen`, so
`aesopen --help` works in Terminal right away.

The `.zip` is the portable option: drag the app to Applications. It cannot
run an install script, so on first launch it tries to create the same link
when `/usr/local/bin` is writable; otherwise it shows the exact command to
run. **AES Open Crypt → Repair Command Line Tool** fixes the link after the
app moves, and `scripts/install-cli.sh` does the same from a checkout.

The app is ad-hoc signed and not notarized, and the package is unsigned
because no Developer ID identity is available. On another Mac, right-click
the app and choose **Open** (or use **System Settings → Privacy & Security →
Open Anyway**). If Gatekeeper blocks the package, right-click it and choose
**Open**, or run:

```bash
sudo installer -pkg "AES Open Crypt 0.2.0.pkg" -target /
```

## What works

- Drag up to 10 files onto the window, or use **Open File…** (⌘O).
- `.aes` files open in decrypt mode; anything else opens in encrypt mode. A
  mixed drop asks whether to encrypt or decrypt the whole batch.
- Finder Services open the same password window. Window drops accept regular
  files only; folders and document packages such as `.rtfd` are rejected. Zip
  a package first to encrypt it.
- One password per batch. Every row reports its own result; if a row fails,
  fix the password and retry only the failed rows.
- The app writes stream format 3 by default (AES Crypt 4.x and this app,
  stronger password hashing) or format 2 (opens in every AES Crypt release).
  The picker remembers your last choice.
- Weak passwords (under 8 characters, or no uppercase letter and no symbol)
  show an amber suggestion under the password field. It never blocks
  encryption.
- Optional password hints. A hint is stored as a plaintext extension tag and
  is shown before the password is entered. Anyone with the file can read or
  change it; never put the password in a hint.
- While a batch runs, a matrix-style overlay covers the file area. It stays for
  at least 1 second and never blocks Cancel.
- Decrypt reads stream formats 0 through 3, including files made by the
  Intel-only AES Crypt 3.14.1 for Mac.
- Passwords are never written to disk. Output is written to a temporary file
  and only moved into place after the HMAC verifies, so a wrong password or a
  corrupted file leaves nothing behind.
- Existing files are never overwritten. The app picks `name (1).aes` or
  `name (1)` instead.
- Finder Services: **Encrypt with AES Open Crypt** and
  **Decrypt with AES Open Crypt**.

## Work in progress

- **Dock drag-and-drop.** Dropping files on the Dock icon goes through the same
  open event as `open -a`, but the Dock path has not been verified on a real
  desktop. It is experimental: window drops and Finder Services are the
  supported paths for 0.2.0.

## Build and run

Requires macOS 13 or later and Xcode 26 (Swift 6.2).

```bash
swift test
./scripts/build-app.sh
open "dist/AES Open Crypt.app"

./scripts/build-pkg.sh   # dist/AES Open Crypt <version>.pkg
```

`scripts/build-app.sh` builds release binaries, embeds `aesopen` at
`Contents/Resources/bin/aesopen`, assembles the `.app` bundle, copies the
icon, and ad-hoc signs the CLI and the app. It builds a universal binary
(`arm64` + `x86_64`) by default; set `UNIVERSAL=0` for a host-only build.
`scripts/build-pkg.sh` wraps the app in an installer package. There is no Xcode project and no third-party
dependency. To rebuild the icon, run `swift scripts/make-icon.swift` and then
`iconutil`.

The manual release checks that need a real desktop or a disposable macOS
system are in [docs/manual-checks.md](docs/manual-checks.md).

## Command line

The same engine ships as `aesopen` for scripts and for checking files without
the GUI.

```bash
BIN="dist/AES Open Crypt.app/Contents/Resources/bin/aesopen"

$BIN --help
$BIN encrypt notes.txt report.pdf        # writes notes.txt.aes and report.pdf.aes
$BIN decrypt --password-file ~/.aesopen-password secret.aes
$BIN info --json backup.aes | python3 -m json.tool
```

`$BIN --help` lists every option, the default output names, the exit-code
table, and the full JSON schema. Encryption defaults to stream format 3; pass
`--format v2` when the file must open in AES Crypt 3.x or older. One run
handles up to 10 files with one password. `--password-file` reads the first
line of a file (`-` for stdin) and prevents every prompt. `--json` prints a
machine-readable result for each file:

```json
{"version":"0.2.0","command":"encrypt","results":[
  {"input":"/abs/notes.txt","output":"/abs/notes.txt.aes","mode":"encrypt",
   "status":"ok","error":null}
]}
```

`--hint "text"` writes an optional plaintext hint during encryption. `aesopen
info` prints it, and `info --json` includes a `hint` field. The hint is not
encrypted or authenticated.

`--password` exists for scripting, but it is visible in the process list and
shell history. Prefer the prompt or the password file. Exit codes: `1` usage
or more than 10 files, `2` wrong password, `3` corrupt or not an AES Crypt
file, `4` unsupported format, `5` file error or existing output, `130`
cancelled.

## Compatibility

| Stream format | Read | Write |
|---|:-:|:-:|
| 0 | yes | no |
| 1 | yes | no |
| 2 | yes | yes (option) |
| 3 | yes | yes (default) |

The test suite decrypts all 84 official AES Crypt known-answer vectors (21
each for formats 0 through 3), the official format 3 sample, and fixtures
produced by the real AES Crypt 3.14 command line tool. It also encrypts with
this implementation and decrypts the result with AES Crypt 3.14 itself.
Manual cross-checks with AES Crypt 4.7.0 cover both directions: 4.7.0 reads
this app's format 2 and 3 output, and this app reads 4.7.0's format 3
output, including non-ASCII passwords and non-default KDF iteration counts.
Password hints use a URI extension tag; AES Crypt 3.14 and 4.x ignore it and
still decrypt the file.

## Security notes

- AES-256 in CBC mode. Format 2 derives the key with the original AES Crypt
  construction (8192 rounds of SHA-256 over the IV and the UTF-16LE
  password); format 3 uses PBKDF2-HMAC-SHA512 with the IV as salt.
- Format 2 does not authenticate the final size-modulo-16 byte. An attacker
  with write access to a `.aes` file can change the decrypted length by up to
  15 bytes; this is inherent to the format and cannot be fixed compatibly.
  Use format 3 when you control both ends. A regression test demonstrates the
  behavior using a disposable copy of a fixture.
- CBC with a random IV per file, plus a random session key wrapped under the
  password-derived key. The header and payload each carry an HMAC-SHA256.
- Password hints are plaintext extension tags. They are neither encrypted nor
  authenticated, so anyone can read or change them without the password.
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
