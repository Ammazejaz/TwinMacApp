#!/bin/zsh
set -eu
ROOT="${0:A:h}"
mkdir -p "$ROOT/.build/module-cache"
swiftc -swift-version 5 \
  -module-cache-path "$ROOT/.build/module-cache" \
  -framework AppKit \
  "$ROOT/Sources/LauncherModel.swift" \
  "$ROOT/Sources/AccountProfiles.swift" \
  "$ROOT/Tests/ProfilePreparationCheck.swift" \
  -o "$ROOT/.build/profile-preparation-check"
cd "$ROOT"
"$ROOT/.build/profile-preparation-check"
