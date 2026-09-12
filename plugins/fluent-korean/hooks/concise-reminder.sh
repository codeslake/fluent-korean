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
[ -f "$transcript" ] || exit 0

# ponytail: the active style is read from the transcript, so the first prompt of a session
# (nothing recorded yet) gets no reminder; the system prompt already carries the full rules.
style=$(grep -o '"type":"output_style","style":"[^"]*"' "$transcript" | tail -n 1)
case $style in *fluent-korean*-concise'"') ;; *) exit 0 ;; esac

printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"Be concise: lead with the result, skip preamble and narration, keep only what the user needs."}}\n' "$event"
