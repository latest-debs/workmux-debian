#!/usr/bin/env bash
set -euo pipefail

API="https://api.github.com"
AUTH=(-H "Authorization: token ${GITHUB_TOKEN:?}")

gh_json() { curl -fsSL "${AUTH[@]}" "$1" || true; }

yaml_val() {
  awk -v k="$1" -F': *' '$1==k { v=$2; gsub(/["'\'' ]/, "", v); sub(/#.*/, "", v); print v; exit }' package.yaml
}

GITHUB_REPO="$(yaml_val github_repo)"
PACKAGE_NAME="$(yaml_val package_name)"

[ -n "$GITHUB_REPO" ] || { echo "::error::github_repo not found in package.yaml"; exit 1; }
[ -n "$PACKAGE_NAME" ] || { echo "::error::package_name not found in package.yaml"; exit 1; }
[ -n "${GITHUB_REPOSITORY:-}" ] || { echo "::error::GITHUB_REPOSITORY not set"; exit 1; }

normalize() { printf '%s' "$1" | sed -E 's/^[vV]//; s/\+[0-9]+$//'; }
out() { printf '%s=%s\n' "$1" "$2" >>"${GITHUB_OUTPUT:-/dev/null}"; }

BUILD_VERSION="${BUILD_VERSION:-1}"
AUTO="${AUTO:-false}"

if [ "$AUTO" != "true" ]; then
  [ -n "${MANUAL_VERSION:-}" ] || { echo "::error::version input is required when auto is off"; exit 1; }
  out version "$MANUAL_VERSION"
  out build_version "$BUILD_VERSION"
  out should_build true
  exit 0
fi

UPSTREAM_TAG=""
resp="$(gh_json "$API/repos/$GITHUB_REPO/releases/latest")"
UPSTREAM_TAG="$(printf '%s' "$resp" | jq -r '.tag_name // empty' 2>/dev/null || true)"
if [ -z "$UPSTREAM_TAG" ]; then
  resp="$(gh_json "$API/repos/$GITHUB_REPO/releases?per_page=1")"
  UPSTREAM_TAG="$(printf '%s' "$resp" | jq -r '.[0].tag_name // empty' 2>/dev/null || true)"
fi
if [ -z "$UPSTREAM_TAG" ]; then
  echo "::notice::No upstream releases found for $GITHUB_REPO; nothing to build"
  out should_build false
  exit 0
fi

OWN_TAG=""
resp="$(gh_json "$API/repos/$GITHUB_REPOSITORY/releases/latest")"
OWN_TAG="$(printf '%s' "$resp" | jq -r '.tag_name // empty' 2>/dev/null || true)"
if [ -z "$OWN_TAG" ]; then
  resp="$(gh_json "$API/repos/$GITHUB_REPOSITORY/tags?per_page=1")"
  OWN_TAG="$(printf '%s' "$resp" | jq -r '.[0].name // empty' 2>/dev/null || true)"
fi

up="$(normalize "$UPSTREAM_TAG")"
own="$(normalize "$OWN_TAG")"

if [ -n "$own" ] && [ "$(printf '%s\n%s' "$up" "$own" | sort -V | tail -n1)" = "$own" ]; then
  echo "::notice::Upstream $UPSTREAM_TAG already built as $OWN_TAG; skipping"
  out should_build false
  exit 0
fi

echo "::notice::New upstream release detected: $UPSTREAM_TAG (last built: ${OWN_TAG:-none})"
out version "$UPSTREAM_TAG"
out build_version "$BUILD_VERSION"
out should_build true
