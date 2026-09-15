#!/bin/sh
# 사용법: sh Tests/hook/run.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/../../hooks/hook.sh"
FIX="$HERE/fixtures"
export CLAUDE_PET_STATE_DIR=$(mktemp -d)
fail=0

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fail=1; fi
}
field() { # file key -> value
  sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p" "$1"
}
run() { sh "$HOOK" < "$FIX/$1"; assert_eq "exit0 $1" 0 $?; }

run pre-tool-use.json
f="$CLAUDE_PET_STATE_DIR/sess-1.json"
assert_eq "file created" yes "$([ -f "$f" ] && echo yes || echo no)"
assert_eq "state running" running "$(field "$f" state)"
assert_eq "event" PreToolUse "$(field "$f" event)"
assert_eq "tool" Bash "$(field "$f" tool)"
assert_eq "cwd first match" /Users/x/proj "$(field "$f" cwd)"
assert_eq "ts numeric" yes "$(grep -q '"ts":[0-9][0-9]*}' "$f" && echo yes || echo no)"
assert_eq "single line" 1 "$(wc -l < "$f" | tr -d ' ')"

run permission-request.json
assert_eq "waiting" waiting "$(field "$CLAUDE_PET_STATE_DIR/sess-2.json" state)"

run stop.json
assert_eq "review" review "$(field "$f" state)"

run post-tool-use-failure.json
f3="$CLAUDE_PET_STATE_DIR/sess-3.json"
assert_eq "failed" failed "$(field "$f3" state)"
assert_eq "backslash escaped, json stays valid" yes "$(grep -q '"cwd":"/Users/x/q \\\\","ts"' "$f3" && echo yes || echo no)"

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

printf '' | sh "$HOOK"; assert_eq "empty stdin exit0" 0 $?
printf '{not json' | sh "$HOOK"; assert_eq "broken json exit0" 0 $?
out=$(sh "$HOOK" < "$FIX/stop.json"); assert_eq "no stdout" "" "$out"

rm -rf "$CLAUDE_PET_STATE_DIR"
[ $fail -eq 0 ] && echo "ALL OK" || { echo "SOME FAILED"; exit 1; }
