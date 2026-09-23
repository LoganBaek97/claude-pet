# claude-pet 설계

작성일: 2026-09-15 (2026-09-17 Codex 지원 추가, 2026-09-23 Windows 지원 추가)
대상: macOS 26 과 Windows 10/11, Claude Desktop(Code 탭)과 Claude Code CLI, Codex(CLI·IDE 확장·데스크톱 앱)

## 목적

Codex 앱의 pet과 같은 경험을 Claude Code 사용자에게 준다. 화면 구석에 항상 떠 있는 작은 픽셀 펫이 Claude 세션들의 상태(작업 중, 입력 대기, 실패, 리뷰 대기, 유휴)에 맞춰 애니메이션을 바꾸고, 클릭하면 해당 세션으로 이동한다.

Claude Code와 Desktop 앱에는 UI 확장 지점이 없으므로 별도 오버레이 앱으로 만들고, 훅으로 상태를 받는다. 펫 자산은 Codex v1 펫 포맷을 그대로 채택해 codex-pets.net의 펫을 재사용한다.

Codex도 같은 모양의 훅을 제공하므로 두 에이전트를 한 펫으로 본다. 상태 파일에 `agent` 필드를 두고, 합성은 에이전트를 가리지 않으며, Codex 세션만 말풍선 앞에 이름을 붙인다.

## 범위

v1에 포함:

- 훅 스크립트와 세션별 상태 파일
- Swift/AppKit 오버레이 앱: 스프라이트 재생, 말풍선, 클릭 이동, 메뉴바 메뉴
- 다중 세션 우선순위 합성
- CLI: 훅 설치/제거, 펫 설치(codex-pets.net), 기본 펫 지정, 로그인 항목
- 내장 기본 펫 하나

v1에서 제외:

- 펫 생성(hatch, 이미지 생성)
- Linux, WSL 안의 에이전트 (Windows 네이티브는 아래 "Windows" 절)
- 세션마다 펫 여러 마리
- 코드 서명, 공증, 배포 패키징

## 구성 요소

```
Claude Code ──(hook stdin JSON)──▶ hooks/hook.sh
Codex ────────(hook stdin JSON)──▶ hooks/hook.sh --agent codex
                                      │ 원자적 쓰기
                                      ▼
                  ~/Library/Application Support/ClaudePet/state/<session_id>.json
                                      │ FSEvents 감시 + 1초 폴링
                                      ▼
                                ClaudePet.app ──▶ 오버레이 창(스프라이트, 말풍선)
                                      │            메뉴바 메뉴
                                      └─ 클릭 ──▶ open claude://code/continue?session=<id>

claude-pet CLI ──▶ ~/.claude/settings.json (Claude 훅 등록)
               ──▶ ~/.codex/hooks.json       (Codex 훅 등록, ~/.codex 가 있을 때)
               ──▶ ~/Library/Application Support/ClaudePet/pets/<id>/ (펫 설치)
```

### 훅 스크립트 `hooks/hook.sh`

- POSIX sh, 외부 의존성 없음(`cat`, `sed`, `mkdir`, `mv`만 사용). 목표 실행 시간 50ms 이내.
- 첫 인자로 `--agent claude|codex`를 받는다. 없거나 모르는 값이면 `claude`. 값은 상태 파일의 `agent`로 남는다.
- `CLAUDE_CODE_HOST_SESSION_ID`는 Claude일 때만 본다. Claude Desktop 터미널에서 띄운 Codex도 이 변수를 물려받지만 그 세션은 Claude 것이 아니다.
- Codex는 `codex exec`처럼 짧은 세션에서도 SessionEnd를 보내 파일을 지운다. 훅은 Codex 샌드박스(read-only 포함) 바깥에서 돌아 상태 디렉터리 쓰기가 막히지 않는다(2026-09-17 Codex 0.154 실측).
- stdin 전체를 읽고 `hook_event_name`, `session_id`, `tool_name`, `cwd`를 `sed`로 뽑는다. `session_id`가 없으면 아무것도 쓰지 않는다.
- 이벤트를 상태로 바꾼 뒤 `state/<session_id>.json.tmp`에 쓰고 `mv`로 교체한다.
- `SessionEnd`는 해당 파일을 삭제한다.
- 어떤 경우에도 exit 0. stdout에는 아무것도 쓰지 않는다.

