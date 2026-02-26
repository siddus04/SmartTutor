#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$REPO_ROOT/SmartTutor.xcodeproj/project.pbxproj"

if [[ ! -f "$PBXPROJ" ]]; then
  echo "project file not found: $PBXPROJ" >&2
  exit 1
fi

missing_refs=()
missing_sources=()

while IFS= read -r file; do
  base="$(basename "$file")"

  if ! grep -Fq "/* $base */ = {isa = PBXFileReference;" "$PBXPROJ"; then
    missing_refs+=("$file")
  fi

  if ! grep -Fq "$base in Sources" "$PBXPROJ"; then
    missing_sources+=("$file")
  fi

done < <(cd "$REPO_ROOT" && rg --files Features -g '*.swift')

if (( ${#missing_refs[@]} > 0 || ${#missing_sources[@]} > 0 )); then
  echo "❌ Xcode project consistency check failed"

  if (( ${#missing_refs[@]} > 0 )); then
    echo "Missing PBXFileReference entries:"
    printf '  - %s\n' "${missing_refs[@]}"
  fi

  if (( ${#missing_sources[@]} > 0 )); then
    echo "Missing PBXSourcesBuildPhase entries:"
    printf '  - %s\n' "${missing_sources[@]}"
  fi

  exit 1
fi

echo "✅ Xcode project includes all Features/*.swift files in file references and Sources build phase"
