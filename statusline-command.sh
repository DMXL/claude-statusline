#!/usr/bin/env bash
# Claude Code status line — inspired by Powerlevel10k lean theme
# Left:  dir branch | model effort | phase        (groups split by a grey pipe)
# Right: context tokens  usage bar  usage%
# The right half is right-aligned to $COLUMNS, which the harness exports.

input=$(cat)

# One jq pass. The unit separator keeps empty fields intact, which a tab would
# not: bash treats tab as IFS whitespace and collapses runs of it.
IFS=$'\037' read -r cwd model effort tokens used <<< "$(
  printf '%s' "$input" | jq -r '[
    (.cwd // .workspace.current_dir // ""),
    (.model.display_name // ""),
    (.effort.level // ""),
    (.context_window.total_input_tokens // 0 | tostring),
    (.context_window.used_percentage // "" | tostring)
  ] | join("\u001f")' 2>/dev/null
)"

# Shorten home directory to ~
home="$HOME"
short_cwd="${cwd/#$home/\~}"

# Git branch (skip optional lock to avoid hangs).
#
# The binary is pinned deliberately. Where `git` on PATH resolves to a corporate
# auth wrapper rather than the real binary, it can cost roughly 390ms a call
# against 45ms, because it tries to authenticate against whatever remote it is
# handed. Three calls a render at refreshInterval 1 made that the single most
# expensive thing the status line did. Override with CLAUDE_STATUSLINE_GIT if
# the Homebrew path is wrong for your machine.
GIT="${CLAUDE_STATUSLINE_GIT:-/opt/homebrew/bin/git}"
[ -x "$GIT" ] || GIT=git

branch=""
repo_root=""
if "$GIT" -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$("$GIT" -C "$cwd" -c core.hooksPath=/dev/null symbolic-ref --short HEAD 2>/dev/null \
           || "$GIT" -C "$cwd" -c core.hooksPath=/dev/null rev-parse --short HEAD 2>/dev/null)
  repo_root=$("$GIT" -C "$cwd" -c core.hooksPath=/dev/null rev-parse --show-toplevel 2>/dev/null)
fi

# Phase progress from a plan file. Counts only checkboxes at column 0, so
# indented per-step checkboxes inside a phase do not inflate the total.
# Override the filename with CLAUDE_STATUSLINE_PLAN (e.g. PROGRESS.md).
plan_name="${CLAUDE_STATUSLINE_PLAN:-PLAN.md}"
plan=""
for dir in "$cwd" "$repo_root"; do
  [ -n "$dir" ] || continue
  for cand in "$dir/$plan_name" "$dir/docs/$plan_name"; do
    if [ -f "$cand" ]; then plan="$cand"; break 2; fi
  done
done

# Marker set, all at column 0: [x] done, [/] or [~] in progress, [-] cancelled,
# [ ] pending. The current phase is the first in-progress one, falling back to
# the first pending one, so a plan with no [/] behaves exactly as it did before.
# Cancelled phases count toward the total but are never current.
#
# Both numbers come from the plan's own "Phase N:" labels when it has any: the
# numerator is the current phase's own N, the denominator the highest N in the
# file. A 0-indexed plan of six phases therefore reads "Phase 3/5", matching
# what the document calls them. With no labels at all it falls back to position
# and plain count. The label is then stripped from the title, since the bar
# prints its own. An index of -1 means nothing is left to work on.
phase_total=0
phase_index=-1
phase_title=""
if [ -n "$plan" ]; then
  read -r phase_total phase_index phase_title <<< "$(awk '
    function phnum(s,   m) {
      if (!match(s, /^[Pp]hase[[:space:]]*[0-9]+/)) return -1
      m = substr(s, RSTART, RLENGTH)
      sub(/^[Pp]hase[[:space:]]*/, "", m)
      return m + 0
    }
    function see(s,   v) {
      v = phnum(s)
      if (v >= 0) { labelled = 1; if (v > maxnum) maxnum = v }
      return v
    }
    /^- \[[xX]\] /  { n++; see(substr($0, 7)); next }
    /^- \[[\/~]\] / { n++; v = see(substr($0, 7))
                     if (!ci) { ci = 1; cur = substr($0, 7); cpos = n; cnum = v } next }
    /^- \[-\] /     { n++; see(substr($0, 7)); next }
    /^- \[ \] /     { n++; v = see(substr($0, 7))
                     if (!pi) { pi = 1; pend = substr($0, 7); ppos = n; pnum = v } next }
    END {
      if (ci)      { title = cur;  pos = cpos; num = cnum }
      else if (pi) { title = pend; pos = ppos; num = pnum }
      else         { title = "";   pos = -1;   num = -1 }
      total = (labelled && maxnum >= 1) ? maxnum : n
      idx = -1
      if (pos > 0) idx = (labelled && num >= 0) ? num : pos
      sub(/[[:space:]]+$/, "", title)
      sub(/^[Pp]hase[[:space:]]*[0-9]+[[:space:]]*[.:)-]?[[:space:]]*/, "", title)
      printf "%d %d %s", total + 0, idx + 0, title
    }
  ' "$plan")"
fi

# Nerd Font glyphs (MesloLGS NF, matching the p10k prompt): U+F126 branch and
# U+F0E7 effort. Along with the bar characters they are deliberately kept out of
# the *_plain strings and counted in extra_cols instead, because each renders a
# single column but is three bytes, and ${#var} only agrees with that under a
# UTF-8 locale. A hook inherits whatever LANG the terminal had.
ICO_BRANCH=""
ICO_EFFORT=""
BAR_ON="█"
BAR_OFF="█"
BAR_CELLS=6

# Palette, in one place so a colour can be retuned without hunting through the
# render code. Basic ANSI (30-37) is remapped by the terminal's colour scheme
# and so follows a theme change; every 38;5;N is a fixed xterm value and does
# not. The location group deliberately keeps the basic colours it started with.
C_DIR=36              # basic cyan, follows the terminal theme
C_BRANCH=32           # basic green, follows the terminal theme
C_PHASE=35            # basic magenta, follows the terminal theme
C_DIVIDER=240         # grey pipe between groups
C_MODEL=250           # light grey
C_PHASE_TITLE=141     # light purple, a shade up from the phase number
C_TOKENS=245          # grey
C_BAR_EMPTY=239       # unfilled track, quieter than the divider
C_EFFORT_MAX=196      # red
C_EFFORT_HIGH=75      # blue, for high and xhigh
C_EFFORT_MEDIUM=76    # green
C_EFFORT_LOW=208      # orange, for low and xlow
C_EFFORT_OTHER=245    # anything unrecognised
C_USE_LOW=76          # under 50% used, green
C_USE_MID=178         # 50 to 69%, yellow
C_USE_HIGH=208        # 70 to 89%, orange
C_USE_FULL=196        # 90% and over, red

extra_cols=0

# Group 1: where you are
g1="\033[${C_DIR}m${short_cwd}\033[0m"
g1p="${short_cwd}"
if [ -n "$branch" ]; then
  g1+=" \033[${C_BRANCH}m${ICO_BRANCH} ${branch}\033[0m"
  g1p+=" ${branch}"
  extra_cols=$((extra_cols + 2))
fi

# Group 2: what is answering. Effort is colour coded by level, since the level
# is the thing worth spotting at a glance rather than the word itself.
case "$effort" in
  max)          effort_color=$C_EFFORT_MAX ;;
  high|xhigh)   effort_color=$C_EFFORT_HIGH ;;
  medium)       effort_color=$C_EFFORT_MEDIUM ;;
  low|xlow)     effort_color=$C_EFFORT_LOW ;;
  *)            effort_color=$C_EFFORT_OTHER ;;