이벤트 → 상태:

| 이벤트 | 상태 |
| --- | --- |
| SessionStart | idle |
| SessionEnd | (파일 삭제) |
| UserPromptSubmit, PreToolUse, PostToolUse | running |
| PermissionRequest, Notification | waiting |
| PostToolUseFailure, StopFailure | failed |
| Stop | review |
| Interrupt (Codex 전용) | idle |
| 그 외(SubagentStart, SubagentStop 포함) | 무시 |

Codex에는 Notification, PostToolUseFailure, StopFailure가 없어 Codex 세션은 failed에 들어가지 않는다. Codex 훅의 한계로 받아들인다.

상태 파일:

```json
{"session_id":"…","state":"waiting","event":"PermissionRequest","tool":"Bash","cwd":"/path/to/project","agent":"codex","ts":1789000000}
```

`ts`는 Unix 초. `tool`과 `cwd`는 없으면 빈 문자열. `transcript`는 훅 입력의 `transcript_path`이고, 앱이 이 파일의 끝 256KB를 읽어 마지막 어시스턴트 발화를 말풍선 미리보기로 쓴다. 발화 글자 자체는 여기 적지 않는다. 훅은 JSON을 `printf`로 손수 짜기 때문에 모델이 낸 임의의 글자(제어문자, 따옴표)를 끼워 넣으면 파일이 깨진다. `agent`는 `claude` 또는 `codex`이고, 예전 훅이 쓴 파일처럼 없거나 모르는 값이면 앱은 `claude`로 읽는다.

### 에이전트 (`ClaudePetCore.Agent`)

에이전트마다 다른 것은 이 타입 하나에 모은다.

| | Claude | Codex |
| --- | --- | --- |
| 훅 파일 | `~/.claude/settings.json`의 `hooks` | `~/.codex/hooks.json` (루트 `hooks` 키, 같은 모양) |
| 걸 이벤트 | 위 표 전체 | SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, Stop, Interrupt |
| 타임아웃 | 5초 | 5초. SessionEnd·Interrupt는 Codex 상한에 맞춰 3초 |
| 훅 명령 | `"…/hook.sh" # claude-pet` | `"…/hook.sh" --agent codex # claude-pet` |
| 설치 대상 | 항상 | `~/.codex` 디렉터리가 있을 때 |

설치기(`HooksInstaller`)는 에이전트를 인자로 받고 순수 변환은 공유한다. 재설치 때 그 에이전트의 목록에 없는 이벤트에 남은 우리 항목은 지운다(Codex 파일에 Claude 목록으로 잘못 걸린 경우 포함).

Codex는 관리되지 않는 훅을 사용자가 `/hooks`에서 신뢰하기 전까지 건너뛴다. 신뢰는 훅 해시 기준이라 명령 문자열이 바뀌면 다시 승인해야 한다. 우리가 대신 신뢰를 기록할 방법은 없으므로 CLI와 앱은 설치 직후 이 절차를 안내한다(`Agent.postInstallNote`). 검증 자동화에서만 `--dangerously-bypass-hook-trust`를 쓴다.

### 상태 합성 (`ClaudePetCore.StateAggregator`)

입력: 상태 디렉터리의 모든 JSON. 출력: 표시할 상태 하나와 그 근거 세션.

