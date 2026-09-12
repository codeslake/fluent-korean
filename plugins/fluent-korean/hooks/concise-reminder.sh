#!/bin/sh
# Output-style frontmatter has no per-turn reminder field, so a plugin style only gets
# the generic "<name> output style is active" line. This adds the sentence the built-in
# Concise style sends each turn, and only while a fluent-korean *-concise style is active.
event=$1
input=$(cat)

# Built-in style reminders skip subagents. Only the top-level keys are checked:
# tool_calls carries nested tool inputs that may hold their own "agent_id".
case ${input%%'"tool_calls"'*} in *'"agent_id"'*) exit 0 ;; esac

transcript=$(printf '%s' "$input" | sed -n 's/.*"transcript_path" *: *"\([^"]*\)".*/\1/p')

# The transcript records the style Claude Code actually applied on each request.
style=$(grep -o '"type":"output_style","style":"[^"]*"' "$transcript" 2>/dev/null | tail -n 1)

# The first prompt of a session has nothing recorded yet, so read the settings files
# /config writes, nearest first.
# ponytail: misses a style set only by --settings or managed policy on that first prompt.
if [ -z "$style" ]; then
  for f in "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.local.json" "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json" "$HOME/.claude/settings.json"; do
    style=$(grep -o '"outputStyle" *: *"[^"]*"' "$f" 2>/dev/null) && break
  done
fi
case $style in *fluent-korean*-concise'"') ;; *) exit 0 ;; esac

printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"Be concise: lead with the result, skip preamble and narration, keep only what the user needs."}}\n' "$event"
