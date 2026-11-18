#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release --product Miso

app="${HOME}/Applications/Miso.app"
mkdir -p "${HOME}/Applications"

if killall Miso 2>/dev/null; then
  sleep 0.3
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/.build/release/Miso" "$app/Contents/MacOS/Miso"
cp "$root/scripts/Info.plist" "$app/Contents/Info.plist"
chmod +x "$app/Contents/MacOS/Miso"

codesign --force --sign - --identifier com.vrishab.miso "$app"

plutil -lint "$app/Contents/Info.plist" >/dev/null

bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")"
if [[ "$bundle_id" != "com.vrishab.miso" ]]; then
  echo "Expected CFBundleIdentifier com.vrishab.miso, got ${bundle_id}" >&2
  exit 1
fi

sign_id="$(codesign -dv "$app" 2>&1 | sed -n 's/^Identifier=//p')"
if [[ "$sign_id" != "com.vrishab.miso" ]]; then
  echo "Expected signing identifier com.vrishab.miso, got ${sign_id}" >&2
  exit 1
fi

echo "Installed ${app}"
echo "CFBundleIdentifier=${bundle_id}"
echo "codesign Identifier=${sign_id}"

if command -v sfltool >/dev/null 2>&1; then
  echo "Login items for com.vrishab.miso (a duplicate would list this id more than once):"
  dump="$(mktemp)"
  sfltool dumpbtm >"$dump" 2>/dev/null &
  dump_pid=$!
  for _ in 1 2 3 4 5; do
    if ! kill -0 "$dump_pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  if kill -0 "$dump_pid" 2>/dev/null; then
    kill -9 "$dump_pid" 2>/dev/null || true
    wait "$dump_pid" 2>/dev/null || true
    echo "(sfltool dumpbtm timed out)"
  else
    wait "$dump_pid" 2>/dev/null || true
    matches="$(grep -F "com.vrishab.miso" "$dump" || true)"
    if [[ -n "$matches" ]]; then
      printf '%s\n' "$matches"
      count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
      echo "Match lines: ${count}"
    else
      echo "(none registered)"
    fi
  fi
  rm -f "$dump"
fi

open "$app"