1. 파싱 실패 파일은 건너뛴다.
2. `agent_pid`로 세션 프로세스를 확인한다. 살아 있으면 아무리 조용해도 남기고, 없으면 바로 뺀다. pid는 돌려 쓰이므로 커널의 짧은 이름(`p_comm`)과 실행 파일 경로 조각으로 정말 claude/codex인지 본다. CLI로 깐 Claude Code는 실행 파일 이름이 버전 번호(`~/.local/share/claude/versions/2.1.274`)라서 마지막 조각만 보면 놓친다. pid가 없는 옛 파일은 `now - ts > 30분`이면 죽은 세션으로 본다. `> 24시간`이면 파일을 삭제한다.
3. `failed`, `review`는 `now - ts > 10분`이면 idle로 취급한다. `running`은 `now - ts > 5분`이면 idle로 취급한다.
4. 남은 것 중 우선순위 `waiting > failed > running > review > idle`로 고른다. 같은 순위면 `ts`가 큰 것.
5. 함께 반환: 선택된 세션 ID, tool, cwd, 그리고 waiting 상태인 세션 수.
6. 살아 있는 세션이 없으면 idle, 세션 없음.

### 애니메이션 상태 기계 (`ClaudePetCore.AnimationDirector`)

합성 상태를 스프라이트 행으로 바꾼다.

| 합성 상태 | 행 |
| --- | --- |
| idle | idle |
| running | running. 20초마다 30% 확률로 run-right 또는 run-left를 한 사이클 끼워 넣어 제자리 산책 |
| waiting | waiting |
| failed | failed |
| review | review |

일회성 행:

- 앱 시작, 펫 교체: waving 한 사이클 후 합성 상태로.
- waiting → running 전이: jumping 한 사이클 후 running.
- 드래그 놓음: jumping 한 사이클(착지) 후 합성 상태로.

붙잡는 행(드래그):

끌려가는 동안에는 상태 행과 일회성 연출을 모두 제치고 방향에 맞는 행을 계속 돌린다. 가로로 더 움직이면 run-right/run-left, 세로로 더 움직이면 jumping(시트에 떨어지는 행이 없어 위아래를 하나로 묶는다). 손이 멈추면(0.2초간 이벤트 없음) 놓고 평소 상태로 돌아간다. 방향은 직전 이벤트로부터의 이동량을 모아서 정한다. 되돌아올 때 펫도 따라 돌아서야 하므로 시작점부터의 거리는 쓰지 않고, 이벤트 하나가 문턱값(2pt)에 못 미쳐도 멈춘 것으로 보지 않고 넘을 때까지 모은다. 이벤트마다 판단하면 천천히 끌 때 달리기가 내려갔다 올라오기를 반복해 끊겨 보인다.

가라앉는 규칙: 지금 벌어지는 일(작업 중, 입력 대기)은 그 상태인 동안 계속 돈다. 재생 횟수로 멈추지 않는다. 펫만 보고도 돌아가는지 알 수 있어야 하기 때문이다. 조용해졌는지는 합성이 시간으로 판단한다(`runningStaleAfter` 5분이 지나면 idle). 이미 끝난 일(끝남, 실패)만 3회 알리고 느린 idle 로 가라앉는다.

프레임 속도 10fps. 행별 프레임 수는 Codex 규약(idle 6, running-right 8, running-left 8, waving 4, jumping 5, failed 8, waiting 6, running 6, review 6)을 기본으로 하되, 시트를 로드할 때 각 행에서 완전 투명한 셀은 빈 프레임으로 제외한다.

### 펫 포맷 (`ClaudePetCore.PetManifest`, `SpriteSheet`)

Codex v1 포맷 그대로.

```
<pets>/<id>/pet.json         {"id","displayName","description","spritesheetPath"}
<pets>/<id>/spritesheet.webp 1536×1872, 8열×9행, 셀 192×208, 투명 배경
```

- 로드 시 크기가 1536×1872가 아니면 거부한다.
- WebP 디코드는 ImageIO(`CGImageSource`)를 쓴다.
- 셀은 로드 시 한 번 `CGImage`로 잘라 배열에 보관한다.
- 펫 탐색 순서: `~/Library/Application Support/ClaudePet/pets/*`, 그다음 `~/.codex/pets/*`(읽기만, 복사하지 않음). 같은 id면 앞쪽이 이긴다.
- 내장 기본 펫: 저장소 `Resources/pets/default/`에 포함하는 간단한 픽셀 캐릭터. 시트는 스크립트로 생성한 PNG를 쓴다(로더는 ImageIO라 WebP와 PNG를 가리지 않는다). 설치된 펫이 없거나 로드에 실패하면 이것을 쓴다.