esac

g2=""
g2p=""
if [ -n "$model" ]; then
  g2="\033[38;5;${C_MODEL}m${model}\033[0m"
  g2p="${model}"
fi
if [ -n "$effort" ]; then
  if [ -n "$g2" ]; then g2+=" "; g2p+=" "; fi
  g2+="\033[38;5;${effort_color}m${ICO_EFFORT} ${effort}\033[0m"
  g2p+="${effort}"
  extra_cols=$((extra_cols + 2))
fi

# Group 3: what is being worked on
g3=""
g3p=""
if [ "$phase_total" -gt 0 ]; then
  [ "$phase_index" -ge 0 ] || phase_index="$phase_total"
  g3="\033[${C_PHASE}mPhase ${phase_index}/${phase_total}\033[0m"
  g3p="Phase ${phase_index}/${phase_total}"
  if [ -n "$phase_title" ] && [ "${#phase_title}" -le 32 ]; then
    g3+="\033[${C_PHASE}m:\033[0m \033[38;5;${C_PHASE_TITLE}m${phase_title}\033[0m"
    g3p+=": ${phase_title}"
  fi
fi

# Join the non-empty groups with a grey pipe, so a missing group never leaves a
# dangling divider.
left=""
left_plain=""
for n in 1 2 3; do
  eval "seg=\$g${n}; segp=\$g${n}p"
  [ -n "$segp" ] || continue
  if [ -n "$left" ]; then
    left+=" \033[38;5;${C_DIVIDER}m|\033[0m "
    left_plain+=" | "
  fi
  left+="$seg"
  left_plain+="$segp"
