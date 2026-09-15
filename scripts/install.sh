#!/bin/sh
# dist/ClaudePet.app 을 /Applications 에 넣고 CLI 링크를 만든 뒤 훅을 설치한다.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/dist/ClaudePet.app"
[ -d "$APP" ] || { echo "먼저 sh scripts/bundle.sh 를 실행하세요"; exit 1; }
pkill -x ClaudePetApp 2>/dev/null || true
rm -rf /Applications/ClaudePet.app
cp -R "$APP" /Applications/ClaudePet.app
CLI=/Applications/ClaudePet.app/Contents/MacOS/claude-pet

# 쓸 수 있는 첫 번째 bin 디렉터리에 링크한다. Apple Silicon 의 /usr/local/bin 은
# 기본으로 없거나 sudo 가 필요해서 Homebrew prefix 와 ~/.local/bin 을 함께 본다.
BINDIR=""
for d in /usr/local/bin "$(brew --prefix 2>/dev/null || echo /nonexistent)/bin" "$HOME/.local/bin"; do
  case "$d" in /nonexistent/*) continue;; esac
  if [ -d "$d" ] && [ -w "$d" ]; then BINDIR=$d; break; fi
done
[ -n "$BINDIR" ] || { mkdir -p "$HOME/.local/bin" && BINDIR="$HOME/.local/bin"; }

if ln -sf "$CLI" "$BINDIR/claude-pet" 2>/dev/null; then
  echo "CLI: $BINDIR/claude-pet"
  case ":$PATH:" in
    *":$BINDIR:"*) ;;
    *) echo "  주의: $BINDIR 이 PATH 에 없습니다. 셸 설정에 추가하세요:"
       echo "    echo 'export PATH=\"$BINDIR:\$PATH\"' >> ~/.zshrc";;
  esac
else
  echo "CLI 링크를 만들지 못했습니다. 직접 실행: sudo ln -sf $CLI /usr/local/bin/claude-pet"
fi

"$CLI" install-hooks
echo
echo "다음 단계:"
echo "  claude-pet add guga        # 펫 받기"
echo "  open /Applications/ClaudePet.app"
echo "  claude-pet login-item on   # 로그인 시 자동 실행"
