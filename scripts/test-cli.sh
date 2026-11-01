#!/bin/bash
# Exercise the aesopen command line against a real release build.
# Optional cross-checks:
#   AESCRYPT314=/path/to/aescrypt   (3.14 reads format 2 only)
#   AESCRYPT4=/path/to/aescrypt     (4.x reads formats 2 and 3)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> building aesopen (release)"
swift build -c release --product aesopen >/dev/null
BIN="$(swift build -c release --show-bin-path)/aesopen"
[ -x "$BIN" ] || { echo "FAIL: missing $BIN" >&2; exit 1; }

WORK_BASE="${TMPDIR:-/tmp}"
WORK_BASE="${WORK_BASE%/}"
WORK="$(mktemp -d "$WORK_BASE/aesopen-cli-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
PW='correct horse battery staple'

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

ok() {
    PASS=$((PASS + 1))
    echo "ok $PASS: $*"
}

# run_expect <exit code> <command...>
run_expect() {
    local expected="$1"
    shift
    set +e
    "$@" >"$WORK/stdout" 2>"$WORK/stderr"
    local code=$?
    set -e
    if [ "$code" -ne "$expected" ]; then
        echo "--- stderr ---" >&2
        cat "$WORK/stderr" >&2
        fail "expected exit $expected, got $code: $*"
    fi
}

# ---------------------------------------------------------------- help/version

HELP="$("$BIN" --help)"
for token in \
    'encrypt' 'decrypt' 'info' '--output' '--format' '--iterations' \
    '--password-file' '--password' '--json' '--quiet' '--version' '--help' \
    '--hint' '10' 'Exit codes' 'JSON schema' 'process lists' 'Default: v3' \
    '0    Every file succeeded.' '1    Usage error' '2    Wrong password' \
    '3    Corrupt' '4    Unsupported' '5    File error' '130  Cancelled.'; do
    grep -q -- "$token" <<<"$HELP" || fail "help is missing '$token'"
done
grep -q '600000' <<<"$HELP" || fail "help is missing the default iteration count"
ok "help lists commands, options, limits, exit codes, and JSON schema"

VERSION="$("$BIN" --version)"
[ "$VERSION" = "aesopen 0.2.0" ] || fail "--version printed '$VERSION'"
ok "--version prints 0.2.0"

# ------------------------------------------------------------- batch round trip

mkdir -p "$WORK/round" "$WORK/round/decrypted"
printf 'alpha\n' >"$WORK/round/a.txt"
printf 'bravo\n' >"$WORK/round/b.txt"
printf 'charlie\n' >"$WORK/round/c.txt"
BEFORE="$(cd "$WORK/round" && shasum -a 256 a.txt b.txt c.txt)"

run_expect 0 "$BIN" encrypt --password "$PW" \
    "$WORK/round/a.txt" "$WORK/round/b.txt" "$WORK/round/c.txt"
[ "$(wc -l <"$WORK/stdout" | tr -d ' ')" -eq 3 ] || fail "encrypt did not print three output paths"
for name in a b c; do
    [ -f "$WORK/round/$name.txt.aes" ] || fail "missing $name.txt.aes"
    cp "$WORK/round/$name.txt.aes" "$WORK/round/decrypted/$name.aes"
done

run_expect 0 "$BIN" decrypt --password "$PW" \
    "$WORK/round/decrypted/a.aes" "$WORK/round/decrypted/b.aes" "$WORK/round/decrypted/c.aes"
for name in a b c; do
    cmp "$WORK/round/$name.txt" "$WORK/round/decrypted/$name" || fail "$name did not round trip"
done
AFTER="$(cd "$WORK/round" && shasum -a 256 a.txt b.txt c.txt)"
[ "$BEFORE" = "$AFTER" ] || fail "input files changed during the batch"
ok "three-file encrypt/decrypt round trip leaves inputs byte-identical"

# ---------------------------------------------------------------- file limit

mkdir -p "$WORK/eleven"
for i in $(seq 1 11); do
    printf 'file %s\n' "$i" >"$WORK/eleven/f$i.txt"
