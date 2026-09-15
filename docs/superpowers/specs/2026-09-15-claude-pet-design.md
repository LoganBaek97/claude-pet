# claude-pet 설계

작성일: 2026-09-15
대상: macOS 26, Claude Desktop(Code 탭)과 Claude Code CLI

## 목적

Codex 앱의 pet과 같은 경험을 Claude Code 사용자에게 준다. 화면 구석에 항상 떠 있는 작은 픽셀 펫이 Claude 세션들의 상태(작업 중, 입력 대기, 실패, 리뷰 대기, 유휴)에 맞춰 애니메이션을 바꾸고, 클릭하면 해당 세션으로 이동한다.

Claude Code와 Desktop 앱에는 UI 확장 지점이 없으므로 별도 오버레이 앱으로 만들고, 훅으로 상태를 받는다. 펫 자산은 Codex v1 펫 포맷을 그대로 채택해 codex-pets.net의 펫을 재사용한다.

## 범위

v1에 포함:

- 훅 스크립트와 세션별 상태 파일
- Swift/AppKit 오버레이 앱: 스프라이트 재생, 말풍선, 클릭 이동, 메뉴바 메뉴
- 다중 세션 우선순위 합성
- CLI: 훅 설치/제거, 펫 설치(codex-pets.net), 기본 펫 지정, 로그인 항목
- 내장 기본 펫 하나

v1에서 제외:

- 펫 생성(hatch, 이미지 생성)
- Windows, Linux
- 세션마다 펫 여러 마리
- 코드 서명, 공증, 배포 패키징

## 구성 요소

```
Claude Code ──(hook stdin JSON)──▶ hooks/hook.sh
                                      │ 원자적 쓰기
                                      ▼
                  ~/Library/Application Support/ClaudePet/state/<session_id>.json
                                      │ FSEvents 감시 + 1초 폴링
                                      ▼
                                ClaudePet.app ──▶ 오버레이 창(스프라이트, 말풍선)
                                      │            메뉴바 메뉴
                                      └─ 클릭 ──▶ open claude://code/continue?session=<id>

claude-pet CLI ──▶ ~/.claude/settings.json (훅 등록)
               ──▶ ~/Library/Application Support/ClaudePet/pets/<id>/ (펫 설치)
```

### 훅 스크립트 `hooks/hook.sh`

- POSIX sh, 외부 의존성 없음(`cat`, `sed`, `mkdir`, `mv`만 사용). 목표 실행 시간 50ms 이내.
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
| 그 외(SubagentStart, SubagentStop 포함) | 무시 |

상태 파일:

```json
{"session_id":"…","state":"waiting","event":"PermissionRequest","tool":"Bash","cwd":"/path/to/project","ts":1789000000}
```

`ts`는 Unix 초. `tool`과 `cwd`는 없으면 빈 문자열.

### 상태 합성 (`ClaudePetCore.StateAggregator`)

입력: 상태 디렉터리의 모든 JSON. 출력: 표시할 상태 하나와 그 근거 세션.

1. 파싱 실패 파일은 건너뛴다.
2. `now - ts > 30분`인 파일은 죽은 세션으로 보고 무시한다. `> 24시간`이면 삭제한다.
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
- 렌더링: `CALayer.contents`에 `CGImage` 교체. `magnificationFilter = .nearest`, `minificationFilter = .nearest`.
- 클릭 통과: 기본 `ignoresMouseEvents = true`. `NSEvent.addGlobalMonitorForEvents(.mouseMoved)`로 커서가 펫 사각형 안에 들어오면 `false`, 나가면 `true`.
- 마우스 이벤트: 좌클릭은 세션 이동, 우클릭은 메뉴, 드래그는 이동.

### 말풍선 (`ClaudePetApp.SpeechBubble`)

펫 위에 붙는 라운드 라벨. 상태별 문구:

| 상태 | 문구 |
| --- | --- |
| running | `<tool> · <cwd 마지막 디렉터리>` (tool이 없으면 `작업 중 · <dir>`) |
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

### 메뉴바 (`ClaudePetApp.StatusMenu`)

