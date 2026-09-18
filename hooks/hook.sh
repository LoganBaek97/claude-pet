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

# 조상 프로세스를 한 번 훑어 두 가지를 집는다.
#
#  agent_pid — 이 세션을 돌리는 claude/codex 프로세스. 가장 가까운 쪽을 잡는다.
#              앱이 이 pid 로 생사를 확인해서, 오래 조용한 세션도 살아 있으면 계속 보여 준다.
#              이게 없으면 30분간 이벤트가 없는 세션은 죽은 것으로 취급되어 사라진다.
#  host_app  — 클릭했을 때 데려갈 앱. 가장 바깥쪽 .app 을 잡는다. 터미널에서 띄운 CLI 면
#              Terminal/iTerm/Ghostty, 에디터 안이면 그 에디터다.
#              Claude Desktop 세션은 위에서 이미 확정했으니 찾지 않는다.
#
# 대개 훅의 부모가 곧 에이전트다. 그 한 프로세스만 물어보는 것이 전체 목록을 훑는 것보다 훨씬 싸다
# (이 기계에서 70ms 대 38ms). 데스크톱 세션은 host_app 을 찾을 일이 없어서 여기서 끝난다.
agent_pid=""
host_pid=""
host_app=""
ppid_comm=$(ps -p "$PPID" -o comm= 2>/dev/null)
case "${ppid_comm##*/}" in claude|codex) agent_pid=$PPID;; esac

# 부모가 에이전트가 아니거나(중간에 셸이 끼는 경우) 호스트 앱을 찾아야 할 때만 조상을 훑는다.
if [ -z "$agent_pid" ] || [ -z "$host" ]; then
scan=$(ps -Ao pid=,ppid=,comm= 2>/dev/null | awk -v start="$PPID" -v want_host="$([ -z "$host" ] && echo 1 || echo 0)" '
  { c=$0; sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+/, "", c); parent[$1]=$2; cmd[$1]=c }
  END {
    p = start
    for (i = 0; i < 20 && p != "" && p > 1; i++) {
      if (agent == "") {
        base = cmd[p]; sub(/^.*\//, "", base)
        if (base == "claude" || base == "codex") agent = p
      }
      if (want_host == 1 && index(cmd[p], ".app/Contents/MacOS/") > 0) { outer = cmd[p]; outerpid = p }
      p = parent[p]
    }
    if (outer != "") { sub(/\/Contents\/MacOS\/.*$/, "", outer) } else { outerpid = "" }
    print (agent == "" ? "-" : agent) " " (outerpid == "" ? "-" : outerpid) " " outer
  }')
if [ -n "$scan" ]; then
  scanned_agent=${scan%% *}
  rest=${scan#* }
  host_pid=${rest%% *}
  host_app=${rest#* }
  [ "$host_pid" = "-" ] && host_pid=""
  case "$host_pid" in *[!0-9]*) host_pid=""; host_app="";; esac
  # 위에서 부모로 이미 찾았으면 그대로 둔다.
  if [ -z "$agent_pid" ] && [ "$scanned_agent" != "-" ]; then
    case "$scanned_agent" in *[!0-9]*) ;; *) agent_pid=$scanned_agent;; esac
  fi
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
printf '{"session_id":"%s","state":"%s","event":"%s","tool":"%s","cwd":"%s","transcript":"%s","host_session":"%s","host_pid":%s,"host_app":"%s","agent_pid":%s,"agent":"%s","ts":%s}\n' \
  "$session" "$state" "$(esc "$event")" "$(esc "$tool")" "$(esc "$cwd")" "$(esc "$transcript")" "$host" "${host_pid:-0}" "$(esc "$host_app")" "${agent_pid:-0}" "$agent" "$ts" > "$tmp" 2>/dev/null \
  && mv -f "$tmp" "$file" 2>/dev/null
rm -f "$tmp" 2>/dev/null
exit 0
