#!/bin/sh
# 사용법: sh Tests/hook/run.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/../../hooks/hook.sh"
FIX="$HERE/fixtures"
export CLAUDE_PET_STATE_DIR=$(mktemp -d)
# 이 테스트를 Claude Desktop 안에서 돌리면 진짜 호스트 세션 ID 가 상속된다. 기준선은 없는 상태.
unset CLAUDE_CODE_HOST_SESSION_ID
fail=0

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fail=1; fi
}
field() { # file key -> value
  sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p" "$1"
}
number() { # file key -> 따옴표 없는 수 값
  sed -n "s/.*\"$2\":\([0-9][0-9]*\).*/\1/p" "$1"
}
# case 를 $( ) 안에 두면 bash 3.2 가 패턴의 ) 를 치환 끝으로 읽는다. 함수로 뺀다.
is_number() { case "$1" in ''|*[!0-9]*) echo no;; *) echo yes;; esac; }
run() { sh "$HOOK" < "$FIX/$1"; assert_eq "exit0 $1" 0 $?; }

run pre-tool-use.json
f="$CLAUDE_PET_STATE_DIR/sess-1.json"
assert_eq "file created" yes "$([ -f "$f" ] && echo yes || echo no)"
assert_eq "state running" running "$(field "$f" state)"
assert_eq "event" PreToolUse "$(field "$f" event)"
assert_eq "tool" Bash "$(field "$f" tool)"
assert_eq "cwd first match" /Users/x/proj "$(field "$f" cwd)"
assert_eq "transcript path" /Users/x/.claude/projects/p/sess-1.jsonl "$(field "$f" transcript)"
# agent_pid: 앱이 이걸로 세션 프로세스의 생사를 본다. 테스트를 어디서 돌리냐에 따라 값이
# 달라지므로 숫자인지만 본다. 부모가 claude/codex 가 아니면 조상에서 찾고, 없으면 0 이다.
assert_eq "agent_pid is a number" yes "$(is_number "$(number "$f" agent_pid)")"
assert_eq "ts numeric" yes "$(grep -q '"ts":[0-9][0-9]*}' "$f" && echo yes || echo no)"
assert_eq "host_session empty without env" "" "$(field "$f" host_session)"
assert_eq "single line" 1 "$(wc -l < "$f" | tr -d ' ')"

run permission-request.json
assert_eq "waiting" waiting "$(field "$CLAUDE_PET_STATE_DIR/sess-2.json" state)"
# 훅 입력에 transcript_path 가 없으면 빈 값으로 남는다. 앱은 그걸 미리보기 없음으로 읽는다.
assert_eq "transcript empty when absent" "" "$(field "$CLAUDE_PET_STATE_DIR/sess-2.json" transcript)"

run stop.json
assert_eq "review" review "$(field "$f" state)"

run post-tool-use-failure.json
f3="$CLAUDE_PET_STATE_DIR/sess-3.json"
assert_eq "failed" failed "$(field "$f3" state)"
assert_eq "backslash escaped, json stays valid" yes "$(grep -q '"cwd":"/Users/x/q \\\\","transcript"' "$f3" && echo yes || echo no)"

run session-end.json
assert_eq "file removed" no "$([ -f "$f" ] && echo yes || echo no)"

run no-session.json
assert_eq "no file without session" 0 "$(ls "$CLAUDE_PET_STATE_DIR" | grep -c '^\.json$')"

before=$(ls "$CLAUDE_PET_STATE_DIR" | wc -l | tr -d ' ')
run unknown-event.json
after=$(ls "$CLAUDE_PET_STATE_DIR" | wc -l | tr -d ' ')
assert_eq "unknown event ignored" "$before" "$after"

run subagent-stop.json
assert_eq "subagent stop creates no file" no "$([ -f "$CLAUDE_PET_STATE_DIR/sess-4.json" ] && echo yes || echo no)"

