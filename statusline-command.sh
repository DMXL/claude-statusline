#!/usr/bin/env bash
# Claude Code status line — inspired by Powerlevel10k lean theme
# Left:  dir branch | model effort | phase        (groups split by a grey pipe)
# Right: context tokens  usage bar  usage%
# The right half is right-aligned to $COLUMNS, which the harness exports, and
# when the content will not fit in it the line sheds segments by priority rather
# than letting the harness cut its tail. See the ladder under "Fit".

input=$(cat)

# One jq pass. The unit separator keeps empty fields intact, which a tab would
# not: bash treats tab as IFS whitespace and collapses runs of it.
IFS=$'\037' read -r cwd model effort tokens used session <<< "$(
  printf '%s' "$input" | jq -r '[
    (.cwd // .workspace.current_dir // ""),
    (.model.display_name // ""),
    (.effort.level // ""),
    (.context_window.total_input_tokens // 0 | tostring),
    (.context_window.used_percentage // "" | tostring),
    (.session_id // "")
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
# [ ] pending. Cancelled phases count toward the total but are never named.
#
# Both numbers come from the plan's own "Phase N:" labels when it has any: the
# numerator is the named phase's own N, the denominator the highest N in the
# file. A 0-indexed plan of six phases therefore reads "3/5", matching what the
# document calls them. With no labels at all it falls back to position and plain
# count. The label is stripped from the title, since the bar prints the number
# itself and the word "Phase" is left off entirely: beside a title, a bare "3/5"
# reads as a phase without spending five columns saying so.
#
# The parse yields a mode, because which phase to name is not one question:
#
#   live    a [/] exists, so that phase is in flight and is the only answer
#   flash   no [/], but a phase is finished and another is pending, so there are
#           two true things to say and the segment alternates between them
#   next    no [/] and nothing finished, so the plan has not been started
#   done    no [/] and nothing pending, so the plan is finished
#   bare    checkboxes exist but none of the above, e.g. every phase cancelled
#
# "Finished" here means the last [x] reached before the first pending line, in
# execution order. A [-] is not a finish and is never named, since "cancelled"
# is not an accomplishment to acknowledge.
phase_total=0
phase_mode=""
phase_index=-1
phase_title=""
phase_next_index=-1
phase_next_title=""
if [ -n "$plan" ]; then
  IFS=$'\037' read -r phase_total phase_mode phase_index phase_title \
                      phase_next_index phase_next_title <<< "$(awk '
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
    # Tabs go because the fields are joined by one separator and split by it
    # alone; a stray tab in a title would not break that, but a stray \037
    # would, and stripping both is cheaper than reasoning about which.
    function clean(s) {
      gsub(/[\t\037]/, " ", s)
      sub(/[[:space:]]+$/, "", s)
      sub(/^[Pp]hase[[:space:]]*[0-9]+[[:space:]]*[.:)-]?[[:space:]]*/, "", s)
      return s
    }
    /^- \[[xX]\] /  { n++; v = see(substr($0, 7))
                      if (!pi) { di = 1; dtxt = substr($0, 7); dpos = n; dnum = v }
                      next }
    /^- \[[\/~]\] / { n++; v = see(substr($0, 7))
                      if (!ci) { ci = 1; ctxt = substr($0, 7); cpos = n; cnum = v }
                      next }
    /^- \[-\] /     { n++; see(substr($0, 7)); next }
    /^- \[ \] /     { n++; v = see(substr($0, 7))
                      if (!pi) { pi = 1; ptxt = substr($0, 7); ppos = n; pnum = v }
                      next }
    END {
      total = (labelled && maxnum >= 1) ? maxnum : n
      mode = ""; idx = -1; title = ""; nidx = -1; ntitle = ""
      if (ci) {
        mode  = "live"
        idx   = (labelled && cnum >= 0) ? cnum : cpos
        title = clean(ctxt)
      } else if (di && pi) {
        mode   = "flash"
        idx    = (labelled && dnum >= 0) ? dnum : dpos
        title  = clean(dtxt)
        nidx   = (labelled && pnum >= 0) ? pnum : ppos
        ntitle = clean(ptxt)
      } else if (pi) {
        mode  = "next"
        idx   = (labelled && pnum >= 0) ? pnum : ppos
        title = clean(ptxt)
      } else if (di) {
        mode  = "done"
        idx   = (labelled && dnum >= 0) ? dnum : dpos
        title = clean(dtxt)
      } else if (n > 0) {
        mode = "bare"
        idx  = total
      }
      printf "%d\037%s\037%d\037%s\037%d\037%s", \
        total + 0, mode, idx + 0, title, nidx + 0, ntitle
    }
  ' "$plan")"
fi

# The five seconds between the two forms of a flash.
#
# Ticking a box used to make the segment jump silently from one pending phase to
# the next, which said nothing about the one just finished. In flash mode the
# segment names the finished phase for CLAUDE_STATUSLINE_FLASH seconds and the
# pending one from then on, so ticking a box is acknowledged before the bar
# moves on.
#
# Five seconds needs a start, and this script is stateless and runs only when
# the harness spawns it, so it keeps one line in $TMPDIR: a fingerprint of what
# is being displayed and the epoch it was first seen. A render whose fingerprint
# matches inherits that clock, one whose fingerprint differs resets it. The
# flash is therefore derived from the plan's state rather than animated over the
# top of it, which is what makes the plan changing mid flash a non-event:
# ticking a further box restarts the acknowledgement on the new phase, marking a
# [/] leaves flash mode altogether and renders that phase at once, and editing
# prose below the checklist changes no fingerprint and so changes nothing.
#
# The file is keyed by session id. Two sessions open on the same repo share the
# plan doc, and a clock keyed on the doc alone would have each re-flashing the
# other. A stale file from a previous boot fails the fingerprint and resets, and
# a timestamp in the future gives a negative age, which resets too.
#
# Two things to know. The clock is $EPOCHSECONDS, which is bash 5, and with no
# clock the segment simply settles on the pending phase. And the harness runs no
# timer unless statusLine.refreshInterval is set, so without it the first form
# holds until the next spawn happens for some other reason. Both degrade to
# showing the less useful of two true things, never to naming the wrong phase.
FLASH_SECS="${CLAUDE_STATUSLINE_FLASH:-5}"
case "$FLASH_SECS" in ''|*[!0-9]*) FLASH_SECS=0 ;; esac
flash_now="${CLAUDE_STATUSLINE_NOW:-${EPOCHSECONDS:-}}"
case "$flash_now" in ''|*[!0-9]*) flash_now="" ;; esac

phase_form="next"
if [ "$phase_mode" = "flash" ] && [ -n "$flash_now" ] && [ "$FLASH_SECS" -gt 0 ]; then
  fp="${phase_total}:${phase_index}:${phase_next_index}:${phase_title}:${phase_next_title}"
  sid="${session//[^A-Za-z0-9._-]/_}"
  state="${CLAUDE_STATUSLINE_STATE:-${TMPDIR:-/tmp}/claude-statusline-${sid:-nosession}}"
  saved_fp=""; saved_at=""
  if [ -r "$state" ]; then IFS=$'\037' read -r saved_fp saved_at < "$state"; fi
  age=-1
  if [ "$saved_fp" = "$fp" ]; then
    case "$saved_at" in
      ''|*[!0-9]*) ;;
      *) age=$((flash_now - saved_at)) ;;
    esac
  fi
  if [ "$age" -lt 0 ]; then
    # The stderr redirection goes first deliberately. Redirections are applied
    # left to right, so with it second bash reports a failing "> $state" to the
    # real stderr, which the harness copies into its debug log once a second.
    #
    # A state file that cannot be written means no clock can be kept at all, so
    # this falls back to what a missing clock does and settles on the pending
    # phase. Letting it stand at age zero instead would acknowledge the finished
    # phase on every render forever, which is the one outcome worse than not
    # acknowledging it.
    if printf '%s\037%s\n' "$fp" "$flash_now" 2>/dev/null > "$state"; then
      age=0
    else
      age="$FLASH_SECS"
    fi
  fi
  [ "$age" -lt "$FLASH_SECS" ] && phase_form="done"
fi

# Nerd Font glyphs (MesloLGS NF, matching the p10k prompt): U+F126 branch and
# U+F0E7 effort. Along with the bar characters they are deliberately kept out of
# the *_plain strings and counted in extra_cols instead, because each renders a
# single column but is three bytes, and ${#var} only agrees with that under a
# UTF-8 locale. A hook inherits whatever LANG the terminal had.
ICO_BRANCH=""
ICO_EFFORT=""
ICO_PHASE_DONE="✓"    # U+2713 CHECK MARK, the phase just finished
ICO_PHASE_NEXT="→"    # U+2192 RIGHTWARDS ARROW, the phase coming up
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

# ── Cells ────────────────────────────────────────────────────────────────────
#
# Every printable piece is a cell, held across parallel arrays: an id, the group
# it belongs to, its coloured form, the plain form that gets measured, the
# columns the plain form does not carry, and a role. Cells inside a group are
# joined by a space, groups by a grey pipe, and the left half is padded away from
# the right half.
#
# The per-cell width is what makes overflow handling possible at all. A single
# accumulated extra_cols cannot say how many columns come back when a segment is
# dropped, so the count has to live on the segment that owns it.
n_cells=0
cell_id=(); cell_g=(); cell_c=(); cell_p=(); cell_x=(); cell_r=(); cell_a=()

# add_cell id group coloured plain extra_columns [role]
#
# Role "div" marks a cell that exists only to separate two others. It is skipped
# whenever it would land at either end of what survives in its group, which is
# what keeps a dangling separator off the line.
add_cell() {
  cell_id[$n_cells]="$1"; cell_g[$n_cells]="$2"; cell_c[$n_cells]="$3"
  cell_p[$n_cells]="$4";  cell_x[$n_cells]="$5"; cell_r[$n_cells]="${6:-cell}"
  cell_a[$n_cells]=1
  eval "idx_$1=$n_cells"   # index by name, so the ladder never has to search
  n_cells=$((n_cells + 1))
}

drop_cell() {
  local n="idx_$1"
  eval "n=\${$n:--1}"
  [ "$n" -ge 0 ] && cell_a[$n]=0
  return 0
}

# Group 1: where you are
add_cell cwd 1 "\033[${C_DIR}m${short_cwd}\033[0m" "$short_cwd" 0
if [ -n "$branch" ]; then
  # Two extra columns: the glyph itself and the space after it, neither of which
  # is in the measured copy.
  add_cell branch 1 "\033[${C_BRANCH}m${ICO_BRANCH} ${branch}\033[0m" "$branch" 2
fi

# Group 2: what is answering. Effort is colour coded by level, since the level is
# the thing worth spotting at a glance rather than the word itself.
case "$effort" in
  max)          effort_color=$C_EFFORT_MAX ;;
  high|xhigh)   effort_color=$C_EFFORT_HIGH ;;
  medium)       effort_color=$C_EFFORT_MEDIUM ;;
  low|xlow)     effort_color=$C_EFFORT_LOW ;;
  *)            effort_color=$C_EFFORT_OTHER ;;
