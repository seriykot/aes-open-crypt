<p align="center">
  <img src="docs/assets/readme-banner.png" alt="AES Open Crypt">
</p>

<p align="center">
  <img src="docs/assets/app-screenshot.png" width="800" alt="AES Open Crypt with files ready to decrypt and a matrix animation during decryption">
</p>

# AES Open Crypt

Open-source macOS app and CLI for AES Crypt `.aes` files. Reads stream formats
0–3 and writes format 3 by default or format 2 for older AES Crypt versions.
No telemetry, network access, or password storage.

## Download

[0.2.0 installer (.pkg)](https://github.com/seriykot/aes-open-crypt/releases/download/v0.2.0/AES.Open.Crypt.0.2.0.pkg) ·
[Portable app (.zip)](https://github.com/seriykot/aes-open-crypt/releases/download/v0.2.0/AES.Open.Crypt.0.2.0.zip) ·
[Checksums](https://github.com/seriykot/aes-open-crypt/releases/download/v0.2.0/SHA256SUMS.txt)

Requires macOS 13 or later; both Apple silicon and Intel are supported. The app
and CLI are ad-hoc signed; the installer is unsigned. This release is not
notarized, so Gatekeeper may warn or block launch.

## Features

- Drag or choose up to 10 files; `.aes` files are decrypted and other files encrypted.
- Finder Services and a command-line tool (`aesopen`) are included.
- Outputs never overwrite existing files; wrong passwords and corrupt files
  leave no partial output.
- Optional password hints are stored in plaintext; never put a password in one.

## Testing

- **AES Crypt versions:** 3.14 command-line tool and 4.7.0. Cross-checks cover
  format 2 with 3.14, and formats 2 and 3 with 4.7.0.
- **Fixtures:** 84 known-answer vectors (21 per stream format 0–3), the
  official format 3 `hello_world.txt` sample, and `.aes` files produced by
  AES Crypt 3.14.
- **Real-world files:** encrypted and decrypted 11 local files, with exact
  matches and originals unchanged: 1 DOC, 2 DOCX, 3 PDF, 1 JPG, 1 RTF,
  2 ZIP, and 1 MP4. Private filenames and file contents are not published.
- `swift test` passes 97 tests.

## Build

Requires Xcode 26 and Swift 6.2.

```bash
swift test
./scripts/build-app.sh
./scripts/build-pkg.sh
```

## License

MIT. Independent of AES Crypt and Packetizer.
