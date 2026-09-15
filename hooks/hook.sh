#!/bin/sh
# claude-pet hook: Claude Code 이벤트를 세션별 상태 파일로 기록한다.
# 어떤 경우에도 exit 0, stdout 출력 없음.
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

dir=${CLAUDE_PET_STATE_DIR:-"$HOME/Library/Application Support/ClaudePet/state"}
file="$dir/$session.json"

case "$event" in
  SessionEnd) rm -f "$file" 2>/dev/null; exit 0;;
  SessionStart) state=idle;;
  UserPromptSubmit|PreToolUse|PostToolUse) state=running;;
  PermissionRequest|Notification) state=waiting;;
  PostToolUseFailure|StopFailure) state=failed;;
  Stop) state=review;;
  *) exit 0;;
esac

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
mkdir -p "$dir" 2>/dev/null || exit 0
ts=$(date +%s)
tmp="$file.tmp.$$"
printf '{"session_id":"%s","state":"%s","event":"%s","tool":"%s","cwd":"%s","ts":%s}\n' \
  "$session" "$state" "$(esc "$event")" "$(esc "$tool")" "$(esc "$cwd")" "$ts" > "$tmp" 2>/dev/null \
  && mv -f "$tmp" "$file" 2>/dev/null
rm -f "$tmp" 2>/dev/null
exit 0
