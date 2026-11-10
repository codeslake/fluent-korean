#!/bin/sh
# Self-check for plugins/fluent-korean/hooks/concise-reminder.sh. Run: sh tests/hook_test.sh  (exit 0 = all pass)
H=$(cd "$(dirname "$0")/.." && pwd)/plugins/fluent-korean/hooks/concise-reminder.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.claude" "$T/proj"
python3 - "$T" "$H" <<'PY'
import json, re, sys
d, h = sys.argv[1], open(sys.argv[2]).read()
def w(name, recs): open(f'{d}/{name}.jsonl', 'w').write('\n'.join(json.dumps(r, ensure_ascii=False, separators=(',', ':')) for r in recs) + '\n')
S = {"type": "attachment", "attachment": {"type": "output_style", "style": "fluent-korean:fluent-korean-concise"}}
U = {"type": "user", "origin": {"kind": "human"}, "message": {"content": "이거 왜 영어로 쓰지?"}}
EN = {"type": "assistant", "message": {"content": [{"type": "text", "text": "I fixed the black-text problem in the board's method figure and redeployed it."}]}}
KO = {"type": "assistant", "message": {"content": [{"type": "text", "text": "보드 그림의 검은 글자 문제를 고쳤습니다."}]}}
# the texts the hook already sent on an earlier prompt: the concise reminder plus the line, or the line alone
KOLINE = re.search(r'ko\) lang_line="([^"]*)"', h).group(1)
BOTH = re.search(r'concise="([^"]*)"', h).group(1) + ' ' + KOLINE
L = lambda t: {"type": "attachment", "isSidechain": False, "attachment": {"type": "hook_additional_context", "content": [t], "hookName": "UserPromptSubmit", "hookEvent": "UserPromptSubmit"}}
CRON = {"type": "session_cron_carry", "tasks": [], "otherArmed": [{"id": "c1", "cron": "34 * * * *", "prompt": "매시 상태 보고"}]}
w('seen', [S, CRON, U, KO, L(BOTH)])
w('seen_line', [S, U, KO, L(KOLINE)])
w('seen_en', [S, U, EN, L(BOTH)])
w('compacted', [S, U, KO, L(BOTH), {"type": "system", "subtype": "compact_boundary", "content": "Conversation compacted"}])
PY
EN="I fixed the black-text problem in the board's method figure and redeployed it to all hosts."
TN='<task-notification>
<summary>Background command "x" completed</summary>
</task-notification>'
fail=0
check() { # label transcript event reply-lang prompt last-message expected-substring|-
  P=$(python3 -c 'import json,sys;print(json.dumps({"session_id":"s1","prompt_id":"q1","transcript_path":sys.argv[1],"hook_event_name":sys.argv[2],"prompt":sys.argv[3],"last_assistant_message":sys.argv[4]},ensure_ascii=False))' "$2" "$3" "$5" "$6")
  out=$(HOME="$T/home" CLAUDE_PROJECT_DIR="$T/proj" TMPDIR="$T" CLAUDE_CODE_ENTRYPOINT=cli CLAUDE_PLUGIN_OPTION_REPLY_LANG="$4" FLUENT_KOREAN_REPLY_LANG= sh "$H" "$3" <<EOT
$P
EOT
)
  if [ "$7" = - ]; then [ -z "$out" ]; else printf '%s' "$out" | python3 -c 'import json,sys;json.load(sys.stdin)' 2>/dev/null && case $out in *"$7"*) true ;; *) false ;; esac; fi
  if [ $? -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1: ${out:-<none>}"; fail=1; fi
}
check "owner-typed prompt: reminder and line" "$T/seen.jsonl" UserPromptSubmit 한국어 "그림 다시 봐줘" "" "필요한 내용만 전달합니다. 사용자에게 쓰는 글(CLI 답변)의 언어: 한국어. 사용자가"
check "peer message, same text already given: silent" "$T/seen.jsonl" UserPromptSubmit 한국어 "Another Claude session sent a message: status?" "" -
check "scheduled prompt, same text already given: silent" "$T/seen.jsonl" UserPromptSubmit 한국어 "매시 상태 보고" "" -
check "task notification, same line already given: silent" "$T/seen_line.jsonl" UserPromptSubmit 한국어 "$TN" "" -
check "task notification after reminder and line: line" "$T/seen.jsonl" UserPromptSubmit 한국어 "$TN" "" "한국어였으므로"
check "peer message after the line alone: reminder and line" "$T/seen_line.jsonl" UserPromptSubmit 한국어 "Another Claude session sent a message: status?" "" "간결하게 답합니다."
check "peer message after a compaction: reminder and line" "$T/compacted.jsonl" UserPromptSubmit 한국어 "Another Claude session sent a message: status?" "" "한국어였으므로"
check "peer message after an English reply: drift line" "$T/seen_en.jsonl" UserPromptSubmit 한국어 "Another Claude session sent a message: status?" "" "직전에 사용자에게 쓴 글이 영어였습니다"
check "no reply_lang: reminder as before" "$T/seen.jsonl" UserPromptSubmit "" "Another Claude session sent a message: status?" "" "간결하게 답합니다."
check "tool batch: reminder and line as before" "$T/seen.jsonl" PostToolBatch 한국어 "" "" "한국어였으므로"
check "English final reply: block" "$T/seen.jsonl" Stop 한국어 "" "$EN" '"decision":"block"'
exit $fail
