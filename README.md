# claude-pet

Claude Code 세션 상태에 반응하는 macOS 데스크톱 펫. 화면 구석의 픽셀 펫이 지금 작업 중인지, 내 입력을 기다리는지, 실패했는지, 끝났는지를 애니메이션으로 보여준다.

- 세션이 여러 개면 가장 급한 상태를 따른다 (입력 대기 > 실패 > 작업 중 > 끝남 > 유휴)
- 펫을 클릭하면 해당 Claude Desktop 세션으로 이동한다
- 펫을 드래그해 원하는 위치에 두면 재시작해도 유지된다
- 펫 자산은 Codex v1 포맷을 그대로 읽는다. [codex-pets.net](https://codex-pets.net) 의 펫을 `claude-pet add <id>` 로 설치한다

Anthropic 공식 프로젝트가 아니다. 개인이 만든 비공식 도구다.

## 요구 사항

- macOS 14 (Sonoma) 이상
- Xcode Command Line Tools (`xcode-select --install`)
- Claude Code

## 설치

어느 쪽이든 내 컴퓨터에서 직접 빌드한다. 배포용 Apple Developer ID 서명이 없어서 미리 만든 바이너리를 받으면 Gatekeeper 가 막는다. 직접 빌드한 앱은 그런 제약이 없다.

### Homebrew

```sh
brew install LoganBaek97/tap/claude-pet
claude-pet install-hooks
ln -sfn "$(brew --prefix)/opt/claude-pet/ClaudePet.app" /Applications/ClaudePet.app
claude-pet add guga
open /Applications/ClaudePet.app
```

Homebrew 는 앱을 자기 디렉터리에 두기 때문에 설정 변경과 `/Applications` 연결은 직접 한다. `brew upgrade` 를 해도 훅 경로는 그대로 쓸 수 있다.

### 소스에서 직접

```sh
git clone https://github.com/LoganBaek97/claude-pet.git
cd claude-pet
sh scripts/bundle.sh
sh scripts/install.sh
claude-pet add guga
open /Applications/ClaudePet.app
```

`scripts/install.sh` 는 세 가지를 한다.

1. `dist/ClaudePet.app` 을 `/Applications` 로 복사
2. 쓸 수 있는 `bin` 디렉터리에 `claude-pet` CLI 링크 생성
3. `~/.claude/settings.json` 에 펫 훅 추가

훅은 ` # claude-pet` 표식이 붙은 항목으로만 들어가고, 손대기 전에 설정 파일 백업을 남긴다. 되돌리려면 `claude-pet uninstall-hooks` 를 쓴다. 이때도 백업을 남긴다.

## 명령

| 명령 | 설명 |
| --- | --- |
| `claude-pet add <id>` | codex-pets.net 에서 펫을 받아 설치 |
| `claude-pet use <id>` | 기본 펫 지정 |
| `claude-pet list` | 설치된 펫 목록 |
| `claude-pet status` | 훅 설치 여부와 살아 있는 세션 상태 |
| `claude-pet login-item on\|off` | 로그인 시 자동 실행 |
| `claude-pet install-hooks` | 훅 설치 |
| `claude-pet uninstall-hooks` | 훅 제거 |

## 동작 원리

Claude Code 훅(`hooks/hook.sh`)이 이벤트마다 `~/Library/Application Support/ClaudePet/state/<session_id>.json` 을 쓰고, 앱이 그 디렉터리를 감시해 상태를 합성한다. 훅은 어떤 경우에도 `exit 0` 이고 stdout 에 아무것도 쓰지 않아서 Claude Code 동작에 끼어들지 않는다. 세션이 끝나면 상태 파일을 지운다.

설계 문서: [docs/superpowers/specs/2026-09-15-claude-pet-design.md](docs/superpowers/specs/2026-09-15-claude-pet-design.md)

## 개발

```sh
swift test                 # Core 단위 테스트
sh Tests/hook/run.sh       # 훅 스크립트 테스트
swift build && .build/debug/ClaudePetApp
```

`scripts/bundle.sh` 의 release 빌드는 기본으로 arm64·x86_64 유니버설을 만든다. 현재 아키텍처만 필요하면 `CLAUDE_PET_UNIVERSAL=0 sh scripts/bundle.sh` 를 쓴다.

## 라이선스

코드는 [MIT](LICENSE). 기본 펫 스프라이트는 이 저장소에서 만든 것이고 같은 라이선스를 따른다. `claude-pet add` 로 받는 펫은 codex-pets.net 이 배포하는 자산이라 각자의 조건을 따른다.
