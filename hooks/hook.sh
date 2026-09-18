#!/bin/sh
# claude-pet hook: Claude Code / Codex 이벤트를 세션별 상태 파일로 기록한다.
# 사용법: hook.sh [--agent claude|codex]   (기본 claude)
# 어떤 경우에도 exit 0, stdout 출력 없음.

# 에이전트: 설치기가 `--agent codex` 를 붙인다. 모르는 값은 claude 로 본다.
agent=claude
if [ "${1:-}" = "--agent" ]; then
  case "${2:-}" in claude|codex) agent=$2;; esac
fi

payload=$(cat 2>/dev/null | tr -d '\n\r')
[ -z "$payload" ] && exit 0

# key -> 페이로드에서 "key" 가 처음 나온 뒤의 첫 따옴표 문자열.
# 셸 파라미터 확장만 쓴다. 값 안의 이스케이프된 따옴표(\") 앞까지만 잡히지만
# session_id, hook_event_name, tool_name 에는 따옴표가 없고 cwd 손실은 감수한다.
first_value() {
  rest=${payload#*\"$1\"}
  [ "$rest" = "$payload" ] && { printf ''; return; }
  rest=${rest#*\"}
  printf '%s' "${rest%%\"*}"
}

session=$(first_value session_id)
[ -z "$session" ] && exit 0
case "$session" in *[!A-Za-z0-9._-]*) exit 0;; esac

event=$(first_value hook_event_name)
tool=$(first_value tool_name)
cwd=$(first_value cwd)
# 트랜스크립트 경로. 앱이 이걸 읽어 마지막 답변을 말풍선 미리보기로 쓴다.
# 글자 자체를 여기서 넣지 않는 이유: 모델 출력에는 따옴표·줄바꿈·제어문자가 섞여 있어
# printf 로 짜는 이 JSON 을 깨뜨린다. 경로는 cwd 와 같은 수준으로 안전하다.
transcript=$(first_value transcript_path)

# Claude Desktop 이 호스팅하는 세션이면 앱의 세션 ID 가 환경에 있다. 딥링크는
# 이 값만 받는다(`^local_[A-Za-z0-9-]{1,64}$`). 형식이 어긋나면 비워서 링크에서 뺀다.
# Claude Desktop 터미널에서 띄운 Codex 도 이 변수를 물려받지만 그 세션은 Claude 것이
# 아니므로 Claude 일 때만 본다.
host=""
[ "$agent" = claude ] && host=${CLAUDE_CODE_HOST_SESSION_ID:-}
hrest=${host#local_}
if [ "$hrest" = "$host" ] || [ -z "$hrest" ] || [ ${#hrest} -gt 64 ]; then
  host=""
else
  case "$hrest" in *[!A-Za-z0-9-]*) host="";; esac
fi

# 호스트 앱: 조상 프로세스를 거슬러 올라가 가장 바깥쪽 .app 을 찾는다. 터미널에서
# 띄운 CLI 면 Terminal/iTerm/Ghostty, 에디터 안이면 그 에디터가 잡힌다.
# Claude Desktop 은 위에서 이미 확정했으니 ps 를 부르지 않는다.
host_pid=""
host_app=""
if [ -z "$host" ]; then
  host_line=$(ps -Ao pid=,ppid=,comm= 2>/dev/null | awk -v start="$PPID" '
    { c=$0; sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+/, "", c); parent[$1]=$2; cmd[$1]=c }
    END {
      p = start
      for (i = 0; i < 20 && p != "" && p > 1; i++) {
        if (index(cmd[p], ".app/Contents/MacOS/") > 0) { outer = cmd[p]; outerpid = p }
        p = parent[p]
      }
      if (outer != "") { sub(/\/Contents\/MacOS\/.*$/, "", outer); print outerpid " " outer }
    }')
  if [ -n "$host_line" ]; then
    host_pid=${host_line%% *}
    host_app=${host_line#* }
    case "$host_pid" in *[!0-9]*) host_pid=""; host_app="";; esac
  fi
fi

dir=${CLAUDE_PET_STATE_DIR:-"$HOME/Library/Application Support/ClaudePet/state"}
file="$dir/$session.json"

case "$event" in
  SessionEnd) rm -f "$file" 2>/dev/null; exit 0;;
  SessionStart) state=idle;;
  UserPromptSubmit|PreToolUse|PostToolUse) state=running;;
  PermissionRequest|Notification) state=waiting;;
  PostToolUseFailure|StopFailure) state=failed;;
  Stop) state=review;;
  Interrupt) state=idle;;
  *) exit 0;;
esac

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
mkdir -p "$dir" 2>/dev/null || exit 0
ts=$(date +%s)
tmp="$file.tmp.$$"
printf '{"session_id":"%s","state":"%s","event":"%s","tool":"%s","cwd":"%s","transcript":"%s","host_session":"%s","host_pid":%s,"host_app":"%s","agent":"%s","ts":%s}\n' \
  "$session" "$state" "$(esc "$event")" "$(esc "$tool")" "$(esc "$cwd")" "$(esc "$transcript")" "$host" "${host_pid:-0}" "$(esc "$host_app")" "$agent" "$ts" > "$tmp" 2>/dev/null \
  && mv -f "$tmp" "$file" 2>/dev/null
rm -f "$tmp" 2>/dev/null
exit 0
