#!/bin/zsh

set -euo pipefail

SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
CONFIGURATION="${1:-debug}"
if [[ "${CONFIGURATION}" != debug && "${CONFIGURATION}" != release ]]; then
    echo "Usage: $0 [debug|release]" >&2
    exit 2
fi
APP_NAME="MK Studio Upkeep"
EXECUTABLE_NAME="ProducerUpToDate"
# A labelled build keeps a running test application's bundle untouched.
BUILD_LABEL="${STUDIO_UPKEEP_BUILD_LABEL:-${CONFIGURATION}}"
if [[ ! "$BUILD_LABEL" =~ '^[a-zA-Z0-9_-]+$' ]]; then
    echo "Build label must contain only letters, digits, underscores or hyphens." >&2
    exit 2
fi
BUILD_DIRECTORY="${PROJECT_DIRECTORY}/build/${BUILD_LABEL}"
FINAL_APP_DIRECTORY="${BUILD_DIRECTORY}/${APP_NAME}.app"
STAGING_DIRECTORY="$(mktemp -d "/tmp/studio-upkeep-package.XXXXXX")"
APP_DIRECTORY="${STAGING_DIRECTORY}/${APP_NAME}.app"
CONTENTS_DIRECTORY="${APP_DIRECTORY}/Contents"
CLANG_CACHE_DIRECTORY="${PROJECT_DIRECTORY}/.build/clang-module-cache"
SWIFTPM_CACHE_DIRECTORY="${PROJECT_DIRECTORY}/.build/swiftpm-module-cache"
ASSET_INFO_PLIST="${BUILD_DIRECTORY}/asset-info.plist"

trap 'rm -rf "${STAGING_DIRECTORY}"' EXIT

cd "${PROJECT_DIRECTORY}"

mkdir -p "${CLANG_CACHE_DIRECTORY}"
mkdir -p "${SWIFTPM_CACHE_DIRECTORY}"
mkdir -p "${BUILD_DIRECTORY}"


export CLANG_MODULE_CACHE_PATH="${CLANG_CACHE_DIRECTORY}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_CACHE_DIRECTORY}"

swift build --disable-sandbox -c "${CONFIGURATION}" --arch arm64 --arch x86_64 \
    -Xswiftc -debug-prefix-map -Xswiftc "${PROJECT_DIRECTORY}=." \
    -Xswiftc -file-prefix-map -Xswiftc "${PROJECT_DIRECTORY}=."
SWIFT_BINARY_DIRECTORY="$(
    swift build --disable-sandbox -c "${CONFIGURATION}" --arch arm64 --arch x86_64 --show-bin-path
)"

mkdir -p "${CONTENTS_DIRECTORY}/MacOS"
mkdir -p "${CONTENTS_DIRECTORY}/Resources"

cp "${SWIFT_BINARY_DIRECTORY}/${EXECUTABLE_NAME}" \
    "${CONTENTS_DIRECTORY}/MacOS/${EXECUTABLE_NAME}"
cp "${PROJECT_DIRECTORY}/Resources/Info.plist" \
    "${CONTENTS_DIRECTORY}/Info.plist"
xcrun actool "${PROJECT_DIRECTORY}/Resources/Assets.xcassets" \
    --compile "${CONTENTS_DIRECTORY}/Resources" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "${ASSET_INFO_PLIST}"

# Package only the app's notices; no release catalogue is distributed with Core.
cp "${PROJECT_DIRECTORY}/THIRD_PARTY_NOTICES.md" "${CONTENTS_DIRECTORY}/Resources/THIRD_PARTY_NOTICES.md"
cp "${PROJECT_DIRECTORY}/LICENSE" "${CONTENTS_DIRECTORY}/Resources/LICENSE"
cp "${PROJECT_DIRECTORY}/COMMERCIAL_LICENSE.md" "${CONTENTS_DIRECTORY}/Resources/COMMERCIAL_LICENSE.md"
cp "${PROJECT_DIRECTORY}/PRIVACY.md" "${CONTENTS_DIRECTORY}/Resources/PRIVACY.md"

chmod +x "${CONTENTS_DIRECTORY}/MacOS/${EXECUTABLE_NAME}"
xcrun lipo "${CONTENTS_DIRECTORY}/MacOS/${EXECUTABLE_NAME}" -verify_arch arm64 x86_64

if [[ "${CONFIGURATION}" == release ]]; then
    xcrun strip -S "${CONTENTS_DIRECTORY}/MacOS/${EXECUTABLE_NAME}"
fi
xattr -cr "${APP_DIRECTORY}"
codesign --force --options runtime --entitlements "${PROJECT_DIRECTORY}/Resources/StudioUpkeep.entitlements" --sign - "${APP_DIRECTORY}"
if xattr -p com.apple.FinderInfo "${APP_DIRECTORY}" >/dev/null 2>&1; then
    xattr -d com.apple.FinderInfo "${APP_DIRECTORY}"
fi
codesign --verify --deep --strict "${APP_DIRECTORY}"

if [[ -e "${FINAL_APP_DIRECTORY}" ]]; then
    BACKUP_DIRECTORY="${PROJECT_DIRECTORY}/build/backups/$(date +%Y%m%d-%H%M%S)-$$-${CONFIGURATION}"
    mkdir -p "${BACKUP_DIRECTORY}"
    mv "${FINAL_APP_DIRECTORY}" "${BACKUP_DIRECTORY}/${APP_NAME}.app"
fi
ditto --norsrc --noextattr "${APP_DIRECTORY}" "${FINAL_APP_DIRECTORY}"
codesign --verify --deep --strict "${FINAL_APP_DIRECTORY}"
cmp "${PROJECT_DIRECTORY}/LICENSE" "${FINAL_APP_DIRECTORY}/Contents/Resources/LICENSE"
if [[ "${CONFIGURATION}" == release ]]; then
    python3 scripts/audit-artifact.py "${FINAL_APP_DIRECTORY}"
fi

echo "${FINAL_APP_DIRECTORY}"
