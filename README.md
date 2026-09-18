# claude-pet

Claude Code 와 Codex 세션 상태에 반응하는 macOS 데스크톱 펫. 화면 구석의 픽셀 펫이 지금 작업 중인지, 내 입력을 기다리는지, 실패했는지, 끝났는지를 애니메이션으로 보여준다.

- Claude Code 와 Codex(CLI·IDE 확장·데스크톱 앱) 세션을 함께 본다. 펫은 한 마리고, Codex 세션 말풍선에는 `Codex` 배지가 붙는다
- 세션이 여러 개면 펫은 에이전트를 가리지 않고 가장 급한 상태를 따른다 (입력 대기 > 실패 > 작업 중 > 끝남 > 유휴)
- 말풍선은 세션마다 하나씩, 급한 것이 펫에 가깝게 쌓인다. 평소에는 작업 중인 세션만 보이고 펫이나 말풍선에 마우스를 올리면 유휴 세션까지 펼쳐진다
- 말풍선을 누르면 그 세션이 돌고 있는 앱으로 가고, 닫기 버튼으로 하나씩 치울 수 있다
- 입력 대기·끝남·실패 상태에는 마지막 답변 미리보기가 붙는다. 마우스를 올리면 두 줄로 펴진다
- 펫을 클릭하면 가장 급한 세션이 돌고 있는 앱으로 이동한다 — Claude Desktop 이면 그 세션까지, 터미널·에디터·Codex 앱이면 그 앱까지
- 펫을 드래그해 원하는 위치에 두면 재시작해도 유지된다
- 펫 자산은 Codex 포맷(v1 8열×9행, v2 8열×11행)을 그대로 읽는다. 버전은 `pet.json` 의 `spriteVersionNumber` 로 정한다(생략 시 v1). [codex-pets.net](https://codex-pets.net) 의 펫을 `claude-pet add <id>` 로 설치한다

Anthropic 공식 프로젝트가 아니다. 개인이 만든 비공식 도구다.

## 요구 사항

- macOS 14 (Sonoma) 이상
- Claude Code, Codex, 또는 둘 다
- Command Line Tools (아래 참고)

Xcode 는 필요 없다. 용량이 큰 Xcode 대신 Command Line Tools 만 있으면 된다.

### Command Line Tools

이 앱은 미리 만든 바이너리를 받는 대신 내 컴퓨터에서 빌드한다. 그래서 애플이 무료로 주는 빌드 도구 묶음인 Command Line Tools 가 필요하다. 한 번 설치하면 다시 할 일은 없다.

설치되어 있는지 확인한다. 버전이 나오면 이미 있는 것이다.

```sh
pkgutil --pkg-info=com.apple.pkg.CLTools_Executables
```

없으면 설치한다. 설치 창이 뜨면 안내를 따른다.

```sh
xcode-select --install
```

**이미 설치되어 있어도 버전이 낮으면 Homebrew 가 빌드를 거부한다.** `Your Command Line Tools are too outdated` 라는 오류가 그것이다. 위 명령은 이미 설치된 경우 아무 일도 하지 않으니, 이때는 갱신해야 한다. 시스템 설정의 소프트웨어 업데이트에서 Command Line Tools 항목을 설치하면 된다. 터미널로 하려면 먼저 목록을 보고,

```sh
softwareupdate --list
```

거기 나온 `Label:` 값을 그대로 넘긴다. 제목이 아니라 레이블이어야 한다.

```sh
sudo softwareupdate --install "Command Line Tools for Xcode 26.6-26.6"
```

약 900MB 를 받고 재시작은 필요 없다.

## 설치

어느 쪽이든 내 컴퓨터에서 직접 빌드한다. 배포용 Apple Developer ID 서명이 없어서 미리 만든 바이너리를 받으면 Gatekeeper 가 막는다. 직접 빌드한 앱은 그런 제약이 없다.

### Homebrew

```sh
brew trust LoganBaek97/tap
brew install LoganBaek97/tap/claude-pet
claude-pet install-hooks
ln -sfn "$(brew --prefix)/opt/claude-pet/ClaudePet.app" /Applications/ClaudePet.app
claude-pet add guga
open /Applications/ClaudePet.app
```

Homebrew 7 부터 서드파티 tap 은 `brew trust` 로 신뢰를 먼저 밝혀야 읽힌다. Homebrew 는 앱을 자기 디렉터리에 두기 때문에 설정 변경과 `/Applications` 연결은 직접 한다. `brew upgrade` 를 해도 훅 경로는 그대로 쓸 수 있다.

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
3. `~/.claude/settings.json` 에 펫 훅 추가. `~/.codex` 디렉터리가 있으면 `~/.codex/hooks.json` 에도 추가

훅은 ` # claude-pet` 표식이 붙은 항목으로만 들어가고, 손대기 전에 설정 파일 백업을 남긴다. 되돌리려면 `claude-pet uninstall-hooks` 를 쓴다. 이때도 백업을 남긴다. 나중에 Codex 를 깔았다면 `claude-pet install-hooks codex` 로 그쪽만 더할 수 있다.

**Codex 는 한 단계가 더 있다.** Codex 는 사용자가 신뢰하지 않은 훅을 조용히 건너뛴다. 훅을 설치한 뒤 `codex` 를 열고 `/hooks` 에서 claude-pet 항목을 신뢰해야 펫이 반응한다. 신뢰는 훅 명령의 해시에 묶이므로 앱 경로가 바뀌면(예: 소스 빌드 → Homebrew) 다시 승인해야 한다. 승인 전에는 Codex 가 시작할 때 검토할 훅이 있다는 경고를 한 줄 띄운다.

## 명령

| 명령 | 설명 |
| --- | --- |
| `claude-pet add <id>` | codex-pets.net 에서 펫을 받아 설치 |
| `claude-pet use <id>` | 기본 펫 지정 |
| `claude-pet list` | 설치된 펫 목록 |
| `claude-pet status` | 훅 설치 여부와 살아 있는 세션 상태 |
| `claude-pet login-item on\|off` | 로그인 시 자동 실행 |
| `claude-pet install-hooks [claude\|codex]` | 훅 설치. 인자가 없으면 Claude 와, `~/.codex` 가 있으면 Codex 도 |
| `claude-pet uninstall-hooks [claude\|codex]` | 훅 제거. 대상 선택은 설치와 같다 |

## 동작 원리

Claude Code 와 Codex 의 훅(`hooks/hook.sh`)이 이벤트마다 `~/Library/Application Support/ClaudePet/state/<session_id>.json` 을 쓰고, 앱이 그 디렉터리를 감시해 상태를 합성한다.

훅은 세션을 돌리는 claude/codex 프로세스의 pid 도 함께 적는다(`agent_pid`). 앱이 그 pid 로 생사를 확인해서, 몇 시간 조용한 세션도 프로세스가 살아 있으면 계속 보여 주고 프로세스가 사라졌으면 바로 지운다. 이게 없으면 훅 이벤트만 보게 되어 30분간 아무 일도 없던 세션이 죽은 것으로 취급된다. pid 는 돌려 쓰이므로 번호만 믿지 않고 그 프로세스가 정말 claude/codex 인지도 확인한다. 훅은 어떤 경우에도 `exit 0` 이고 stdout 에 아무것도 쓰지 않아서 에이전트 동작에 끼어들지 않는다. 세션이 끝나면 상태 파일을 지운다.

두 에이전트의 훅은 설정 파일 모양과 stdin 필드(`session_id`, `cwd`, `hook_event_name`, `tool_name`)가 같아서 스크립트 하나를 같이 쓴다. Claude 는 `~/.claude/settings.json` 의 `hooks`, Codex 는 `~/.codex/hooks.json` 에 걸리고, Codex 쪽 명령에는 `--agent codex` 가 붙어 상태 파일의 `agent` 필드로 남는다. Codex 에는 `Notification`, `PostToolUseFailure`, `StopFailure` 이벤트가 없어서 Codex 세션은 "실패" 상태에 들어가지 않는다. 대신 사용자가 끊는 `Interrupt` 가 있고 이건 유휴로 간다. Codex 는 `SessionEnd` 와 `Interrupt` 훅을 최대 3초까지만 기다리므로 그 둘은 타임아웃 3초로 건다.

말풍선은 살아 있는 세션마다 한 장씩 뜬다. 카드에는 프로젝트 이름, 상태와 도구, 마지막 신호로부터 지난 시간이 담기고
Codex 세션은 `Codex` 배지가 붙는다. 평소에는 유휴가 아닌 세션만 최대 네 장까지 보여 주고 나머지는 "세션 N개 더" 로
세어 준다. 펫이나 말풍선에 마우스를 올리면 유휴 세션까지 펼쳐진다. 펫 위에 남은 화면 높이가 모자라면 그만큼만 띄운다.
입력 대기·끝남·실패 상태에는 마지막 답변 미리보기가 한 줄 붙는다. 그 카드에 마우스를 올리면 두 줄로 펴진다.
작업 중인 세션에는 붙이지 않는다. 마지막 답변이 계속 바뀌어 글자가 초마다 들썩이기 때문이다.
미리보기는 훅이 남긴 `transcript_path` 를 앱이 직접 읽어 만든다. 파일 끝 256KB 만 읽고, 파일이 자란 것만 다시 읽는다.
훅이 글자를 상태 파일에 적지 않는 이유가 있다. 훅은 POSIX sh 이고 JSON 을 `printf` 로 손수 짜기 때문에
모델이 낸 임의의 글자를 끼워 넣으면 파일이 깨진다.

말풍선에 마우스를 올리면 오른쪽에 닫기 버튼이 나온다. 누르면 그 말풍선만 치운다. 세션에는 아무 영향이 없고,
그 세션의 상태가 달라지면 다시 뜬다. 알림을 지우는 것과 같다.

말풍선 바깥은 클릭이 아래 창으로 그대로 통과한다. 메뉴의 "대화창 끄기" 로 말풍선 전체를 끌 수 있다.

세션을 중단하거나 세션에 메시지를 보내는 기능은 넣지 않았다. Claude Code 로컬 대화형 세션에 외부 프로그램이
메시지를 넣는 공식 경로가 없고(`claude stop` 은 `--bg` 배경 세션 전용, `--cloud … -p` 는 클라우드 세션 전용),
중단도 프로세스에 SIGINT 를 보내면 턴만 끊기는 게 아니라 세션이 죽는다. Esc 처럼 턴만 끊으려면 키 입력을 그
터미널에 넣어야 하는데 macOS 에는 외부 앱이 그럴 방법이 없다(`TIOCSTI` 미지원). 손쉬운 사용 권한을 받아 키를
합성하는 길은 남아 있지만 권한을 요구하지 않기로 했다.

펫이나 말풍선을 누르면 상태 파일에 기록된 호스트를 보고 갈 곳을 정한다. Claude Desktop 세션은 환경변수 `CLAUDE_CODE_HOST_SESSION_ID` 가 있어서 `claude://code/continue?session=local_...` 딥링크로 그 세션까지 간다(앱이 받는 형식은 `^local_[A-Za-z0-9-]{1,64}$` 뿐이라 Claude Code 쪽 세션 UUID 를 넣으면 거절당한다). 그 밖의 호스트는 훅이 조상 프로세스에서 찾아 둔 `.app` 번들과 pid 로 그 앱을 앞으로 가져온다.

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
