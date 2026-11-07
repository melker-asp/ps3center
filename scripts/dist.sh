#!/bin/bash
# Builds what a GitHub release ships, into .build/dist:
#   PS3-Center.dmg   the app for Apple silicon and Intel; open it and drag the app to Applications
#   ps3-cli.zip      the ps3 command for Apple silicon and Intel
#   SHA256SUMS.txt   checksums of both
#
#   scripts/dist.sh 1.2.0        (or: make dist VERSION=1.2.0)
#
# The version must already be in App/project.yml (MARKETING_VERSION) and Sources/ps3/PS3.swift
# (version:), so a tag can't publish files that call themselves something else.
# Both are signed ad hoc ("-"). There is no Developer ID, so macOS asks the user to allow the app
# once; README.md → Download says how. The file names carry no version, so
# github.com/<repo>/releases/latest/download/PS3-Center.dmg always points at the newest release.
set -euo pipefail

version="${1:?usage: scripts/dist.sh <version>, e.g. scripts/dist.sh 1.2.0}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "The version should look like 1.2.0, not \"$version\"." >&2
    exit 1
fi

cd "$(dirname "$0")/.."
root="$PWD"

app_version="$(sed -n 's/^ *MARKETING_VERSION: *//p' App/project.yml)"
cli_version="$(sed -n 's/^ *version: "\([^"]*\)".*/\1/p' Sources/ps3/PS3.swift)"
if [[ "$app_version" != "$version" || "$cli_version" != "$version" ]]; then
    echo "Asked for $version, but App/project.yml says \"$app_version\" and Sources/ps3/PS3.swift says \"$cli_version\"." >&2
    echo "Set both to $version, commit, and tag that commit." >&2
    exit 1
fi

# Both architectures, read from `lipo -archs` (`lipo -verify_arch` misreads its arguments in Xcode 27).
universal() {
    local archs
    archs=" $(lipo -archs "$1") "
    if [[ "$archs" != *" arm64 "* || "$archs" != *" x86_64 "* ]]; then
        echo "$1 is built for$archs, not arm64 and x86_64." >&2
        exit 1
    fi
}

dist="$root/.build/dist"
derived="$root/.build/xcode-dist"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
rm -rf "$dist"
mkdir -p "$dist"

echo "→ The app $version (arm64 + x86_64)"
(cd App && xcodegen --quiet)
xcodebuild -project App/PS3Center.xcodeproj -scheme PS3Center -configuration Release \
    -derivedDataPath "$derived" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -quiet build
app="$derived/Build/Products/Release/PS3 Center.app"
codesign --verify --deep --strict "$app"
universal "$app/Contents/MacOS/PS3 Center"

echo "→ PS3-Center.dmg"
mkdir "$stage/dmg"
ditto "$app" "$stage/dmg/PS3 Center.app"
ln -s /Applications "$stage/dmg/Applications"
# hdiutil now and then fails with "Resource busy" on GitHub's runners; a second try works.
for attempt in 1 2 3; do
    if hdiutil create -quiet -volname "PS3 Center" -srcfolder "$stage/dmg" -fs HFS+ -format UDZO \
        -ov "$dist/PS3-Center.dmg"; then
        break
    fi
    [[ $attempt == 3 ]] && exit 1
    sleep 5
done
# What a user gets out of the image must still carry a valid signature.
mount="$stage/mount"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$dist/PS3-Center.dmg"
codesign --verify --deep --strict "$mount/PS3 Center.app"
hdiutil detach -quiet "$mount"

echo "→ ps3-cli.zip (arm64 + x86_64)"
# One architecture at a time, each in a build folder of its own, then lipo. `swift build` with two
# --arch switches to the XCBuild backend, which in Xcode 16 (GitHub's runner) rejects
# `.swiftLanguageMode(.v6)`; and Xcode 27's default backend puts every architecture in the same
# .build/out folder, so without --scratch-path the second build overwrites the first.
slices=()
for arch in arm64 x86_64; do
    scratch="$root/.build/dist-$arch"
    swift build -c release --arch "$arch" --scratch-path "$scratch" --product ps3
    slices+=("$(swift build -c release --arch "$arch" --scratch-path "$scratch" --show-bin-path)/ps3")
done
mkdir "$stage/cli"
lipo -create -output "$stage/cli/ps3" "${slices[@]}"
codesign --force --sign - "$stage/cli/ps3"
universal "$stage/cli/ps3"
[[ "$("$stage/cli/ps3" --version)" == "$version" ]]
(cd "$stage/cli" && ditto -c -k ps3 "$dist/ps3-cli.zip")

(cd "$dist" && shasum -a 256 PS3-Center.dmg ps3-cli.zip > SHA256SUMS.txt)
echo "→ Done: $dist"
ls -lh "$dist"