done
run_expect 1 "$BIN" encrypt --password "$PW" "$WORK/eleven"/*.txt
grep -q '10' "$WORK/stderr" || fail "the 11-file error does not mention the limit of 10"
[ -z "$(find "$WORK/eleven" -name '*.aes' -print -quit)" ] || fail "the 11-file run created output"
ok "an 11-file batch exits 1 and mentions the limit of 10"

mkdir -p "$WORK/unsupported"
python3 - "$WORK/unsupported/future.aes" <<'PY'
import sys
open(sys.argv[1], "wb").write(b"AES\x09\x00")
PY
run_expect 4 "$BIN" decrypt --password "$PW" "$WORK/unsupported/future.aes"
grep -q 'not supported' "$WORK/stderr" || fail "unsupported-version error message is missing"
ok "an unsupported AES Crypt version exits 4"

# ---------------------------------------------------------------- JSON output

mkdir -p "$WORK/json"
printf 'json payload\n' >"$WORK/json/j.txt"
run_expect 0 "$BIN" encrypt --password "$PW" --json "$WORK/json/j.txt"
python3 -m json.tool <"$WORK/stdout" >/dev/null || fail "--json output is not valid JSON"
python3 - "$WORK/stdout" "$WORK/json/j.txt.aes" <<'PY' || fail "--json schema is wrong"
import json, os, sys
doc = json.load(open(sys.argv[1]))
assert doc["version"] == "0.2.0", doc
assert doc["command"] == "encrypt", doc
assert len(doc["results"]) == 1, doc
row = doc["results"][0]
assert row["status"] == "ok", row
assert row["mode"] == "encrypt", row
assert row["error"] is None, row
assert row["input"] == os.path.abspath(sys.argv[2][:-4]), row
assert row["output"] == os.path.abspath(sys.argv[2]), row
PY
ok "--json emits the documented object and parses with json.tool"

# ---------------------------------------------------------------- password file

mkdir -p "$WORK/pwfile" "$WORK/pwfile/out"
printf 'file secret\nsecond line ignored\n' >"$WORK/pwfile/password"
printf 'password file payload\n' >"$WORK/pwfile/x.txt"
run_expect 0 "$BIN" encrypt --password-file "$WORK/pwfile/password" "$WORK/pwfile/x.txt"
cp "$WORK/pwfile/x.txt.aes" "$WORK/pwfile/out/x.aes"
run_expect 0 "$BIN" decrypt --password-file "$WORK/pwfile/password" "$WORK/pwfile/out/x.aes"
cmp "$WORK/pwfile/x.txt" "$WORK/pwfile/out/x" || fail "password file round trip failed"

printf 'stdin secret\n' >"$WORK/pwfile/stdin-password"
printf 'stdin payload\n' >"$WORK/pwfile/s.txt"
# shellcheck disable=SC2016 # $1..$3 expand inside the inner bash.
run_expect 0 bash -c 'cat "$1" | "$2" encrypt --password-file - "$3"' _ \
    "$WORK/pwfile/stdin-password" "$BIN" "$WORK/pwfile/s.txt"
[ -f "$WORK/pwfile/s.txt.aes" ] || fail "--password-file - did not read stdin"

printf 'wrong password\n' >"$WORK/pwfile/wrong"
cp "$WORK/pwfile/x.txt.aes" "$WORK/pwfile/out/wrong.aes"
run_expect 2 "$BIN" decrypt --password-file "$WORK/pwfile/wrong" "$WORK/pwfile/out/wrong.aes"
grep -qi 'wrong password' "$WORK/stderr" || fail "wrong-password error message is missing"
ok "--password-file reads the first line, supports stdin, and a wrong password exits 2"

run_expect 1 "$BIN" encrypt --password "$PW" --password-file "$WORK/pwfile/password" "$WORK/pwfile/x.txt"
ok "--password with --password-file is a usage error"

# ---------------------------------------------------------------- output exists

mkdir -p "$WORK/exists"
printf 'source\n' >"$WORK/exists/s.txt"
printf 'sentinel\n' >"$WORK/exists/s.txt.aes"
run_expect 5 "$BIN" encrypt --password "$PW" "$WORK/exists/s.txt"
[ "$(cat "$WORK/exists/s.txt.aes")" = 'sentinel' ] || fail "an existing output was overwritten"
ok "an existing output exits 5 and keeps its bytes"

# ---------------------------------------------------------------- exit priority

mkdir -p "$WORK/priority"
printf 'priority payload\n' >"$WORK/priority/p.txt"
run_expect 0 "$BIN" encrypt --password "$PW" "$WORK/priority/p.txt"
mv "$WORK/priority/p.txt.aes" "$WORK/priority/good.aes"
printf 'junk\n' >"$WORK/priority/bad.aes"
run_expect 2 "$BIN" decrypt --password wrong "$WORK/priority/good.aes" "$WORK/priority/bad.aes"
ok "a wrong password outranks a corrupt file in the exit code"

# ---------------------------------------------------------------- info JSON

run_expect 0 "$BIN" info --json "$WORK/round/a.txt.aes"
python3 - "$WORK/stdout" <<'PY' || fail "info --json schema is wrong"
import json, sys
doc = json.load(open(sys.argv[1]))
assert doc["version"] == "0.2.0", doc
assert doc["command"] == "info", doc
row = doc["results"][0]
assert row["status"] == "ok", row
assert row["format"] == "v3", row
assert isinstance(row["size"], int) and row["size"] > 0, row
assert isinstance(row["ciphertext"], int) and row["ciphertext"] > 0, row
PY
ok "info --json reports the v3 default, size, and ciphertext"

run_expect 0 "$BIN" encrypt --password "$PW" --format v2 \
    -o "$WORK/round/forced-v2.aes" "$WORK/round/a.txt"
run_expect 0 "$BIN" info --json "$WORK/round/forced-v2.aes"
python3 - "$WORK/stdout" <<'PY' || fail "info --json did not report the forced v2 format"
import json, sys
doc = json.load(open(sys.argv[1]))
assert doc["results"][0]["format"] == "v2", doc
PY
ok "--format v2 still produces a v2 file"

# ---------------------------------------------------------------- password hint

mkdir -p "$WORK/hint"
printf 'hint payload\n' >"$WORK/hint/h.txt"
run_expect 0 "$BIN" encrypt --password "$PW" --hint "pet name" "$WORK/hint/h.txt"
run_expect 0 "$BIN" info "$WORK/hint/h.txt.aes"
grep -q 'password hint: pet name' "$WORK/stdout" || fail "info did not print the password hint"
run_expect 0 "$BIN" info --json "$WORK/hint/h.txt.aes"
python3 - "$WORK/stdout" <<'PY' || fail "info --json did not report the hint"
import json, sys
doc = json.load(open(sys.argv[1]))
assert doc["results"][0]["hint"] == "pet name", doc
PY
cp "$WORK/hint/h.txt.aes" "$WORK/hint/out.aes"
run_expect 0 "$BIN" decrypt --password "$PW" "$WORK/hint/out.aes"
cmp "$WORK/hint/h.txt" "$WORK/hint/out" || fail "hint round trip failed"
run_expect 1 "$BIN" decrypt --password "$PW" --hint "not allowed" "$WORK/hint/h.txt.aes"
LONG_HINT="$(python3 -c 'print("a" * 300)')"
run_expect 1 "$BIN" encrypt --password "$PW" --hint "$LONG_HINT" "$WORK/hint/h.txt"
ok "password hints round trip, appear in info, and are encrypt-only"

printf 'terminal payload\\n' >"$WORK/hint/terminal.txt"
TERMINAL_HINT=$(printf 'visible\033[2J\nnext\tend')
run_expect 0 "$BIN" encrypt --password "$PW" --hint "$TERMINAL_HINT" "$WORK/hint/terminal.txt"
run_expect 0 "$BIN" info "$WORK/hint/terminal.txt.aes"
grep -Fq 'password hint: visible\u{001B}[2J\nnext\tend' "$WORK/stdout" \
    || fail "info did not visibly escape terminal controls"
python3 - "$WORK/stdout" <<'PY' || fail "info output contains terminal control bytes"
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_bytes()
assert not any((byte < 0x20 and byte != 0x0A) or 0x7F <= byte <= 0x9F for byte in text), repr(text)
PY
run_expect 0 "$BIN" info --json "$WORK/hint/terminal.txt.aes"
EXPECTED_HINT="$TERMINAL_HINT" python3 - "$WORK/stdout" <<'PY' || fail "info --json changed the terminal-control hint"
import json, os, sys
doc = json.load(open(sys.argv[1]))
assert doc["results"][0]["hint"] == os.environ["EXPECTED_HINT"], doc
PY
ok "info escapes terminal controls while JSON preserves the hint"

CONTROL_NAME="control$(printf '\033')name.aes"
cp "$WORK/hint/terminal.txt.aes" "$WORK/hint/$CONTROL_NAME"
run_expect 0 "$BIN" info "$WORK/hint/$CONTROL_NAME"
python3 - "$WORK/stdout" <<'PY' || fail "info output contains a raw control character in the file path"
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_bytes()
assert not any((byte < 0x20 and byte != 0x0A) or 0x7F <= byte <= 0x9F for byte in text), repr(text)
assert b"control\\u{001B}name.aes" in text, repr(text)
PY
ok "info escapes terminal controls in file paths"

CONTROL_INPUT="control$(printf '\033')name.txt"
printf 'path control payload\\n' >"$WORK/hint/$CONTROL_INPUT"
run_expect 0 "$BIN" encrypt --password "$PW" "$WORK/hint/$CONTROL_INPUT"
python3 - "$WORK/stdout" <<'PY' || fail "encrypt output path contains raw controls"
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_bytes()
assert b"control\\u{001B}name.txt.aes" in text, repr(text)
assert not any((byte < 0x20 and byte != 0x0A) or 0x7F <= byte <= 0x9F for byte in text), repr(text)
PY
MISSING_INPUT="missing$(printf '\033')name.txt"
run_expect 5 "$BIN" encrypt --password "$PW" "$WORK/hint/$MISSING_INPUT"
python3 - "$WORK/stderr" <<'PY' || fail "error output path contains raw controls"
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
assert text.count(r"missing\u{001B}name.txt") == 2, repr(text)
assert not any((ord(char) < 0x20 and char != "\n") or 0x7F <= ord(char) <= 0x9F for char in text), repr(text)
PY
ok "encrypt and error output escape terminal controls in file paths"

# ---------------------------------------------------------------- Unicode

mkdir -p "$WORK/unicode" "$WORK/unicode/out"
UNICODE_FILE="$WORK/unicode/héllo 世界.txt"
UNICODE_PW='pässwörd🔐'
printf 'unicode payload\n' >"$UNICODE_FILE"
run_expect 0 "$BIN" encrypt --password "$UNICODE_PW" "$UNICODE_FILE"
cp "$UNICODE_FILE.aes" "$WORK/unicode/out/u.aes"
run_expect 0 "$BIN" decrypt --password "$UNICODE_PW" "$WORK/unicode/out/u.aes"
cmp "$UNICODE_FILE" "$WORK/unicode/out/u" || fail "Unicode round trip failed"
ok "Unicode filename and password round trip"

# ---------------------------------------------------------------- no leftovers

if find "$WORK" -name '.aesopen-*' -print -quit | grep -q .; then
    fail "temporary .aesopen-* files were left behind"
fi
ok "no .aesopen-* temporary files remain"

# ---------------------------------------------------------------- cross-checks

cross_check() {
    local label="$1"
    local tool="$2"
    local formats="$3"
    [ -n "$tool" ] || return 0
    [ -x "$tool" ] || fail "$label cross-check tool is not executable: $tool"

    local dir="$WORK/cross-$label"
    mkdir -p "$dir"
    printf 'cross-check payload for %s\n' "$label" >"$dir/plain.txt"
    for format in $formats; do
        run_expect 0 "$BIN" encrypt --password "$PW" --format "$format" \
            -o "$dir/$format.aes" "$dir/plain.txt"
        "$tool" -d -p "$PW" -o "$dir/$format.out" "$dir/$format.aes" >/dev/null 2>&1 \
            || fail "$label could not decrypt our $format output"
        cmp "$dir/plain.txt" "$dir/$format.out" || fail "$label $format round trip mismatch"

        run_expect 0 "$BIN" encrypt --password "$PW" --format "$format" \
            --hint "cross-check hint" -o "$dir/$format-hint.aes" "$dir/plain.txt"
        "$tool" -d -p "$PW" -o "$dir/$format-hint.out" "$dir/$format-hint.aes" >/dev/null 2>&1 \
            || fail "$label could not decrypt our hinted $format output"
        cmp "$dir/plain.txt" "$dir/$format-hint.out" \
            || fail "$label hinted $format round trip mismatch"
    done
    ok "$label decrypts our $formats output"
}

# AES Crypt 3.14 has no format 3 reader (verified: it exits with
# "Unsupported AES file version: 3"), so it only checks format 2.
cross_check "AES Crypt 3.14" "${AESCRYPT314:-}" "v2"
cross_check "AES Crypt 4.7" "${AESCRYPT4:-}" "v2 v3"

echo "==> $PASS CLI checks passed"
