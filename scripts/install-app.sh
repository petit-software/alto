#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh "${1:-Release}"
if [ ! -w /Applications ]; then
  echo 'Cannot install Alto: /Applications is not writable.' >&2
  exit 1
fi
if [ -e /Applications/Alto.app ]; then
  installed_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' /Applications/Alto.app/Contents/Info.plist)"
  if [ "$installed_id" != 'software.petit.alto' ]; then
    echo 'Refusing to replace a different app at /Applications/Alto.app.' >&2
    exit 1
  fi
fi
staging_dir="$(mktemp -d /private/tmp/alto-install.XXXXXX)"
ditto dist/Alto.app "$staging_dir/Alto.app"
codesign --verify --deep --strict "$staging_dir/Alto.app"
osascript -e 'if application id "software.petit.alto" is running then tell application id "software.petit.alto" to quit'
# Allow Alto to finish any clipboard restoration before replacing its bundle.
for attempt in {1..50}; do
  if ! pgrep -x Alto >/dev/null; then break; fi
  sleep 0.1
done
if pgrep -x Alto >/dev/null; then
  echo 'Alto has not quit; installation stopped without replacing the running app.' >&2
  exit 1
fi
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [ -d /Applications/Alto.app ]; then
  mv /Applications/Alto.app "$staging_dir/Previous.app"
  "$lsregister" -u "$staging_dir/Previous.app" >/dev/null 2>&1 || true
fi
mv "$staging_dir/Alto.app" /Applications/Alto.app
# Only the installed copy may provide "Listen with Alto": a second registered
# bundle with the same identifier keeps the item out of Services menus.
"$lsregister" -u "$PWD/build/Build/Products/Release/Alto.app" >/dev/null 2>&1 || true
"$lsregister" -u "$PWD/build/Build/Products/Debug/Alto.app" >/dev/null 2>&1 || true
"$lsregister" -u "$PWD/dist/Alto.app" >/dev/null 2>&1 || true
"$lsregister" -f /Applications/Alto.app >/dev/null 2>&1 || true
/System/Library/CoreServices/pbs -flush || true
/System/Library/CoreServices/pbs -update || true
rm -rf "$staging_dir"
open /Applications/Alto.app
for attempt in {1..50}; do
  if pgrep -f '^/Applications/Alto.app/Contents/MacOS/Alto( |$)' >/dev/null; then
    echo 'Installed and running: /Applications/Alto.app'
    exit 0
  fi
  sleep 0.1
done
echo 'Installed Alto, but could not confirm that the installed process launched.' >&2
exit 1