항목: 펫 보이기/숨기기, 펫 선택(설치된 펫 목록, 현재 것 체크), 크기(0.35 / 0.5 / 1.0), 로그인 시 실행(체크), 훅: 설치됨 / 설치하기, 상태 다시 읽기, 종료.

시트 로드 실패나 훅 미설치 같은 경고는 아이콘 옆 작은 점으로 표시하고, 메뉴 첫 줄에 이유를 적는다.

### CLI (`claude-pet`)

앱 번들 `Contents/MacOS/claude-pet`에 두고, `scripts/install.sh`가 `/usr/local/bin/claude-pet` 심볼릭 링크를 만든다. 앱과 같은 `ClaudePetCore`를 쓴다.

| 명령 | 동작 |
| --- | --- |
| `install-hooks` | `~/.claude/settings.json`의 `hooks`에 위 표의 이벤트마다 항목을 추가한다. 명령 문자열은 `"<앱 경로>/Contents/Resources/hook.sh" # claude-pet` 형태. 기존 항목은 보존하고, `# claude-pet` 표식이 있는 항목이 이미 있으면 경로만 갱신한다. 쓰기 전 `settings.json.bak-YYYYMMDD-HHMMSS`를 남긴다. 파일이 없으면 만든다. JSON 파싱 실패 시 아무것도 쓰지 않고 종료 코드 1. |
| `uninstall-hooks` | `# claude-pet` 표식이 있는 항목만 제거한다. 빈 배열이 된 이벤트 키는 삭제한다. |
| `add <id>` | `https://codex-pets.net/api/pets/<id>`에서 `downloadUrl`을 읽고 zip을 받아 `pets/<id>/`에 `pet.json`과 `spritesheet.webp`로 푼다. 시트 크기를 검증하고 아니면 디렉터리를 지우고 종료 코드 1. |
| `use <id>` | 기본 펫을 `UserDefaults`에 저장하고 실행 중인 앱에 알린다(`DistributedNotificationCenter`). |
| `list` | 설치된 펫과 출처를 표시한다. |
| `login-item on\|off` | `SMAppService.mainApp`로 로그인 항목 등록/해제. |
| `status` | 훅 설치 여부, 상태 디렉터리의 살아 있는 세션 요약을 출력한다. |

### 첫 실행

앱을 처음 켤 때:

1. 훅이 설치되어 있지 않으면 알림창으로 설치 여부를 묻는다. 예를 누르면 `install-hooks`와 같은 동작을 한다.
2. 설치된 펫이 없으면 내장 기본 펫으로 시작하고, 메뉴에 "펫 받기(guga)…" 항목을 보여준다.

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
│   │                        StatusMenu, StateWatcher, AppDelegate
│   └── claude-pet/         CLI 진입점
├── Tests/
│   ├── ClaudePetCoreTests/
│   └── hook/               hook.sh 셸 테스트
├── hooks/hook.sh
├── Resources/
│   ├── Info.plist
│   ├── AppIcon.icns
│   └── pets/default/       내장 기본 펫
├── scripts/
│   ├── bundle.sh           swift build 결과를 ClaudePet.app으로 감싼다
│   └── install.sh          /Applications 복사, CLI 링크, 훅 설치 안내
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
- 훅 설치: 기존 훅 보존, 표식 항목 갱신, 제거 후 빈 키 삭제, 백업 파일 생성, 잘못된 JSON에서 미변경.

`Tests/hook/` (셸):

- 각 이벤트 샘플 JSON을 stdin으로 넣고 결과 파일 내용 비교.
- session_id 없는 입력, 빈 입력, 깨진 JSON에서 파일이 생기지 않고 exit 0.
- SessionEnd가 파일을 지우는지.

수동 체크리스트 (빌드 후 직접 실행해 확인):

- 전체화면 앱 위와 다른 Space에서 펫이 보인다.
- 펫 바깥 클릭이 아래 창으로 통과하고, 펫 클릭은 Claude 세션을 연다.
- 세션 두 개에서 하나가 PermissionRequest 상태가 되면 waiting으로 바뀌고 "+N"이 맞다.
- 펫 교체 시 waving이 한 번 나온다.
- 메뉴바 항목이 모두 동작한다.
