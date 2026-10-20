#!/bin/sh
# Output-style frontmatter has no per-turn reminder field, so a plugin style only gets
# the generic "<name> output style is active" line. This adds, in Korean, the reminder the
# built-in Concise style sends each turn, and only while a fluent-korean *-concise style is active.
# The plugin option reply_lang (settings.json "pluginConfigs", read from user settings only)
# adds one line naming the language of text written for the user, under a fluent-korean
# style only; unset, nothing about language is added. FLUENT_KOREAN_REPLY_LANG in "env" is
# still read when the option is unset.
event=$1
skip=
input=$(cat)

# Built-in style reminders skip subagents. Only the top-level keys are checked:
# tool_calls carries nested tool inputs that may hold their own "agent_id".
case ${input%%'"tool_calls"'*} in *'"agent_id"'*) exit 0 ;; esac

# Plugin option ptb_every: remind on every Nth tool batch of a prompt (1, the default, is
# every batch, as the built-in Concise style does; 0 is never). Nothing can change between
# batches of one turn, so a larger N cuts repeated context.
every=$(printf '%s' "${CLAUDE_PLUGIN_OPTION_PTB_EVERY:-1}" | tr -cd 0-9); every=${every:-1}
if [ "$event" = PostToolBatch ] && [ "$every" -eq 0 ]; then
  skip=1