# 호스트 세션 ID: Claude Desktop 이 호스팅할 때만 환경에 있고, 앱 딥링크가 받는
# 형식(`local_` + 영숫자/하이픈 1~64자)이 아니면 기록하지 않는다.
export CLAUDE_CODE_HOST_SESSION_ID=local_f1d6cbbb-68f8-4543-ae2f-d99f0f2c198e
run pre-tool-use.json
assert_eq "host_session from env" local_f1d6cbbb-68f8-4543-ae2f-d99f0f2c198e "$(field "$f" host_session)"

# 호스트 세션 ID 가 있으면 Claude Desktop 이 확정이라 조상 탐색을 건너뛴다.
assert_eq "desktop session skips host app lookup" "0 " "$(number "$f" host_pid) $(field "$f" host_app)"

for bad in "" local_ session_abc local_has_underscore "local_$(printf 'a%.0s' $(seq 65))"; do
  export CLAUDE_CODE_HOST_SESSION_ID="$bad"
  run pre-tool-use.json
  assert_eq "host_session rejected [$bad]" "" "$(field "$f" host_session)"
done
unset CLAUDE_CODE_HOST_SESSION_ID

# 데스크톱 세션이 아니면 조상 프로세스에서 GUI 앱을 찾는다. 테스트를 어디서 돌리느냐에
# 따라 터미널이 잡히기도, 아무것도 없기도 해서 모양만 본다.
run pre-tool-use.json
app=$(field "$f" host_app)
pid=$(number "$f" host_pid)
assert_eq "host_pid is a number" yes "$(is_number "$pid")"
case "$app" in
  "") assert_eq "no host app found, pid stays 0" 0 "$pid";;
  *.app) assert_eq "host app is a bundle with a live pid" yes "$([ "$pid" -gt 0 ] && echo yes || echo no)";;
  *) assert_eq "host app is a bundle path [$app]" yes no;;
esac

# 에이전트: 인자가 없으면 claude, --agent codex 면 codex 로 기록한다.
run pre-tool-use.json
assert_eq "agent defaults to claude" claude "$(field "$f" agent)"
sh "$HOOK" --agent codex < "$FIX/pre-tool-use.json"; assert_eq "exit0 --agent codex" 0 $?
assert_eq "agent codex recorded" codex "$(field "$f" agent)"
assert_eq "state still running under codex" running "$(field "$f" state)"
sh "$HOOK" --agent gemini < "$FIX/pre-tool-use.json"; assert_eq "exit0 unknown agent" 0 $?
assert_eq "unknown agent falls back to claude" claude "$(field "$f" agent)"

# Claude Desktop 터미널에서 codex 를 띄우면 CLAUDE_CODE_HOST_SESSION_ID 가 상속된다.
# Codex 세션에 Claude 딥링크를 달면 클릭이 엉뚱한 앱으로 가므로, Claude 가 아니면 무시한다.
export CLAUDE_CODE_HOST_SESSION_ID=local_f1d6cbbb-68f8-4543-ae2f-d99f0f2c198e
sh "$HOOK" --agent codex < "$FIX/pre-tool-use.json"
assert_eq "codex ignores inherited claude host session" "" "$(field "$f" host_session)"
unset CLAUDE_CODE_HOST_SESSION_ID

# Codex 전용 Interrupt: 사용자가 끊은 것이라 idle 로 가라앉힌다.
sh "$HOOK" --agent codex < "$FIX/codex-interrupt.json"; assert_eq "exit0 interrupt" 0 $?
fc="$CLAUDE_PET_STATE_DIR/codex-1.json"
assert_eq "interrupt -> idle" idle "$(field "$fc" state)"
assert_eq "interrupt event kept" Interrupt "$(field "$fc" event)"
assert_eq "interrupt agent codex" codex "$(field "$fc" agent)"

printf '' | sh "$HOOK"; assert_eq "empty stdin exit0" 0 $?
printf '{not json' | sh "$HOOK"; assert_eq "broken json exit0" 0 $?
out=$(sh "$HOOK" < "$FIX/stop.json"); assert_eq "no stdout" "" "$out"

rm -rf "$CLAUDE_PET_STATE_DIR"
[ $fail -eq 0 ] && echo "ALL OK" || { echo "SOME FAILED"; exit 1; }
