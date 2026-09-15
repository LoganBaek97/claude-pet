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

if [ "$CONFIG" = release ]; then
  swift build -c release --arch arm64 --arch x86_64 2>&1 | tail -1
  BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
else
  swift build -c "$CONFIG" 2>&1 | tail -1
  BIN=$(swift build -c "$CONFIG" --show-bin-path)
fi

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
