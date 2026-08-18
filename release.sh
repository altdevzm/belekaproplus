#!/usr/bin/env bash
# ============================================================
# Beleka POS — 1-Click Release Script
# ============================================================
set -e

VERSION="$1"

if [ -z "$VERSION" ]; then
  # Read current version from pubspec.yaml
  CURRENT_VER=$(grep "^version:" pubspec.yaml | head -1 | awk '{print $2}' | cut -d'+' -f1)
  echo "Current version in pubspec.yaml is: $CURRENT_VER"
  read -p "Enter version to release (e.g. 1.2.0 or press Enter for $CURRENT_VER): " INPUT_VER
  VERSION="${INPUT_VER:-$CURRENT_VER}"
fi

# Ensure version format
VERSION="${VERSION#v}"  # Strip leading 'v' if entered

echo ""
echo "🚀 Creating Beleka POS Release v${VERSION}..."
echo "================================================="

# 1. Update version in pubspec.yaml
sed -i "s/^version: .*/version: ${VERSION}+1/" pubspec.yaml
echo "✅ Updated pubspec.yaml to ${VERSION}+1"

# 2. Stage and commit changes
git add -A
git commit -m "release: Beleka POS v${VERSION}" || echo "ℹ️ Nothing new to commit"

# 3. Create and push tag
git push origin main
git tag -d "v${VERSION}" 2>/dev/null || true
git push origin ":refs/tags/v${VERSION}" 2>/dev/null || true
git tag "v${VERSION}"
git push origin "v${VERSION}"

echo ""
echo "================================================="
echo "🎉 Done! GitHub is now building your release."
echo "🔗 Watch progress: https://github.com/altdevzm/belekapro/actions"
echo "📦 Download files: https://github.com/altdevzm/belekapro/releases"
echo "================================================="
