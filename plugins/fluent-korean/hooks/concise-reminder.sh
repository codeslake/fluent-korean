#!/bin/sh
# Output-style frontmatter has no per-turn reminder field, so a plugin style only gets
# the generic "<name> output style is active" line. This adds, in Korean, the reminder the
# built-in Concise style sends each turn, and only while a fluent-korean *-concise style is active.
# The plugin option reply_lang (settings.json "pluginConfigs", read from user settings only)
# adds one line naming the language of text written for the user, under a fluent-korean
# style only; unset, nothing about language is added. FLUENT_KOREAN_REPLY_LANG in "env" is
# still read when the option is unset.
event=$1
input=$(cat)

# Built-in style reminders skip subagents. Only the top-level keys are checked:
# tool_calls carries nested tool inputs that may hold their own "agent_id".
case ${input%%'"tool_calls"'*} in *'"agent_id"'*) exit 0 ;; esac

# Output-style frontmatter cannot carry hooks (the 2.1.284 schema is name, description,
# keep-coding-instructions, force-for-plugin, strict) and the hook payload/env carry no
# style, so the settings files /config writes are the only cheap source. First file that
# has an "outputStyle" key wins, nearest first.
# ponytail: misses a style set only via --settings or managed policy, which never lands
# in one of these files.
for f in "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.local.json" "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json" "$HOME/.claude/settings.local.json" "$HOME/.claude/settings.json"; do
  style=$(grep -o '"outputStyle" *: *"[^"]*"' "$f" 2>/dev/null) && break
done

# Quotes and backslashes would break the JSON below. The language line belongs to the
# fluent-korean styles only: under any other style it is never added.
lang=$(printf '%s' "${CLAUDE_PLUGIN_OPTION_REPLY_LANG:-${FLUENT_KOREAN_REPLY_LANG:-}}" | tr -d '"\\')
case $style in *'"fluent-korean:'*) ;; *) lang= ;; esac
lang_line=
# Conditional on the user's own language, so a question typed in another language still
# gets an answer in that language. The prefix up to "언어" stays fixed: measurement keys on it.
[ -n "$lang" ] && lang_line="사용자에게 쓰는 글(CLI 답변)의 언어: 사용자가 직접 입력한 마지막 메시지를 ${lang}로 썼다면 ${lang}로 씁니다. 알림이나 다른 세션의 메시지로 시작된 턴에도 이 기준을 따릅니다. 코드, 주석, 커밋 메시지, 다른 사람에게 보내는 글에는 적용하지 않습니다."

# The model misjudges "the user's last typed message" when the text right before its reply is
# English (a notification, a peer message, hook feedback, a skill body): measured 13 of 46
# replies in English with the line above in context. So the hook decides it: each prompt the
# user typed records whether it was Korean, per session, and later turns state the result.
# shortcut: Hangul detection only, so this applies when the language is 한국어; any other value
# keeps the conditional line.
if [ "$lang" = 한국어 ]; then
  sid=${input#*'"session_id"'}; sid=${sid#*'"'}; sid=$(printf '%s' "${sid%%'"'*}" | tr -cd 'A-Za-z0-9-')
  state="${TMPDIR:-/tmp}/fluent-korean-lang-$sid"
  if [ "$event" = UserPromptSubmit ] && [ -n "$sid" ]; then
    p=${input#*'"prompt"'}; p=${p#*'"'}
    case $p in
      '<'*|/*|'Another Claude session'*|'Stop hook feedback'*|'Here is a note offered by a side agent'*|'Base directory for this skill'*|'[SYSTEM'*) ;;
      *) if printf '%s' "$p" | LC_ALL=C grep -q "$(printf '[\352-\355]')"; then echo ko > "$state"
         elif printf '%s' "${p%%'"'*}" | grep -q '[A-Za-z]'; then echo other > "$state"; fi ;;
    esac
  fi
  [ "$(cat "$state" 2>/dev/null)" = ko ] && lang_line="사용자에게 쓰는 글(CLI 답변)의 언어: 한국어. 사용자가 직접 입력한 마지막 메시지가 한국어였으므로, 이번 응답과 중간 보고는 한국어로 씁니다. 직전 입력이 알림, 다른 세션의 메시지, hook 피드백, 스킬 본문처럼 영어로 되어 있어도 같습니다. 코드, 주석, 커밋 메시지, 다른 사람에게 보내는 글에는 적용하지 않습니다."
fi

emit() { printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$1"; }

# Built-in reminders also skip a turn woken by a background-task notification, which still
# fires UserPromptSubmit with the notification as its prompt. The language line does not:
# such a turn answers the user too.
case $input in *'"prompt"'*':'*'"<task-notification>'*)
  [ -n "$lang_line" ] && emit "$lang_line"
  exit 0 ;;
esac

concise=
case $style in *fluent-korean*-concise'"') concise="간결하게 답합니다. 결과를 먼저 밝히고, 서두와 작업 과정에 대한 서술은 생략하며, 사용자에게 필요한 내용만 전달합니다." ;; esac

msg="$concise${concise:+${lang_line:+ }}$lang_line"
[ -n "$msg" ] && emit "$msg"
exit 0
