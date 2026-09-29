#!/usr/bin/env bash
# Before a site is deployed, the runner's own apt must accept it: the signed InRelease verifies
# against the key this repository publishes, both architectures' indexes are well formed, and the
# candidate for `rexenv` is the newest version in the pool. Runs as root (apt's own sandboxing),
# with every apt directory pointed into a temporary folder so the runner's sources are untouched.
#
#   sudo ./scripts/self-test.sh site
set -euo pipefail

SITE="$(cd "${1:?usage: self-test.sh <site-dir>}" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
chmod 755 "$T"
mkdir -p "$T/lists/partial" "$T/cache/archives/partial" "$T/sources.list.d" "$T/preferences.d"
echo "deb [signed-by=${SITE}/rexenv.gpg] file://${SITE} stable main" > "$T/sources.list"

for arch in amd64 arm64; do
  apt_opts=(
    -o "Dir::Etc::SourceList=$T/sources.list"
    -o "Dir::Etc::SourceParts=$T/sources.list.d"
    -o "Dir::Etc::Preferences=$T/preferences"
    -o "Dir::Etc::PreferencesParts=$T/preferences.d"
    -o "Dir::State::Lists=$T/lists"
    -o "Dir::Cache=$T/cache"
    -o "APT::Architecture=$arch"
    -o "APT::Architectures::=$arch"
  )
  rm -rf "$T/lists"/* 2>/dev/null || true
  mkdir -p "$T/lists/partial"
  # Any signature or hash problem is an error here, not a warning apt carries on past.
  apt-get "${apt_opts[@]}" -o APT::Update::Error-Mode=any update
  newest="$(ls "$SITE/pool/main/r/rexenv" | sed -n "s/^rexenv_\\(.*\\)_${arch}\\.deb$/\\1/p" | sort -V | tail -1)"
  candidate="$(apt-cache "${apt_opts[@]}" policy rexenv | awk '/Candidate:/ {print $2}')"
  if [ "$candidate" != "$newest" ]; then
    echo "self-test: ${arch}: apt's candidate is '${candidate}', the pool's newest is '${newest}'" >&2
    exit 1
  fi
  echo "self-test: ${arch}: signature verified, candidate rexenv ${candidate}"
done
