#!/bin/sh
# swift build 결과를 dist/ClaudePet.app 으로 감싼다. 사용법: sh scripts/bundle.sh [debug|release]
# release 는 Apple Silicon + Intel 유니버설로 만든다. debug 는 현재 아키텍처만.
set -eu
CONFIG=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

command -v swift >/dev/null 2>&1 || {
  echo "swift 가 없습니다. Xcode Command Line Tools 를 설치하세요: xcode-select --install" >&2
  exit 1
}

# release 는 기본으로 유니버설. CLAUDE_PET_UNIVERSAL=0 이면 현재 아키텍처만 만든다.
# Homebrew 처럼 설치하는 기계에서 직접 빌드하는 경우에 쓴다.
if [ "$CONFIG" = release ] && [ "${CLAUDE_PET_UNIVERSAL:-1}" = 1 ]; then
  set -- -c release --arch arm64 --arch x86_64
else
  set -- -c "$CONFIG"
fi
swift build "$@" 2>&1 | tail -1
BIN=$(swift build "$@" --show-bin-path)

APP="dist/ClaudePet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/pets"
cp "$BIN/ClaudePetApp" "$BIN/claude-pet" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp hooks/hook.sh "$APP/Contents/Resources/hook.sh"
cp -R Resources/pets/default "$APP/Contents/Resources/pets/"
chmod +x "$APP/Contents/MacOS/"* "$APP/Contents/Resources/hook.sh"
# 로그인 항목(SMAppService)은 서명된 번들을 요구한다. 로컬용 ad-hoc 서명.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "warning: codesign failed; login item may not work"
echo "built $APP ($(lipo -archs "$APP/Contents/MacOS/ClaudePetApp"))"
