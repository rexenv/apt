#!/usr/bin/env bash
# Build the signed apt repository for rexenv from the newest published releases on the tap.
#
#   APT_SIGNING_KEY=<armored private key> ./scripts/build-site.sh site
#
# The site is DERIVED, never accumulated: every run downloads the debs of the newest KEEP
# published (not draft, not prerelease) releases of rexenv/homebrew-tap, checks each against its
# .sha256 and its own control fields, builds the indexes with apt-ftparchive and signs Release —
# so nothing binary is ever committed here, and a re-run rebuilds everything from the releases.
#
# The key that signs must be the key this repository publishes: its fingerprint is committed in
# KEY_FINGERPRINT, and a secret that does not match stops the build (a wrong key signs perfectly
# well, and every apt on every machine would then refuse the repo in silence).
set -euo pipefail

OUT="${1:?usage: build-site.sh <out-dir>}"
KEEP="${KEEP:-3}"
TAP="${TAP:-rexenv/homebrew-tap}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${APT_SIGNING_KEY:?APT_SIGNING_KEY (the armored private key) is not set}"

EXPECTED_FPR="$(tr -d ' \n' < "$ROOT/KEY_FINGERPRINT")"
POOL="$OUT/pool/main/r/rexenv"
TMP="$(mktemp -d)"
export GNUPGHOME="$(mktemp -d)"
chmod 700 "$GNUPGHOME"
trap 'rm -rf "$TMP" "$GNUPGHOME"' EXIT

rm -rf "$OUT"
mkdir -p "$POOL"

# ---------------------------------------------------------------- the key
printf '%s\n' "$APT_SIGNING_KEY" | gpg --batch --quiet --import
FPR="$(gpg --batch --list-secret-keys --with-colons | awk -F: '/^fpr/ {print $10; exit}')"
if [ "$FPR" != "$EXPECTED_FPR" ]; then
  echo "build-site: the signing key is ${FPR:-none}, but this repository publishes ${EXPECTED_FPR} (KEY_FINGERPRINT) — refusing to sign with a key every apt would reject." >&2
  exit 1
fi

# ---------------------------------------------------------------- the debs
tags="$(gh release list -R "$TAP" --exclude-drafts --exclude-pre-releases --limit 30 \
  --json tagName,publishedAt --jq 'sort_by(.publishedAt) | reverse | .[].tagName')"
kept=0
for tag in $tags; do
  [ "$kept" -ge "$KEEP" ] && break
  v="${tag#v}"
  got=0
  for arch in amd64 arm64; do
    deb="rexenv_${v}_${arch}.deb"
    if ! gh release download "$tag" -R "$TAP" -p "$deb" -p "$deb.sha256" -D "$TMP" --clobber 2>/dev/null; then
      continue # a release from before the Linux port carries no deb
    fi
    (cd "$TMP" && sha256sum -c --quiet "$deb.sha256")
    # The file's own control fields must say what its name says — apt indexes the fields, not the name.
    [ "$(dpkg-deb -f "$TMP/$deb" Package)" = "rexenv" ] || { echo "build-site: $deb is not the rexenv package" >&2; exit 1; }
    [ "$(dpkg-deb -f "$TMP/$deb" Version)" = "$v" ] || { echo "build-site: $deb says Version $(dpkg-deb -f "$TMP/$deb" Version)" >&2; exit 1; }
    [ "$(dpkg-deb -f "$TMP/$deb" Architecture)" = "$arch" ] || { echo "build-site: $deb says Architecture $(dpkg-deb -f "$TMP/$deb" Architecture)" >&2; exit 1; }
    mv "$TMP/$deb" "$POOL/"
    got=$((got + 1))
  done
  if [ "$got" -gt 0 ]; then
    kept=$((kept + 1))
    echo "build-site: ${tag} — ${got} deb(s)"
  fi
done
[ "$kept" -gt 0 ] || { echo "build-site: no published release on $TAP carries a deb" >&2; exit 1; }

# ---------------------------------------------------------------- the indexes
cd "$OUT"
for arch in amd64 arm64; do
  dir="dists/stable/main/binary-${arch}"
  mkdir -p "$dir"
  apt-ftparchive --arch "$arch" packages pool > "$dir/Packages"
  gzip -9kn "$dir/Packages"
done
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin=rexenv \
  -o APT::FTPArchive::Release::Label=rexenv \
  -o APT::FTPArchive::Release::Suite=stable \
  -o APT::FTPArchive::Release::Codename=stable \
  -o "APT::FTPArchive::Release::Architectures=amd64 arm64" \
  -o APT::FTPArchive::Release::Components=main \
  -o "APT::FTPArchive::Release::Description=rexenv — a native local development environment" \
  release dists/stable > "$TMP/Release" # not straight into dists/stable: it would hash its own half-written self
mv "$TMP/Release" dists/stable/Release

# ---------------------------------------------------------------- the signatures
gpg --batch --yes --default-key "$FPR" --clearsign -o dists/stable/InRelease dists/stable/Release
gpg --batch --yes --default-key "$FPR" --armor --detach-sign -o dists/stable/Release.gpg dists/stable/Release

# ---------------------------------------------------------------- the published key + the page
cp "$ROOT/rexenv.gpg" "$ROOT/rexenv.asc" "$ROOT/index.html" .
touch .nojekyll
echo "build-site: $(ls pool/main/r/rexenv | wc -l | tr -d ' ') deb(s) from ${kept} release(s), signed by ${FPR}"
