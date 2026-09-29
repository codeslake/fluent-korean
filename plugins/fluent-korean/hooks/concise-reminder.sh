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

# Output-style frontmatter cannot carry hooks (the 2.1.284 schema is name, description,
# keep-coding-instructions, force-for-plugin, strict) and the hook payload/env carry no
# style, so the settings files /config writes are the only cheap source. First file that
# has an "outputStyle" key wins, nearest first.
# ponytail: misses a style set only via --settings or managed policy, which never lands
# in one of these files.
for f in "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.local.json" "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json" "$HOME/.claude/settings.local.json" "$HOME/.claude/settings.json"; do
  style=$(grep -o '"outputStyle" *: *"[^"]*"' "$f" 2>/dev/null) && break
done
case $style in *fluent-korean*-concise'"') ;; *) exit 0 ;; esac

printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"간결하게 답합니다. 결과를 먼저 밝히고, 서두와 작업 과정에 대한 서술은 생략하며, 사용자에게 필요한 내용만 전달합니다."}}\n' "$event"
