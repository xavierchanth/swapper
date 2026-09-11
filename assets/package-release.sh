#!/usr/bin/env bash
set -euo pipefail

app=${1:?Usage: package-release.sh APP OUTPUT_DIRECTORY}
output=${2:?Usage: package-release.sh APP OUTPUT_DIRECTORY}
test -x "$app/Contents/MacOS/XMT"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" = com.xavierchanth.xmt
/usr/bin/lipo "$app/Contents/MacOS/XMT" -verify_arch arm64 x86_64
/usr/bin/codesign --verify --deep --strict "$app"
mkdir -p "$output"
for filename in XMT-macos.zip XMT-macos.tar.gz SHA256SUMS RELEASE-NOTES.md; do
  test ! -e "$output/$filename" || { echo "Refusing to replace $output/$filename" >&2; exit 1; }
done
stage=$(mktemp -d)
trap 'rm -r "$stage"' EXIT
mkdir "$stage/XMT-macos"
/usr/bin/ditto "$app" "$stage/XMT-macos/XMT.app"
/usr/bin/ditto -c -k --keepParent "$stage/XMT-macos/XMT.app" "$output/XMT-macos.zip"
COPYFILE_DISABLE=1 /usr/bin/tar -czf "$output/XMT-macos.tar.gz" -C "$stage" XMT-macos
cp "$(dirname "$0")/release-notes.md" "$output/RELEASE-NOTES.md"
(cd "$output" && shasum -a 256 XMT-macos.zip XMT-macos.tar.gz > SHA256SUMS)
