# aes-open-crypt

A free, open-source macOS app for encrypting and decrypting AES Crypt `.aes`
files. Reads stream formats 0 through 3 and writes formats 2 and 3.

Status: core library and CLI under construction. The Mac app follows.

## Why

AES Crypt for Mac 3.14.1 is an Intel-only app that runs under Rosetta. This
project opens the same files and writes new ones that AES Crypt can read.

## Compatibility

| Stream format | Read | Write |
|---|:-:|:-:|
| 0 | yes | no |
| 1 | yes | no |
| 2 | yes | yes (default) |
| 3 | yes | yes (option) |

Format 2 opens in every AES Crypt release. Format 3 needs AES Crypt 4.x or
this project.

## Build

```bash
swift build
swift test
```

The CLI lands in `.build/debug/aesopen`.

## Security notes

Format 2 does not authenticate the final size-modulo-16 byte. An attacker with
write access to a `.aes` file can change the decrypted length by up to 15
bytes. This is part of the format, not this implementation. Use format 3 when
you control both ends.

## License

MIT. Not affiliated with AES Crypt or Packetizer.