done

# Right: context tokens, then a usage bar and its percentage. The percentage is
# how much of the window is *used*, so the thresholds run cold to hot.
right=""
right_plain=""

if [ -n "$tokens" ] && [ "$tokens" -gt 0 ] 2>/dev/null; then
  if [ "$tokens" -ge 1000000 ]; then
    tok=$(printf '%d.%dM' $((tokens / 1000000)) $(((tokens % 1000000) / 100000)))
  elif [ "$tokens" -ge 1000 ]; then
    tok=$(printf '%d.%dk' $((tokens / 1000)) $(((tokens % 1000) / 100)))
  else
    tok="$tokens"
  fi
  right="\033[38;5;${C_TOKENS}m${tok}\033[0m"
  right_plain="${tok}"
fi

if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  [ "$used_int" -lt 0 ] && used_int=0
  [ "$used_int" -gt 100 ] && used_int=100

  if   [ "$used_int" -lt 50 ]; then bar_color=$C_USE_LOW
  elif [ "$used_int" -lt 70 ]; then bar_color=$C_USE_MID
  elif [ "$used_int" -lt 90 ]; then bar_color=$C_USE_HIGH
  else                              bar_color=$C_USE_FULL
  fi

  # Rounded to the nearest cell, and never empty while any context is in use.
  filled=$(((used_int * BAR_CELLS + 50) / 100))
  [ "$filled" -eq 0 ] && [ "$used_int" -gt 0 ] && filled=1
  [ "$filled" -gt "$BAR_CELLS" ] && filled="$BAR_CELLS"

  # Built by loop rather than substring: ${str:0:n} counts bytes, not
  # characters, once the locale is not UTF-8, which would split a block glyph.
  bar_on=""
  bar_off=""
  i=0
  while [ "$i" -lt "$filled" ]; do bar_on+="$BAR_ON"; i=$((i + 1)); done
  while [ "$i" -lt "$BAR_CELLS" ]; do bar_off+="$BAR_OFF"; i=$((i + 1)); done

  if [ -n "$right" ]; then right+=" "; right_plain+=" "; fi
  right+="\033[38;5;${bar_color}m${bar_on}\033[0m\033[38;5;${C_BAR_EMPTY}m${bar_off}\033[0m"
  right+=" \033[38;5;${bar_color}m${used_int}%\033[0m"
  right_plain+=" ${used_int}%"
  extra_cols=$((extra_cols + BAR_CELLS))
fi

# Right-align by padding the gap. COLUMNS is exported into the hook environment
# by the CLI, so it is the terminal width at spawn time, but the TUI frame eats
# a few columns and ink truncates the line with an ellipsis once it overflows.
# Four is the observed margin; override it with CLAUDE_STATUSLINE_MARGIN. Falls
# back to a two-space join when COLUMNS is missing or the line already fills it.
gap="  "
margin="${CLAUDE_STATUSLINE_MARGIN:-4}"
case "$COLUMNS" in
  ''|*[!0-9]*) ;;
  *)
    pad=$((COLUMNS - margin - ${#left_plain} - ${#right_plain} - extra_cols))
    if [ "$pad" -ge 2 ]; then printf -v gap '%*s' "$pad" ''; fi
    ;;
esac

printf "%b%s%b" "$left" "$gap" "$right"