esac

[ -n "$model" ] && add_cell model 2 "\033[38;5;${C_MODEL}m${model}\033[0m" "$model" 0
if [ -n "$effort" ]; then
  add_cell effort 2 "\033[38;5;${effort_color}m${ICO_EFFORT} ${effort}\033[0m" "$effort" 2
fi

# Group 3: what is being worked on, as "N/M: title", led by a glyph that says
# which of the three things the number means: nothing for a phase in flight, a
# check for one just finished, an arrow for one not started. The glyph carries
# the state and the colour stays categorical, so magenta still means phase and
# nothing here competes with the usage colours.
#
# The short form, glyph and number without the title, is built here rather than
# in the ladder, so the ladder never has to know a colour. Both forms give back
# the same two columns the glyph and its space are worth, which is why the rung
# does not touch the cell's own count.
phase_num=""
phase_short_c=""
if [ "$phase_total" -gt 0 ] && [ -n "$phase_mode" ]; then
  phase_lead=""
  case "$phase_mode" in
    flash)
      if [ "$phase_form" = "done" ]; then
        phase_lead="$ICO_PHASE_DONE"
      else
        phase_lead="$ICO_PHASE_NEXT"
        phase_index="$phase_next_index"
        phase_title="$phase_next_title"
      fi
      ;;
    done) phase_lead="$ICO_PHASE_DONE" ;;
    next) phase_lead="$ICO_PHASE_NEXT" ;;
  esac
  [ "$phase_index" -ge 0 ] || phase_index="$phase_total"
  phase_num="${phase_index}/${phase_total}"
  phase_extra=0
  if [ -n "$phase_lead" ]; then
    phase_short_c="\033[${C_PHASE}m${phase_lead} ${phase_num}\033[0m"
    phase_extra=2
  else
    phase_short_c="\033[${C_PHASE}m${phase_num}\033[0m"
  fi
  pc="$phase_short_c"
  pp="${phase_num}"
  if [ -n "$phase_title" ] && [ "${#phase_title}" -le 32 ]; then
    pc+="\033[${C_PHASE}m:\033[0m \033[38;5;${C_PHASE_TITLE}m${phase_title}\033[0m"
    pp+=": ${phase_title}"
  fi
  add_cell phase 3 "$pc" "$pp" "$phase_extra"