### 오버레이 창 (`ClaudePetApp.OverlayPanel`)

- `NSPanel`, 스타일 `[.borderless, .nonactivatingPanel]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`.
- `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.
- `Info.plist`에 `LSUIElement = YES`.
- 기본 위치: 주 화면 `visibleFrame` 우하단에서 16pt 안쪽. 드래그로 이동 가능하며 위치는 `UserDefaults`에 저장한다. 화면 구성이 바뀌어 저장 위치가 어느 화면에도 없으면 기본 위치로 되돌린다.
- 표시 배율: 0.5(기본, 96×104pt), 1.0, 0.35 중 선택.
- 시스템 "동작 줄이기"를 기본으로 존중한다. 멀미나 전정기관 문제로 켜는 설정이라 앱이 마음대로 무시하지 않는다. 다만 그 설정을 켜 둔 채로 펫만은 움직이길 바라는 사람을 위해 메뉴에 "동작 줄이기 무시하고 움직이기"를 둔다. 기본은 꺼짐이고, 시스템 설정이 켜져 있을 때만 메뉴에 나온다.
- 렌더링: `CALayer.contents`에 `CGImage` 교체. `magnificationFilter = .nearest`, `minificationFilter = .nearest`.
- 클릭 통과: 기본 `ignoresMouseEvents = true`. `NSEvent.addGlobalMonitorForEvents(.mouseMoved)`로 커서가 펫 사각형 안에 들어오면 `false`, 나가면 `true`.
- 마우스 이벤트: 좌클릭은 세션 이동, 우클릭은 메뉴, 드래그는 이동.

### 말풍선 (`ClaudePetApp.SpeechBubble`)

펫 위에 붙는 라운드 라벨. 상태별 문구:

| 상태 | 문구 |
| --- | --- |
| running | `<tool> · <cwd 마지막 디렉터리>` (tool이 없으면 `작업 중 · <dir>`) |

Codex 세션이면 위 문구 앞에 `Codex · `를 붙인다. Claude는 기본이라 표식이 없다.

| waiting | `입력 대기 · <dir>`, 대기 세션이 2개 이상이면 ` +N` |
| failed | `실패 · <tool 또는 dir>` |
| review | `끝남 · <dir>` |
| idle | 숨김 |

- 텍스트가 바뀔 때만 다시 그린다.
- running 문구는 같은 내용이 3초 이상 이어지면 불투명도를 0.5로 낮춘다. waiting과 failed는 항상 불투명도 1.

### 세션 이동

- 좌클릭 시 합성 근거 세션의 ID로 딥링크를 연다.
  - waiting: `claude://code/needs-input?session=<id>`
  - 그 외: `claude://code/continue?session=<id>`
- 딥링크를 열기 전에 `NSWorkspace`로 번들 ID `com.anthropic.claudefordesktop`을 활성화한다. Claude Desktop이 설치되어 있지 않으면 아무것도 하지 않고 메뉴바 아이콘에 잠깐 경고를 띄운다.
- 세션이 없는 idle 상태에서 클릭하면 Claude 앱만 활성화한다.
- Codex 세션은 조상 프로세스에서 찾은 호스트 앱(Codex.app, 에디터, 터미널)을 활성화한다. 단서가 없으면 Claude Desktop 폴백을 타지 않고 아무것도 하지 않는다.

### 메뉴바 (`ClaudePetApp.StatusMenu`)

항목: 펫 보이기/숨기기, 펫 선택(설치된 펫 목록, 현재 것 체크), 크기(0.35 / 0.5 / 1.0), 로그인 시 실행(체크), 에이전트별 훅 줄(`Claude Code 훅: 설치됨` / `Codex 훅 설치하기…`, Codex 줄은 `~/.codex`가 있을 때만), 상태 다시 읽기, 종료.

시트 로드 실패나 훅 미설치 같은 경고는 아이콘 옆 작은 점으로 표시하고, 메뉴 첫 줄에 이유를 적는다.

### CLI (`claude-pet`)

