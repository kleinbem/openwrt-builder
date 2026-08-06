#!/usr/bin/env bash
# Check every profiles/*.conf against the latest OpenWrt stable release and
# open a GitHub issue (never a PR, never auto-applied) when a newer one is
# available.
#
# Firmware for a physical router is not something to auto-bump the way a
# Nix package hash is — a bad image can brick a device with no console. This
# only ever *flags* an available update with the exact values needed; a
# human still reviews and applies the bump by hand (see each profile's own
# header comment for the process this mirrors).
#
# Usage:  ./scripts/check-openwrt-release.sh
# Deps:   bash, curl, gh
set -euo pipefail

cd "$(dirname "$0")/.."

log() { echo -e "\033[0;32m[INFO]\033[0m  $*" >&2; }
err() {
  echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
  exit 1
}

# ── Latest stable release (skips "faillogs"/non-numeric dir entries) ────────
LATEST=$(curl -fsSL "https://downloads.openwrt.org/releases/" |
  grep -oP '(?<=href=")[0-9]+\.[0-9]+\.[0-9]+(?=/")' |
  sort -V | tail -1)
[[ -n $LATEST ]] || err "Could not determine latest OpenWrt release"
log "Latest OpenWrt stable release: $LATEST"

for profile in profiles/*.conf; do
  name=$(basename "$profile" .conf)
  (
    # shellcheck disable=SC1090
    source "$profile"

    if [[ $OPENWRT_RELEASE == "$LATEST" ]]; then
      log "$name: already at $LATEST — nothing to do."
      exit 0
    fi

    log "$name: $OPENWRT_RELEASE → $LATEST available"

    # Target platform (e.g. "mediatek/filogic") lives in BUILDER_URL between
    # /targets/ and the imagebuilder filename — extract it generically so
    # this works for any future profile, not just bpi-r4.
    TARGET=$(grep -oP '(?<=/targets/)[^/]+/[^/]+(?=/openwrt-imagebuilder-)' <<<"$BUILDER_URL")
    [[ -n $TARGET ]] || {
      echo -e "\033[0;31m[ERROR]\033[0m  $name: could not parse target from BUILDER_URL" >&2
      exit 1
    }

    NEW_BUILDER_URL="${BUILDER_URL//$OPENWRT_RELEASE/$LATEST}"
    NEW_FILENAME=$(basename "$NEW_BUILDER_URL")
    # Filename suffix after "openwrt-imagebuilder-<release>-" (e.g.
    # "mediatek-filogic.Linux-x86_64.tar.zst") — board/arch-specific,
    # derived generically rather than hardcoded per profile.
    SUFFIX=$(basename "$BUILDER_URL" | sed "s/^openwrt-imagebuilder-${OPENWRT_RELEASE}-//")
    SUMS_URL="https://downloads.openwrt.org/releases/${LATEST}/targets/${TARGET}/sha256sums"
    NEW_HASH=$(curl -fsSL "$SUMS_URL" | grep " \*${NEW_FILENAME}\$" | awk '{print $1}')
    if [[ -z $NEW_HASH ]]; then
      echo -e "\033[0;31m[ERROR]\033[0m  $name: $NEW_FILENAME not found in $SUMS_URL (target renamed upstream?)" >&2
      exit 1
    fi

    ISSUE_TITLE="chore: OpenWrt $LATEST available for $name (current: $OPENWRT_RELEASE)"

    # Dedup: don't spam a new issue every week if one's already open.
    EXISTING=$(gh issue list --state open --search "in:title \"$ISSUE_TITLE\"" --json number --jq '.[0].number // empty')
    if [[ -n $EXISTING ]]; then
      echo -e "\033[0;32m[INFO]\033[0m  $name: issue #$EXISTING already open for $LATEST — skipping." >&2
      exit 0
    fi

    # BUILDER_URL is already parameterized by ${OPENWRT_RELEASE} in the file
    # itself (see profile header), so only these two lines actually need
    # to change — bumping OPENWRT_RELEASE alone re-resolves BUILDER_URL.
    BODY_FILE=$(mktemp)
    cat > "$BODY_FILE" <<EOF
OpenWrt **$LATEST** is available (\`$name\` is currently pinned to $OPENWRT_RELEASE).

Apply by hand in \`$profile\`:

\`\`\`diff
-OPENWRT_RELEASE="$OPENWRT_RELEASE"
+OPENWRT_RELEASE="$LATEST"
 BUILDER_URL="https://downloads.openwrt.org/releases/\${OPENWRT_RELEASE}/targets/${TARGET}/openwrt-imagebuilder-\${OPENWRT_RELEASE}-${SUFFIX}"
-BUILDER_SHA256="$BUILDER_SHA256"
+BUILDER_SHA256="$NEW_HASH"
\`\`\`

(\`BUILDER_URL\` doesn't need editing — it re-resolves via \`\${OPENWRT_RELEASE}\` once that's bumped. Shown above unchanged for context.)

Verified: \`$NEW_HASH\` matched \`$NEW_FILENAME\` in [$SUMS_URL]($SUMS_URL).

Once bumped, the existing weekly \`build.yml\` run (and a PR's own CI) rebuilds and validates the image — this issue only flags the update, it doesn't touch any files.

---
🤖 Opened automatically by the check-openwrt-release workflow.
EOF

    gh issue create --title "$ISSUE_TITLE" --body-file "$BODY_FILE" --label dependencies
  )
done

log "Done."