fi

# Group 4: context tokens, then a usage bar and its percentage. The percentage is
# how much of the window is *used*, so the thresholds run cold to hot.
if [ -n "$tokens" ] && [ "$tokens" -gt 0 ] 2>/dev/null; then
  if [ "$tokens" -ge 1000000 ]; then
    tok=$(printf '%d.%dM' $((tokens / 1000000)) $(((tokens % 1000000) / 100000)))
  elif [ "$tokens" -ge 1000 ]; then
    tok=$(printf '%d.%dk' $((tokens / 1000)) $(((tokens % 1000) / 100)))
  else
    tok="$tokens"
  fi
  add_cell tokens 4 "\033[38;5;${C_TOKENS}m${tok}\033[0m" "$tok" 0
fi

bar_color=""
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

  # The bar measures as nothing and counts BAR_CELLS columns, for the same reason
  # the glyphs do.
  add_cell bar 4 "\033[38;5;${bar_color}m${bar_on}\033[0m\033[38;5;${C_BAR_EMPTY}m${bar_off}\033[0m" "" "$BAR_CELLS"
  add_cell pct 4 "\033[38;5;${bar_color}m${used_int}%\033[0m" "${used_int}%" 0
fi

# ── Compose ──────────────────────────────────────────────────────────────────
#
# Sets LEFT/LEFT_W and RIGHT/RIGHT_W from whatever is still alive. Called once
# per overflow rung, so it does the divider arithmetic afresh every time rather
# than baking it in at build time: a group emptied by the ladder takes its pipe
# with it, and a "div" cell left at either end of its group is skipped.
compose() {
  LEFT=""; LEFT_W=0; RIGHT=""; RIGHT_W=0
  local g list i pos count gc gw
  for g in 1 2 3 4; do
    list=""; i=0
    while [ "$i" -lt "$n_cells" ]; do
      if [ "${cell_g[$i]}" = "$g" ] && [ "${cell_a[$i]}" = "1" ]; then list="$list $i"; fi
      i=$((i + 1))
    done
    set -- $list
    count=$#
    gc=""; gw=0; pos=0
    for i in "$@"; do
      pos=$((pos + 1))
      if [ "${cell_r[$i]}" = "div" ] && { [ "$pos" -eq 1 ] || [ "$pos" -eq "$count" ]; }; then
        continue
      fi
      if [ -n "$gc" ]; then gc+=" "; gw=$((gw + 1)); fi
      gc+="${cell_c[$i]}"
      gw=$((gw + ${#cell_p[$i]} + cell_x[i]))
    done
    [ -n "$gc" ] || continue
    if [ "$g" = 4 ]; then
      RIGHT="$gc"; RIGHT_W="$gw"
    else
      if [ -n "$LEFT" ]; then
        LEFT+=" \033[38;5;${C_DIVIDER}m|\033[0m "
        LEFT_W=$((LEFT_W + 3))
      fi
      LEFT+="$gc"; LEFT_W=$((LEFT_W + gw))
    fi
  done
}

# ── Fit ──────────────────────────────────────────────────────────────────────
#
# COLUMNS is exported into the hook environment by the CLI, so it is the terminal
# width at spawn time, but the TUI frame eats a few columns. Four is the observed
# margin; override it with CLAUDE_STATUSLINE_MARGIN.
#
# Without this the script simply emitted a line too long and let ink truncate it,
# which cuts from the right end and so killed the usage group first, exactly the
# information the right half exists to show. The ladder instead sheds the
# cheapest thing first and stops the moment the line fits. Every rung is
# arithmetic and whole tokens: nothing spawns a process, and nothing slices a
# string, since ${str:0:n} counts bytes and would split a glyph.
#
# Two spaces is the minimum gap, so a fit means the line can still be aligned. If
# the ladder runs out and it still does not fit, the old behaviour stands: a
# two-space join and an ellipsis from ink.
margin="${CLAUDE_STATUSLINE_MARGIN:-4}"
budget=0
case "$COLUMNS" in
  ''|*[!0-9]*) ;;
  *) budget=$((COLUMNS - margin)) ;;
esac

compose
if [ "$budget" -gt 0 ]; then
  for rung in cwd_short phase_short cwd_drop bar_divider phase_drop \
              effort_drop tokens_drop branch_drop; do
    [ $((LEFT_W + 2 + RIGHT_W)) -le "$budget" ] && break
    case "$rung" in
      cwd_short)
        base="${short_cwd##*/}"
        if [ -n "$base" ] && [ "$base" != "$short_cwd" ] && [ -n "${idx_cwd:-}" ]; then
          cell_c[$idx_cwd]="\033[${C_DIR}m${base}\033[0m"
          cell_p[$idx_cwd]="$base"
        fi
        ;;
      phase_short)
        if [ -n "${idx_phase:-}" ]; then
          cell_c[$idx_phase]="$phase_short_c"
          cell_p[$idx_phase]="$phase_num"
        fi
        ;;
      cwd_drop)    drop_cell cwd ;;
      bar_divider)
        # The bar becomes a separator in the percentage's own colour, so the
        # right half still reads as one thing. As a div it disappears on its own
        # once the token count goes.
        if [ -n "${idx_bar:-}" ]; then
          cell_c[$idx_bar]="\033[38;5;${bar_color}m|\033[0m"
          cell_p[$idx_bar]="|"
          cell_x[$idx_bar]=0
          cell_r[$idx_bar]="div"
        fi
        ;;
      phase_drop)  drop_cell phase ;;
      effort_drop) drop_cell effort ;;
      tokens_drop) drop_cell tokens ;;
      branch_drop) drop_cell branch ;;
    esac
    compose
  done
fi

gap="  "
if [ "$budget" -gt 0 ]; then
  pad=$((budget - LEFT_W - RIGHT_W))
  if [ "$pad" -ge 2 ]; then printf -v gap '%*s' "$pad" ''; fi
fi

printf "%b%s%b" "$LEFT" "$gap" "$RIGHT"