앱 번들 `Contents/MacOS/claude-pet`에 두고, `scripts/install.sh`가 `/usr/local/bin/claude-pet` 심볼릭 링크를 만든다. 앱과 같은 `ClaudePetCore`를 쓴다.

| 명령 | 동작 |
| --- | --- |
| `install-hooks [claude\|codex]` | 대상 에이전트의 훅 파일에 그 에이전트의 이벤트마다 항목을 추가한다. 인자가 없으면 Claude와, `~/.codex`가 있으면 Codex도. 명령 문자열은 `"<앱 경로>/Contents/Resources/hook.sh" # claude-pet` 형태이고 Codex는 `--agent codex`가 마커 앞에 붙는다. 기존 항목은 보존하고, `# claude-pet` 표식이 있는 항목이 이미 있으면 경로만 갱신한다. 쓰기 전 `<파일>.bak-YYYYMMDD-HHMMSS`를 남긴다. 파일이 없으면 만든다. JSON 파싱 실패 시 아무것도 쓰지 않고 종료 코드 1. |
| `uninstall-hooks [claude\|codex]` | `# claude-pet` 표식이 있는 항목만 제거한다. 빈 배열이 된 이벤트 키는 삭제한다. 대상 선택은 설치와 같다. |
| `add <id>` | `https://codex-pets.net/api/pets/<id>`에서 `downloadUrl`을 읽고 zip을 받아 `pets/<id>/`에 `pet.json`과 `spritesheet.webp`로 푼다. 시트 크기를 검증하고 아니면 디렉터리를 지우고 종료 코드 1. |
| `use <id>` | 기본 펫을 `UserDefaults`에 저장하고 실행 중인 앱에 알린다(`DistributedNotificationCenter`). |
| `list` | 설치된 펫과 출처를 표시한다. |
| `login-item on\|off` | `SMAppService.mainApp`로 로그인 항목 등록/해제. |
| `status` | 에이전트별 훅 설치 여부, 상태 디렉터리의 살아 있는 세션 요약(에이전트 열 포함)을 출력한다. |

### 첫 실행

앱을 처음 켤 때:

1. 설치 대상 에이전트 중 훅이 빠진 것이 있으면 알림창으로 설치 여부를 묻는다. 예를 누르면 빠진 것만 `install-hooks`와 같은 동작을 한다.
2. 설치된 펫이 없으면 내장 기본 펫으로 시작하고, 메뉴에 "펫 받기(guga)…" 항목을 보여준다.

## Windows

2026-09-23 추가. 설계 결정과 근거는 다음과 같다.