elif [ "$event" = PostToolBatch ] && [ "$every" -ne 1 ]; then
  k=${input#*'"session_id"'}; k=${k#*'"'}; k=$(printf '%s' "${k%%'"'*}" | tr -cd 'A-Za-z0-9-')
  q=${input#*'"prompt_id"'}; q=${q#*'"'}; q=$(printf '%s' "${q%%'"'*}" | tr -cd 'A-Za-z0-9-')
  cf="${TMPDIR:-/tmp}/fluent-korean-ptb-$k"
  read -r cq cn 2>/dev/null < "$cf"
  [ "$cq" = "$q" ] && n=$((cn + 1)) || n=1
  echo "$q $n" > "$cf"
  [ $((n % every)) -eq 0 ] || skip=1
fi

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
# English (a notification, a peer message, hook feedback, a skill body), so the hook decides it
# from the transcript: the last prompt whose origin is "human" (typed or queued by the user;
# plugin, peer and notification prompts carry their own origin kind, and the hook payload does
# not say which one it is). The prompt being submitted is not in the transcript yet, so a
# UserPromptSubmit sees the previous one, which is what "last typed" means until it lands.
# Once one user-facing text slips into English the next ones follow it about half the time,
# and the standing line does not break that (measured: 46% English after an English text with
# the line in between, 9% after a Korean one), so an English last text is quoted back.
# shortcut: Hangul detection only, so this applies when the language is 한국어; any other value
# keeps the conditional line.
if [ "$lang" = 한국어 ]; then
  tp=${input#*'"transcript_path"'}; tp=${tp#*'"'}; tp=${tp%%'"'*}
  # The payload goes to a file: a tool batch can carry megabytes of output.
  pf=$(mktemp "${TMPDIR:-/tmp}/fluent-korean-payload.XXXXXX") && printf '%s' "$input" > "$pf"
  got=$(python3 -I - "$tp" "$pf" 2>/dev/null <<'PY'
import json, os, re, sys
def lang(t):
    t = re.sub(r'```.*?```|`[^`]*`|https?://\S+|(?:~|/)[\w./-]+', ' ', t, flags=re.S)
    h, a = len(re.findall('[가-힣]', t)), len(re.findall('[A-Za-z]', t))
    return ('ko' if h else ('other' if a else None)), t, h, a
def text(c):
    return c if isinstance(c, str) else ''.join(b.get('text', '') for b in (c or []) if isinstance(b, dict) and b.get('type') == 'text')
p = sys.argv[1]; rec = drift = None
try:
    size = os.path.getsize(p)
except OSError:
    print('none|'); sys.exit()
for start in (max(0, size - 1000000), 0):
    with open(p, 'rb') as f:
        f.seek(start); lines = f.read().decode('utf-8', 'replace').splitlines()
    for l in reversed(lines):
        if rec and drift is not None: break
        try: r = json.loads(l)
        except ValueError: continue
        if not isinstance(r, dict) or r.get('isSidechain'): continue
        m = (r.get('message') or {}).get('content')
        if drift is None and r.get('type') == 'assistant':
            ts = [b.get('text', '') for b in (m or []) if isinstance(b, dict) and b.get('type') == 'text' and b.get('text', '').strip()]
            if ts:
                g, s, h, a = lang(ts[-1])
                drift = re.sub(r'[\x00-\x1f"\\]', ' ', ' '.join(s.split()))[:60] if h < a * 0.2 and a >= 20 else ''
        if not rec and r.get('type') == 'user' and (r.get('origin') or {}).get('kind') == 'human':
            s = text(m)
            # a side agent's note forwarded by the user: only the words typed after the quoted lines
            if s.startswith('Here is a note offered by a side agent'):
                s = '\n'.join(x for x in s.splitlines()[1:] if not x.startswith('>'))
            if s.strip() and not s.lstrip().startswith(('<', '/')):
                rec = lang(s)[0]
    if rec or start == 0: break
# Experiment (2026-10-20): the first slip into English comes mostly right after tool output
# (11.8% vs 2.7% with no tool call). Sessions whose id ends in an even hex digit get a line
# naming English tool output, so the two halves can be compared in the field.
tool = ''
try:
    pl = json.load(open(sys.argv[2]))
    if pl.get('hook_event_name') == 'PostToolBatch' and int(pl.get('session_id', 'x')[-1], 16) % 2 == 0:
        out = ' '.join(str(c.get('tool_response', '')) for c in pl.get('tool_calls') or [] if isinstance(c, dict))
        if len(re.findall('[A-Za-z]', out)) >= 300 and len(re.findall('[가-힣]', out)) * 20 < len(re.findall('[A-Za-z]', out)): tool = 'en'
except (OSError, ValueError, IndexError): pass
print('%s|%s|%s' % (rec or 'none', drift or '', tool))
PY
)
  rm -f "$pf"
  rec=${got%%|*}; rest=${got#*|}; drift=${rest%%|*}; tool=${rest#*|}
  case $rec in
    none|'') lang_line="사용자에게 쓰는 글(CLI 답변)의 언어: 한국어. 이 세션에서 사용자가 직접 입력한 메시지가 아직 없으므로, 이번 응답과 중간 보고는 한국어로 씁니다. 직전 입력이 알림, 다른 세션의 메시지, hook 피드백, 스킬 본문처럼 영어로 되어 있어도 같습니다. 코드, 주석, 커밋 메시지, 다른 사람에게 보내는 글에는 적용하지 않습니다." ;;
    ko) lang_line="사용자에게 쓰는 글(CLI 답변)의 언어: 한국어. 사용자가 직접 입력한 마지막 메시지가 한국어였으므로, 이번 응답과 중간 보고는 한국어로 씁니다. 직전 입력이 알림, 다른 세션의 메시지, hook 피드백, 스킬 본문처럼 영어로 되어 있어도 같습니다. 코드, 주석, 커밋 메시지, 다른 사람에게 보내는 글에는 적용하지 않습니다." ;;
  esac
  case $rec in none|''|ko) [ -n "$drift" ] && lang_line="${lang_line%%.*}. 직전에 사용자에게 쓴 글이 영어였습니다(「${drift}…」). ${lang_line#*. }" && skip= ;; esac
  case $rec in none|''|ko) [ -z "$drift" ] && [ "$tool" = en ] && lang_line="${lang_line%%.*}. 방금 받은 도구 출력이 영어입니다. 이어서 쓰는 글은 한 줄짜리 진행 보고도 한국어로 씁니다. ${lang_line#*. }" && skip= ;; esac
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

[ -n "$skip" ] && exit 0
msg="$concise${concise:+${lang_line:+ }}$lang_line"
[ -n "$msg" ] && emit "$msg"
exit 0
