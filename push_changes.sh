#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <git-remote-url> [branch]"
  exit 1
fi

REMOTE_URL="$1"
BRANCH="${2:-main}"

# Initialize repo if needed
if [ ! -d .git ]; then
  git init
  git checkout -b "$BRANCH" 2>/dev/null || true
fi

git add -A
git commit -m "Apply OpenShift AI + GitOps bootstrap fixes: skip duplicate GitOps install, Argo Job Replace, DSC/Dashboard sync safeguards" || true

# Set or update remote
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
fi

git push -u origin "$BRANCH"