- **스택**: Swift 를 유지하고 `ClaudePetCore`·CLI·테스트를 공유한다. 앱 레이어만 `Sources/ClaudePetWin` 에 Win32(`import WinSDK`)로 새로 쓴다. 파일 단위 `#if os(macOS)` / `#if os(Windows)` 로 갈라서 어느 OS 에서든 `swift build` 가 전 타깃을 돈다.
- **훅**: `hook.sh` 는 네이티브 Windows 에서 못 쓴다(MSYS `ps` 는 MSYS 프로세스만 보여 에이전트 pid 를 못 찾고 경로도 다르다). 대신 CLI 의 `claude-pet hook [--agent x]` 서브커맨드가 같은 상태 파일을 쓴다. `HookRunner.decide` 는 순수 함수라 mac 테스트에서 픽스처로 검증한다. 조상 탐색은 `ProcessAncestry`(Windows: Toolhelp32). 에이전트를 양성 식별하지 못하면 `agent_pid` 는 0 으로 남겨 앱이 30분 규칙으로 처리하게 한다. mac 은 v1 에서 `hook.sh` 를 그대로 쓴다.
- **훅 항목**(`HookCommand`): Claude Code 는 Windows 에서 셸 형태 훅을 Git Bash `sh -c`(없으면 PowerShell)로 돌리므로 경로를 `C:/…` 로 쓰고 `shell` 키로 셸을 고정한다. Codex 는 `commandWindows` 에 PowerShell 문장을 받는다. PowerShell 형은 `[Console]::In.ReadToEnd() | & "…\claude-pet.exe" hook …` 로 stdin 을 명시적으로 넘기고 UTF-8 을 강제한다(PowerShell 5.1 이 파이프를 OEM 코드페이지로 재인코딩해 한글 cwd 가 깨진다). exec 형태(`args`)는 upstream 버그(anthropics/claude-code#90495)로 보류. `isOurs` 는 `command`·`commandWindows` 둘 다 본다.
- **경로**: `%LOCALAPPDATA%\ClaudePet\{state,pets,preferences.json}`. `.claude`·`.codex` 는 `%USERPROFILE%` 아래. 배포 레이아웃은 `<root>\ClaudePetWin.exe`, `<root>\claude-pet.exe`, `<root>\pets\default\`, 런타임 DLL.
- **설정**: `PreferencesStore` 프로토콜. mac 은 UserDefaults 그대로, Windows 는 JSON 파일. CLI → 앱 알림은 mac 은 DistributedNotificationCenter, Windows 는 `prefs-changed` 파일 mtime 을 앱이 1초 폴링.
- **스프라이트**: `SpriteFrame`(RGBA8 premultiplied 버퍼)이 Core 의 프레임 타입. 디코더는 `SpriteDecoder` 프로토콜로 플랫폼이 준다(mac ImageIO, Windows WIC). Windows 11 은 WebP WIC 코덱이 기본이고 Windows 10 은 Store 의 WebP Image Extensions 가 필요하다. 없으면 내장 기본 펫(PNG)으로 대체하고 메뉴에 이유를 적는다.
- **앱 레이어**: `WS_EX_LAYERED|TOPMOST|TOOLWINDOW|NOACTIVATE` 팝업 창에 premultiplied BGRA DIB 를 `UpdateLayeredWindow`. 알파 0 픽셀은 OS 가 클릭을 통과시킨다. 트레이는 `Shell_NotifyIconW`(TaskbarCreated 재등록), 메뉴는 `TrackPopupMenuEx`. 말풍선은 GDI+ 로 같은 DIB 에 합성. 상태 감시는 1초 폴링. 세션 이동은 `ShellExecuteW("claude://…")` 또는 `EnumWindows` → `SetForegroundWindow`(거부 시 `FlashWindowEx`). 로그인 항목은 HKCU Run 키. 동작 줄이기는 `SPI_GETCLIENTAREAANIMATION`. GUI exe 는 `/SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup` 으로 링크.
- **배포**: GitHub Actions windows 러너가 `scripts/bundle-windows.ps1` 로 zip 을 만들어 `v*` 태그에 pre-release 로 붙인다. Swift 런타임 DLL 을 동봉한다. 설치는 `install-windows.ps1`(복사, Mark-of-the-Web 제거, PATH, 훅 설치).
- **검증**: 실기기가 없다. CI 가 빌드·단위 테스트·훅 통합(`Tests/hook/run.ps1`: 픽스처 직접 입력, 설치기가 만든 명령을 bash·powershell.exe·pwsh 로 실행, 콜드 스타트)을 돌린다. 창·트레이·클릭 이동은 실기기 미검증으로 README 에 명시한다.
- **알려진 제한**: WSL 미지원, npm 설치 Claude(node.exe)의 생사 판정 불가, GUI 호스트 세션에서 `bash.exe` 콘솔 깜빡임 가능(Claude Code 가 스폰하는 쪽의 문제), 코드 서명 없음.

## 에러 처리

- 훅: 어떤 실패에도 exit 0. 상태 디렉터리가 없으면 만든다. 쓰기 실패는 무시한다.
- 앱: 깨진 상태 파일은 건너뛴다. 시트 로드 실패는 내장 기본 펫으로 대체하고 경고 표시. 상태 디렉터리 감시 실패 시 1초 폴링만으로 동작한다.
- CLI: 네트워크와 파일 오류는 한 줄 메시지와 종료 코드 1. `settings.json`은 백업 없이 절대 쓰지 않는다.

## 저장소 구조

```
claude-pet/
├── Package.swift
├── Sources/
│   ├── ClaudePetCore/      순수 로직: StateAggregator, AnimationDirector,
│   │                        PetManifest, SpriteSheet, HooksInstaller, PetInstaller
│   ├── ClaudePetApp/       AppKit: OverlayPanel, PetLayerView, SpeechBubble,
│   │                        StatusMenu, StateWatcher, AppDelegate (#if os(macOS))
│   ├── ClaudePetWin/       Win32: OverlayWindow, TrayIcon, BubbleRenderer, WICDecoder (#if os(Windows))
│   └── claude-pet/         CLI 진입점 (hook 서브커맨드 포함)
├── Tests/
│   ├── ClaudePetCoreTests/
│   └── hook/               hook.sh 셸 테스트(run.sh), Windows 네이티브 훅 통합 테스트(run.ps1)
├── hooks/hook.sh
├── Resources/
│   ├── Info.plist
│   ├── AppIcon.icns
│   └── pets/default/       내장 기본 펫
├── scripts/
│   ├── bundle.sh           swift build 결과를 ClaudePet.app으로 감싼다
│   ├── install.sh          /Applications 복사, CLI 링크, 훅 설치 안내
│   ├── bundle-windows.ps1  Windows zip (exe, 런타임 DLL, 기본 펫)
│   └── install-windows.ps1 zip 을 %LOCALAPPDATA%\Programs\ClaudePet 에 설치
├── .github/workflows/      ci.yml (macOS+Windows), release.yml (Windows zip)
└── docs/superpowers/specs/
```

- Xcode 프로젝트 없이 `swift build -c release`와 `scripts/bundle.sh`만으로 앱을 만든다.
- 최소 배포 대상 macOS 14.
- 저장소 위치: `~/Documents/workspace/claude-pet`.

## 테스트

`ClaudePetCoreTests` (XCTest):

- 이벤트 → 상태 매핑 전체 표.
- 합성: 우선순위, 동순위 시 최신 우선, 30분 시효, failed/review 10분 가라앉힘, 24시간 삭제 대상 판정, waiting 세션 수.
- 애니메이션: 상태 전이별 행 선택, waving과 jumping 일회성 삽입, 빈 셀 제외 후 프레임 수.
- 시트: 1536×1872 검증, 셀 자르기 좌표, 완전 투명 셀 감지(테스트용 합성 이미지 사용).
- 훅 설치: 기존 훅 보존, 표식 항목 갱신, 제거 후 빈 키 삭제, 백업 파일 생성, 잘못된 JSON에서 미변경. Codex 변형: 명령의 `--agent codex`, Codex 이벤트 목록만, SessionEnd·Interrupt 타임아웃 3초, `~/.codex/hooks.json` 경로, Claude 목록으로 잘못 걸린 항목 정리.
- 에이전트: 이벤트 목록, 타임아웃, 설정 파일 경로, `~/.codex` 유무에 따른 설치 대상.
- 상태 파일: `agent` 없는 옛 파일과 모르는 값은 Claude로 읽는다. 말풍선: Codex 세션만 접두. 세션 이동: Codex 세션은 단서가 없으면 아무것도 하지 않는다.

`Tests/hook/` (셸):

- 각 이벤트 샘플 JSON을 stdin으로 넣고 결과 파일 내용 비교.
- session_id 없는 입력, 빈 입력, 깨진 JSON에서 파일이 생기지 않고 exit 0.
- SessionEnd가 파일을 지우는지.
- `--agent codex`가 `agent` 필드로 남는지, 인자가 없거나 모르는 값이면 `claude`인지, Interrupt가 idle이 되는지.

수동 체크리스트 (빌드 후 직접 실행해 확인):

- 전체화면 앱 위와 다른 Space에서 펫이 보인다.
- 펫 바깥 클릭이 아래 창으로 통과하고, 펫 클릭은 Claude 세션을 연다.
- 세션 두 개에서 하나가 PermissionRequest 상태가 되면 waiting으로 바뀌고 "+N"이 맞다.
- 펫 교체 시 waving이 한 번 나온다.
- 메뉴바 항목이 모두 동작한다.
