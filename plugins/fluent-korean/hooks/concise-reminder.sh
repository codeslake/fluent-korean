#!/bin/sh
# Output-style frontmatter has no per-turn reminder field, so a plugin style only gets
# the generic "<name> output style is active" line. This adds, in Korean, the reminder the
# built-in Concise style sends each turn, and only while a fluent-korean *-concise style is active.
event=$1
input=$(cat)

# Built-in style reminders skip subagents. Only the top-level keys are checked:
# tool_calls carries nested tool inputs that may hold their own "agent_id".
case ${input%%'"tool_calls"'*} in *'"agent_id"'*) exit 0 ;; esac

# They also skip a turn woken by a background-task notification, which still fires
# UserPromptSubmit with the notification as its prompt.
case $input in *'"prompt"'*':'*'"<task-notification>'*) exit 0 ;; esac

case $input in
  *'"transcript_path"'*)
    transcript=${input#*'"transcript_path"'}
    transcript=${transcript#*:}
    transcript=${transcript#*\"}
    transcript=${transcript%%\"*}
    ;;
  *) transcript= ;;
esac

# The transcript records the style Claude Code actually applied on each request, and a
# session that has used the style at all keeps re-recording it, so the record we want is
# almost always near the end. Check the last 1 MiB first (tail seeks on GNU and BSD, no
# tac needed) and only pay for the whole-file grep when that tail has no record at all.
style=$(tail -c 1048576 "$transcript" 2>/dev/null | grep -o '"type":"output_style","style":"[^"]*"' | tail -n 1)
[ -z "$style" ] && style=$(grep -o '"type":"output_style","style":"[^"]*"' "$transcript" 2>/dev/null | tail -n 1)

# The first prompt of a session has nothing recorded yet, so read the settings files
# /config writes, nearest first.
# ponytail: misses a style set only by --settings or managed policy on that first prompt.
if [ -z "$style" ]; then
  for f in "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.local.json" "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json" "$HOME/.claude/settings.json"; do
    style=$(grep -o '"outputStyle" *: *"[^"]*"' "$f" 2>/dev/null) && break
  done
fi
case $style in *fluent-korean*-concise'"') ;; *) exit 0 ;; esac

printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"간결하게 답합니다. 결과를 먼저 밝히고, 서두와 작업 과정에 대한 서술은 생략하며, 사용자에게 필요한 내용만 전달합니다."}}\n' "$event"
