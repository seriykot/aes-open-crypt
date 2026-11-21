import AESCryptKit

/// The `--help` text, and the tail of every usage error.
///
/// It is the one place the command line documents its options, exit codes,
/// and JSON schema, so `scripts/test-cli.sh` greps this exact string. Keep the
/// tokens and the line breaks.
public let usageText = """
aesopen - AES Crypt compatible encryption

Usage:
  aesopen encrypt [options] <file>...
  aesopen decrypt [options] <file>...
  aesopen info [options] <file>...
  aesopen --help
  aesopen --version

Files:
  Up to 10 input files per run, counted after duplicates are removed. An
  eleventh file is an error (exit 1); files are never silently dropped. One
  password applies to the whole batch.

Default output names:
  encrypt  <file>       -> <file>.aes
  decrypt  <file>.aes   -> <file>
  decrypt  <file>       -> <file>.decrypted
  Existing files are never overwritten. Use -o to choose an exact output path;
  -o is valid only with a single input file.

Options:
  -o, --output <path>     Exact output path. Single input only. Default: above.
  --format <v2|v3>        Output stream format. Default: v3.
  --hint <text>           Plaintext password hint. Encrypt only, up to 256
                          characters. Default: none.
  --iterations <n>        KDF iterations for v3. Default: 600000.
  --password <password>   Password on the command line. Visible in process
                          lists and shell history. Default: prompt.
  --password-file <path>  Read the password from the first line of <path>.
                          Use - for stdin. Prevents all prompts. Default: none.
  --json                  JSON on stdout. Suppresses progress. Default: off.
  --quiet                 Suppress progress. Output paths are still printed.
                          Default: off.
  -v, --version           Print the version and exit.
  -h, --help              Print this help and exit.

Examples:
  aesopen encrypt report.pdf notes.txt
  aesopen decrypt --password-file ~/.aesopen-password secret.aes
  aesopen info --json backup.aes | python3 -m json.tool

Exit codes:
  0    Every file succeeded.
  1    Usage error, or more than 10 input files.
  2    Wrong password.
  3    Corrupt file, not an AES Crypt file, or a file that does not match the
       requested direction.
  4    Unsupported AES Crypt stream version.
  5    File error, existing output, or input and output are the same file.
  130  Cancelled.
  When a batch has several failures, the first matching code in the order
  130, 2, 3, 4, 5 is returned.

JSON schema:
  {
    "version": "\(AESOpenVersion.current)",
    "command": "encrypt",
    "results": [
      {"input": "/abs/a.txt", "output": "/abs/a.txt.aes", "mode": "encrypt",
       "status": "ok", "error": null},
      {"input": "/abs/b.aes", "output": null, "mode": "decrypt",
       "status": "error",
       "error": {"code": 2, "kind": "wrongPassword", "message": "Wrong password."}}
    ]
  }
  "command" is encrypt, decrypt, or info. info results also carry "format",
  "size", "ciphertext", "kdfIterations", "hint", and "extensions". Error codes
  match the exit-code table.

Security:
  Passwords passed with --password appear in process lists and shell history.
  Prefer the interactive prompt or --password-file with a file readable only
  by you. aesopen never stores, logs, or transmits passwords. Password hints
  are stored as plaintext extensions in the file and are not authenticated;
  anyone can read or change them without the password.
"""
