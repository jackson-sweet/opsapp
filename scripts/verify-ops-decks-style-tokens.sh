#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

TARGETS=(
  "$ROOT/OPSDecks"
  "$ROOT/Packages/DeckKit/Sources"
  "$ROOT/Packages/OPSDesignKit/Sources"
)

EXCLUDES='OPSStyle.swift|Package.swift|Generated|Resources|Colors.xcassets'

PATTERN='Color\(red:|Color\([[:space:]]*#[0-9A-Fa-f]|UIColor\(|NSColor\(|\.font\(\.system|Font\.system|\.cornerRadius\([0-9]|\.clipShape\(RoundedRectangle\(cornerRadius:[[:space:]]*[0-9]|\.padding\([0-9]|\.padding\(\.all,[[:space:]]*[0-9]|\.frame\(width:[[:space:]]*[0-9]|\.animation\(\.spring|Animation\.spring|\.shadow\(|boxShadow|#[0-9A-Fa-f]{6}'

found=0
for target in "${TARGETS[@]}"; do
  if [[ -d "$target" ]]; then
    while IFS= read -r line; do
      file="${line%%:*}"
      if [[ ! "$file" =~ $EXCLUDES ]]; then
        echo "$line"
        found=1
      fi
    done < <(rg -n "$PATTERN" "$target" || true)
  fi
done

if [[ "$found" -ne 0 ]]; then
  echo "Hardcoded styling/design values found. Route every value through OPSDesignKit/OPSStyle tokens." >&2
  exit 1
fi
