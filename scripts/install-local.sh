#!/bin/bash
# install-local.sh — build Peek and install it to /Applications with correct
# pluginkit registration. Run after every change you want to test in Finder.
#
# Why this exists: xcodebuild registers the BUILD-DIRECTORY copy of the
# FinderSync appex with pluginkit. A duplicate in /Applications then fails
# extension election and no menu item appears (discovered in the 2026-08-07
# spike). This script installs, removes the build copy, and re-registers.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=/Applications/Peek.app
BUILD=build/Build/Products/Debug/Peek.app

echo "==> Generating Xcode project"
xcodegen generate --quiet

echo "==> Building"
xcodebuild -project Peek.xcodeproj -scheme Peek -configuration Debug \
  -derivedDataPath build build 2>&1 | tail -3

echo "==> Installing to /Applications"
ditto "$BUILD" "$APP"

echo "==> Removing build products (prevents duplicate pluginkit registration)"
rm -rf build/Build/Products

echo "==> Registering extensions from /Applications"
pluginkit -a "$APP/Contents/PlugIns/PeekFinder.appex" || true
pluginkit -e use -i dev.pbommu.peek.findersync || true

echo "==> Restarting Finder"
killall Finder || true

echo "==> Done. Verify with: pluginkit -m -v -A | grep -i peek"
echo "    First run: enable the extension in System Settings → Extensions."
