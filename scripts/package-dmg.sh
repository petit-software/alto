#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh Release
staging_dir="$(mktemp -d /private/tmp/alto-dmg.XXXXXX)"
ditto dist/Alto.app "$staging_dir/Alto.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname Alto -srcfolder "$staging_dir" -ov -format UDZO dist/Alto-0.1.0.dmg
echo "Created dist/Alto-0.1.0.dmg. This local build is not notarized."
