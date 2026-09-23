# claude-pet

Claude Code 와 Codex 세션 상태에 반응하는 macOS·Windows 데스크톱 펫. 화면 구석의 픽셀 펫이 지금 작업 중인지, 내 입력을 기다리는지, 실패했는지, 끝났는지를 애니메이션으로 보여준다.

- Claude Code 와 Codex(CLI·IDE 확장·데스크톱 앱) 세션을 함께 본다. 펫은 한 마리고, Codex 세션 말풍선에는 `Codex` 배지가 붙는다
- 세션이 여러 개면 펫은 에이전트를 가리지 않고 가장 급한 상태를 따른다 (입력 대기 > 실패 > 작업 중 > 끝남 > 유휴)
- 말풍선은 세션마다 하나씩, 급한 것이 펫에 가깝게 쌓인다. 평소에는 작업 중인 세션만 보이고 펫이나 말풍선에 마우스를 올리면 유휴 세션까지 펼쳐진다
- 말풍선을 누르면 그 세션이 돌고 있는 앱으로 가고, 닫기 버튼으로 하나씩 치울 수 있다
- 입력 대기·끝남·실패 상태에는 마지막 답변 미리보기가 붙는다. 마우스를 올리면 두 줄로 펴진다
- 펫을 클릭하면 가장 급한 세션이 돌고 있는 앱으로 이동한다 — Claude Desktop 이면 그 세션까지, 터미널·에디터·Codex 앱이면 그 앱까지
- 펫을 드래그해 원하는 위치에 두면 재시작해도 유지된다. 끌려가는 방향으로 달리고, 위아래로 끌면 뛰고, 놓으면 착지한다
- 작업 중인 세션이 있는 동안 펫은 계속 움직인다. 한동안 아무 일이 없으면 가라앉아 느려진다
- 시스템 "동작 줄이기"를 켜 두면 펫도 멈춘다. 그래도 움직이길 바라면 메뉴에서 켤 수 있다
- 펫 자산은 Codex 포맷(v1 8열×9행, v2 8열×11행)을 그대로 읽는다. 버전은 `pet.json` 의 `spriteVersionNumber` 로 정한다(생략 시 v1). [codex-pets.net](https://codex-pets.net) 의 펫을 `claude-pet add <id>` 로 설치한다

Anthropic 공식 프로젝트가 아니다. 개인이 만든 비공식 도구다.

## 요구 사항

- macOS 14 (Sonoma) 이상, 또는 Windows 10 1809 이상 / Windows 11 (64비트)
- Claude Code, Codex, 또는 둘 다
- macOS: Command Line Tools (아래 참고). Windows: 아무것도 더 필요 없다 (Claude Code 를 쓰려면 Claude Code 자체가 요구하는 Git for Windows 가 있으면 된다)

Windows 지원은 새로 들어갔고 **실기기에서 검증되지 않았다.** 빌드·단위 테스트·훅 통합 테스트는 CI 에서 돌지만 오버레이 창·트레이·클릭 이동은 실제 Windows 에서 확인해 준 사람이 아직 없다. 문제가 있으면 이슈로 알려 주면 좋겠다. 그때까지 Windows 릴리스는 pre-release 로 표시한다.

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

### Windows

Windows 는 미리 만든 zip 을 받는다. macOS 와 달리 서명 없는 실행 파일을 시스템이 막지 않는다(SmartScreen 경고만 뜬다). [Releases](https://github.com/LoganBaek97/claude-pet/releases) 에서 `ClaudePet-windows-x64.zip` 을 받아 풀고, 그 폴더에서 PowerShell 을 연다.

```powershell
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
```

이 스크립트는 네 가지를 한다.

1. `%LOCALAPPDATA%\Programs\ClaudePet` 으로 복사하고 다운로드 표식(Mark-of-the-Web)을 지운다
2. 그 폴더를 사용자 PATH 에 넣는다 (새 터미널부터 `claude-pet` 이 잡힌다)
3. `%USERPROFILE%\.claude\settings.json` 에 펫 훅을 추가한다. `%USERPROFILE%\.codex` 가 있으면 `.codex\hooks.json` 에도 추가한다
4. Visual C++ 재배포 패키지가 없으면 설치 링크를 알려 준다

그다음은 macOS 와 같다.

```powershell
claude-pet add guga
& "$env:LOCALAPPDATA\Programs\ClaudePet\ClaudePetWin.exe"
```

`ClaudePetWin.exe` 를 처음 실행하면 SmartScreen 이 "알 수 없는 게시자" 라고 막을 수 있다. "추가 정보" → "실행" 을 누른다. 로그인 시 자동 실행은 트레이 아이콘 메뉴나 `claude-pet login-item on` 으로 켠다.

소스에서 빌드하려면 [Swift for Windows](https://www.swift.org/install/windows/) 툴체인이 필요하다(Visual Studio Build Tools 를 함께 깐다). 그 뒤 `powershell -ExecutionPolicy Bypass -File scripts\bundle-windows.ps1` 이 `dist\ClaudePet-windows-x64\` 를 만든다.

Windows 에서 아직 안 되는 것:

- WSL 안에서 도는 Claude Code/Codex. 훅이 Linux 쪽에서 실행되어 Windows 앱이 보지 못한다
- npm 으로 설치한 Claude Code 의 프로세스 생사 확인. `node.exe` 로 돌아서 claude 프로세스로 인식하지 못하고, 30분 동안 이벤트가 없으면 죽은 세션으로 본다(macOS 의 npm 설치도 같다)
- Claude Desktop 의 Code 탭처럼 터미널 없는 곳에서 시작한 세션은 훅이 돌 때마다 콘솔 창이 잠깐 비칠 수 있다. Claude Code 가 훅을 `bash.exe` 로 띄우기 때문이고 이 앱이 통제할 수 없다
- WebP 펫은 Windows 11 의 기본 WebP 코덱이나 Windows 10 의 Microsoft Store "WebP Image Extensions" 가 있어야 뜬다. 없으면 내장 기본 펫으로 대체하고 메뉴에 이유를 적는다

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
| `claude-pet hook [--agent claude\|codex]` | (내부용, Windows) 에이전트가 이벤트마다 부르는 네이티브 훅. stdin 의 이벤트 JSON 을 상태 파일로 기록한다 |

## 동작 원리

Claude Code 와 Codex 의 훅(`hooks/hook.sh`)이 이벤트마다 `~/Library/Application Support/ClaudePet/state/<session_id>.json` 을 쓰고, 앱이 그 디렉터리를 감시해 상태를 합성한다. Windows 에서는 상태 디렉터리가 `%LOCALAPPDATA%\ClaudePet\state` 이고 훅은 셸 스크립트 대신 `claude-pet.exe hook` 이다. Git Bash 의 `ps` 는 MSYS 프로세스만 보여서 스크립트로는 에이전트 pid 를 못 찾기 때문이다. Claude Code 는 이 명령을 Git Bash(`sh -c`)로 띄우므로 경로를 `C:/…` 슬래시로 적고 항목에 `"shell": "bash"` 를 붙인다. Codex 는 `commandWindows` 에 PowerShell 문장을 받는데, PowerShell 은 자식에게 stdin 을 넘길 때 코드페이지를 바꾸므로 UTF-8 을 강제하고 `[Console]::In.ReadToEnd() | & "…\claude-pet.exe" hook --agent codex` 로 넘긴다. 두 형태 모두 CI 가 실제 셸로 돌려 한글 경로가 깨지지 않는지 확인한다.

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

Windows 에서는 `swift test` 와 `pwsh Tests/hook/run.ps1`(네이티브 훅 통합 테스트), `swift run ClaudePetWin` 이다. Core 는 두 플랫폼에서 같은 코드를 쓰고, 앱 레이어만 `Sources/ClaudePetApp`(AppKit)과 `Sources/ClaudePetWin`(Win32)으로 갈린다. 파일 단위 `#if os(macOS)` / `#if os(Windows)` 로 나뉘어 어느 쪽에서든 `swift build` 가 전 타깃을 돈다. GitHub Actions 가 두 OS 에서 빌드·테스트하고, `v*` 태그를 올리면 Windows zip 을 릴리스에 붙인다.

`scripts/bundle.sh` 의 release 빌드는 기본으로 arm64·x86_64 유니버설을 만든다. 현재 아키텍처만 필요하면 `CLAUDE_PET_UNIVERSAL=0 sh scripts/bundle.sh` 를 쓴다.

## 라이선스

코드는 [MIT](LICENSE). 기본 펫 스프라이트는 이 저장소에서 만든 것이고 같은 라이선스를 따른다. `claude-pet add` 로 받는 펫은 codex-pets.net 이 배포하는 자산이라 각자의 조건을 따른다.
