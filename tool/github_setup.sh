#!/usr/bin/env bash
# ============================================================
# Beleka POS — GitHub Setup Script
# Run this once to initialize git and push to your GitHub repo
# ============================================================
set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     Beleka POS — GitHub Setup Script     ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Prompt for GitHub details ──────────────────────────────
read -p "📝 Your GitHub username: " GH_USER
read -p "📁 Repository name [beleka-pos]: " GH_REPO
GH_REPO="${GH_REPO:-beleka-pos}"

REMOTE_URL="https://github.com/${GH_USER}/${GH_REPO}.git"

echo ""
echo "Will push to: $REMOTE_URL"
read -p "Continue? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Git init ───────────────────────────────────────────────
cd "$(dirname "$0")/.."

if [ ! -d .git ]; then
  git init -b main
  echo "✅ Git repository initialized"
else
  echo "ℹ️  Git repository already exists"
fi

# ── Configure remote ───────────────────────────────────────
if git remote get-url origin &>/dev/null 2>&1; then
  git remote set-url origin "$REMOTE_URL"
  echo "✅ Updated remote origin → $REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
  echo "✅ Added remote origin → $REMOTE_URL"
fi

# ── Update README with actual username ─────────────────────
sed -i "s/YOUR_GITHUB_USERNAME/${GH_USER}/g" README.md
echo "✅ Updated README.md with your GitHub username"

# ── Stage and commit ───────────────────────────────────────
git add -A
git status --short | head -20
echo ""
git commit -m "chore: initial commit — Beleka POS v1.0.0" || echo "(nothing new to commit)"

# ── Push ───────────────────────────────────────────────────
echo ""
echo "Pushing to GitHub..."
git push -u origin main

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✅ Done! Your code is on GitHub.        ║"
echo "║                                          ║"
echo "║  Next: Create your first release:        ║"
echo "║    git tag v1.0.0                        ║"
echo "║    git push origin v1.0.0               ║"
echo "║                                          ║"
echo "║  GitHub Actions will build & release     ║"
echo "║  the installer automatically!            ║"
echo "╚══════════════════════════════════════════╝"
