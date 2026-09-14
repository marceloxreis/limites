#!/bin/zsh
# Fails when a user-facing string in the code has no Brazilian Portuguese translation,
# or when the translation file still carries keys the code no longer uses.
# The keys come from the compiler itself, so interpolated strings match exactly.
set -euo pipefail
cd "${0:A:h}/.."

table=Resources/pt-BR.lproj/Localizable.strings
plutil -lint -s "$table"

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swift build --arch arm64 -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$out" >/dev/null

python3 - "$out" "$table" <<'PY'
import glob, json, re, subprocess, sys

out, table = sys.argv[1:]
used = set()
for path in glob.glob(f"{out}/*.stringsdata"):
    for entries in json.load(open(path))["tables"].values():
        used.update(entry["key"] for entry in entries)
# Keys made only of placeholders and punctuation ("%@ · %@") need no translation.
used = {key for key in used if re.search(r"[A-Za-z]", re.sub(r"%(lld|ld|d|@|%)", "", key))}

plist = subprocess.run(["plutil", "-convert", "json", "-o", "-", table], check=True, capture_output=True).stdout
translated = set(json.loads(plist))

missing, stale = sorted(used - translated), sorted(translated - used)
for key in missing:
    print(f"missing translation: {key!r}")
for key in stale:
    print(f"unused translation: {key!r}")
if missing or stale:
    sys.exit(1)
print(f"{len(used)} strings, all translated")
PY
