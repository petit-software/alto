#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Release}"
case "$configuration" in Debug|Release) ;; *) echo 'Usage: scripts/build-app.sh [Debug|Release]' >&2; exit 1 ;; esac
# Certificate-backed signatures keep the designated requirement stable across
# rebuilds, so Accessibility approval isn't tied to a changing ad-hoc cdhash.
signing_identity="${ALTO_CODE_SIGN_IDENTITY:-}"
signing_identities="$(security find-identity -v -p codesigning)"
if [ -z "$signing_identity" ]; then
  signing_identity="$(echo "$signing_identities" | sed -nE '/"Apple Development:/s/.* ([0-9A-F]{40}) .*/\1/p' | head -n 1)"
fi
if [ -z "$signing_identity" ]; then
  signing_identity='-'
fi
if [ "$signing_identity" = '-' ]; then
  echo 'Warning: ad-hoc signing; Accessibility may need re-approval after each rebuild.' >&2
else
  echo 'Using certificate-backed signing for stable Accessibility identity.'
fi
signing_arguments=("CODE_SIGN_IDENTITY=$signing_identity" "CODE_SIGN_STYLE=Manual")
signing_team="${ALTO_DEVELOPMENT_TEAM:-}"
if [ "$signing_identity" != '-' ] && [ -z "$signing_team" ]; then
  matching_identity="$(echo "$signing_identities" | grep -F -- "$signing_identity" || true)"
  signing_team="$(echo "$matching_identity" | sed -nE 's/.*\(([A-Z0-9]{10})\)".*/\1/p' | head -n 1)"
fi
if [ -n "$signing_team" ]; then
  signing_arguments+=("DEVELOPMENT_TEAM=$signing_team")
fi
xcodebuild -quiet -project Alto.xcodeproj -scheme Alto -configuration "$configuration" \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build \
  "${signing_arguments[@]}" build
mkdir -p dist
assembly_dir="$(mktemp -d /private/tmp/alto-assembly.XXXXXX)"
ditto "build/Build/Products/$configuration/Alto.app" "$assembly_dir/Alto.app"
codesign --verify --deep --strict "$assembly_dir/Alto.app"
# Assemble from scratch so removed resources cannot survive and break the seal.
# Moving the prior bundle also avoids overwriting a running executable in place.
if [ -d dist/Alto.app ]; then mv dist/Alto.app "$assembly_dir/Previous.app"; fi
mv "$assembly_dir/Alto.app" dist/Alto.app
echo "Built: $PWD/dist/Alto.app"
