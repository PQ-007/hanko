#!/usr/bin/env bash
# Builds the extension zips: web-ext-artifacts/hanko-{chrome,firefox}-<version>.zip
#
#   bash src/package.sh
#
# The extension has no build step, so chrome/ and firefox/ are two copies of
# the same files apart from manifest.json. This script:
#   1. copies the canonical shared scripts from src/ (sync.js, ui.js) into both;
#   2. refuses to package if any other file differs between the two folders
#      (an edit made to one copy and not the other);
#   3. checks both manifests carry the same version, then zips each folder.
# config.js is included — the extension can't sign in without it — and the
# zips are git-ignored (*.zip), so it never lands in a commit this way.
set -euo pipefail
cd "$(dirname "$0")/.."

for f in sync.js ui.js; do
  cp "src/$f" "chrome/$f"
  cp "src/$f" "firefox/$f"
done

drift=$(diff -rq --exclude=manifest.json chrome firefox || true)
if [ -n "$drift" ]; then
  echo "chrome/ and firefox/ differ — copy the change to both first:" >&2
  echo "$drift" >&2
  exit 1
fi

version() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$1"; }
v=$(version chrome/manifest.json)
if [ "$v" != "$(version firefox/manifest.json)" ]; then
  echo "manifest versions differ: chrome $v, firefox $(version firefox/manifest.json)" >&2
  exit 1
fi
[ -f chrome/config.js ] || { echo "chrome/config.js is missing (see src/config.example.js)" >&2; exit 1; }

mkdir -p web-ext-artifacts
for b in chrome firefox; do
  out="web-ext-artifacts/hanko-$b-$v.zip"
  rm -f "$out"
  (cd "$b" && zip -qr -X "../$out" . -x '.*')
  echo "$out"
done
