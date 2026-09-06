#!/usr/bin/env bash
# Render matrix for statusline-command.sh.
#   ./test/render-cases.sh          render every case for eyeballing
#   ./test/render-cases.sh --check  assert widths, phase parsing and the overflow
#                                   ladder, exit non-zero on drift
#
# The width assertion is the point. Every cell is built twice, once with colour
# and once plain, and only the plain copy is measured, so any new cell whose
# printed width differs from its measured width silently pushes the line off.
# Glyphs are one column but three bytes, so the check runs under LC_ALL=C as well
# to catch a glyph that leaked into a measured string.

set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$here/statusline-command.sh"
margin="${CLAUDE_STATUSLINE_MARGIN:-4}"
check=0
[ "${1:-}" = "--check" ] && check=1

fixtures="$(mktemp -d)"
trap 'rm -rf "$fixtures"' EXIT

# A throwaway repo, so the branch segment is exercised regardless of whether the
# directory the suite happens to run from is under git. Without this the branch
# icon's width accounting is never executed and a break in it passes silently.
GIT_BIN="${CLAUDE_STATUSLINE_GIT:-/opt/homebrew/bin/git}"
[ -x "$GIT_BIN" ] || GIT_BIN=git
repo="$fixtures/repo"
mkdir -p "$repo/docs"
"$GIT_BIN" -C "$repo" init -q -b main >/dev/null 2>&1
printf -- '- [x] Phase 0: Scaffold\n- [/] Phase 1: Rendering\n- [ ] Phase 2: Ship\n' > "$repo/docs/PLAN.md"

# U+2588 FULL BLOCK, written by codepoint rather than pasted, for the same reason
# the script writes its glyphs that way. printf '\uXXXX' is bash 4.2 and up, and
# /bin/bash here is 3.2, so the UTF-8 bytes go in directly.
BLOCK=$(printf '\xe2\x96\x88')
CHECK=$(printf '\xe2\x9c\x93')   # U+2713 CHECK MARK, a finished phase
ARROW=$(printf '\xe2\x86\x92')   # U+2192 RIGHTWARDS ARROW, a pending one

pass=0
fail=0

strip() { sed 's/\x1b\[[0-9;]*m//g'; }
cols()  { python3 -c 'import sys;print(len(sys.stdin.read()))'; }

export CLAUDE_STATUSLINE_NOW=1000
export CLAUDE_STATUSLINE_STATE="$fixtures/flash-state"

render() { printf '%s' "$2" | env COLUMNS="$1" bash "$script"; }

# render with the flash clock and its state file pinned, for the cases that turn
# on either. A fresh state file plus any clock reads as age zero, so a case that
# does not say otherwise sees the first of the two forms.
render_at() { # clock, state file, columns, payload
  printf '%s' "$4" \
    | env COLUMNS="$3" CLAUDE_STATUSLINE_NOW="$1" CLAUDE_STATUSLINE_STATE="$2" \
          CLAUDE_STATUSLINE_FLASH="${FLASH_OVERRIDE:-5}" bash "$script"
}

# The phase group, or an empty string when there is none. Anchored to its leading
# divider and to the end of the line, because a bare "N/M" also matches a fixture
# path under mktemp, and the glyph is optional because a phase in flight has none.
phase_group() {
  sed 's/[[:space:]]*$//' \
    | grep -oE "\| (($CHECK|$ARROW) )?[0-9]+/[0-9]+(: [^|]*)?$" \
    | sed 's/^| //'
}

# name, columns, payload, [floor]
#
# Strict by default: the line must be exactly COLUMNS - margin wide. The overflow
# ladder is what makes that hold at any width, so "floor" is only for a terminal
# narrower than the last rung can serve, where the script deliberately falls back
# to a two-space join and lets the harness truncate. Do not relax a case to floor
# to make it pass; an over-long line is exactly what an under-counted glyph
# produces.
case_render() {
  local name="$1" width="$2" payload="$3" mode="${4:-strict}"
  local out plain n
  out="$(render "$width" "$payload")"
  plain="$(printf '%s' "$out" | strip)"
  if [ "$check" -eq 0 ]; then
    printf '%s\n' "$out"
    return
  fi
  n="$(printf '%s' "$plain" | cols)"
  local want=$((width - margin))
  local ok=0
  if [ -z "${plain// /}" ]; then
    ok=1                                   # nothing to render, nothing to align
  elif [ "$mode" = "floor" ]; then
    [ "$n" -gt "$want" ] && ok=1           # past the last rung, fallback expected
  else
    [ "$n" -eq "$want" ] && ok=1
  fi
  if [ "$ok" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  %-34s width %s: got %s cols, want %s\n' "$name" "$width" "$n" "$want" >&2
    printf '      [%s]\n' "$plain" >&2
  fi
}

# name, expected group (or empty), plan body, [clock], [flash length]
#
# Each case gets its own state file, so one case can never inherit another's
# clock. Two renders run: the first establishes the clock at 1000 and its output
# is thrown away, the second asserts at $clock. A case wanting the first of the
# two forms therefore leaves the clock at 1000 and one wanting the second asks
# for a later one. Without the priming render every clock would read as age zero,
# because a fresh state file is itself the reset.
case_phase() {
  local name="$1" want="$2" body="$3" now="${4:-1000}" flash="${5:-5}"
  local dir="$fixtures/$name"
  mkdir -p "$dir"
  printf '%s' "$body" > "$dir/PLAN.md"
  local got payload
  payload="{\"cwd\":\"$dir\",\"session_id\":\"$name\",\"model\":{\"display_name\":\"M\"}}"
  FLASH_OVERRIDE="$flash" render_at 1000 "$dir/state" 200 "$payload" > /dev/null
  got="$(FLASH_OVERRIDE="$flash" render_at "$now" "$dir/state" 200 "$payload" \
        | strip | phase_group)"
  if [ "$check" -eq 0 ]; then
    printf '%-28s -> %s\n' "$name" "$got"
    return
  fi
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  %-34s got [%s], want [%s]\n' "$name" "$got" "$want" >&2
  fi
}

# Every case points at a fixture, never at the project directory. An earlier
# version used "$here" and so rendered this project's own plan doc, which meant
# the assertions moved every time a phase was ticked.
D="$repo"
full='{"cwd":"'"$D"'","model":{"display_name":"DeepSeek V4 Pro"},"effort":{"level":"xhigh"},"context_window":{"total_input_tokens":142347,"used_percentage":71}}'

[ "$check" -eq 0 ] && echo "── payload matrix ──"
case_render "full"              180 "$full"
case_render "full narrow"        96 "$full"
case_render "full wide"         240 "$full"
case_render "below the floor"    22 "$full" floor
case_render "no effort"         180 '{"cwd":"'"$D"'","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":8200,"used_percentage":12}}'
case_render "no model"          180 '{"cwd":"'"$D"'","context_window":{"total_input_tokens":8200,"used_percentage":12}}'
case_render "no git no plan"    120 '{"cwd":"/tmp","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":8200,"used_percentage":12}}'
case_render "no usage yet"      120 '{"cwd":"/tmp","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":0,"used_percentage":null}}'
case_render "no usage narrow"    40 '{"cwd":"'"$D"'","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":0,"used_percentage":null}}'
case_render "million tokens"    120 '{"cwd":"/tmp","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":1420000,"used_percentage":100}}'
case_render "git branch"        180 '{"cwd":"'"$repo"'","model":{"display_name":"Opus 5"},"effort":{"level":"high"},"context_window":{"total_input_tokens":8200,"used_percentage":33}}'
case_render "git branch narrow"  96 '{"cwd":"'"$repo"'","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":8200,"used_percentage":33}}'
case_render "git subdir"        180 '{"cwd":"'"$repo"'/docs","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":8200,"used_percentage":33}}'
case_render "empty payload"     120 '{}'
case_render "malformed stdin"   120 'not json'

# ── The glyph forms, at width ────────────────────────────────────────────────
#
# The repo above carries a [/] in its plan and so renders no glyph at all, which
# left both forms of the two-form segment outside every width assertion. A glyph
# is one column and three bytes, so a form that let one into its measured copy
# runs two columns long, and nothing about the line looks wrong until something
# is aligned against it.
#
# Neither plan here needs a clock. A plan with something finished and something
# pending shows the check at the frozen clock, and a plan with nothing finished
# at all has no second form to wait for, so it shows the arrow at any clock.
repo_check="$fixtures/repo-check"
repo_arrow="$fixtures/repo-arrow"
mkdir -p "$repo_check/docs" "$repo_arrow/docs"
"$GIT_BIN" -C "$repo_check" init -q -b main >/dev/null 2>&1
"$GIT_BIN" -C "$repo_arrow" init -q -b main >/dev/null 2>&1
printf -- '- [x] Phase 0: Scaffold\n- [x] Phase 1: Extraction\n- [ ] Phase 2: Rendering\n' \
  > "$repo_check/docs/PLAN.md"
printf -- '- [ ] Phase 1: Scaffold\n- [ ] Phase 2: Rendering\n' \
  > "$repo_arrow/docs/PLAN.md"
payload_check='{"cwd":"'"$repo_check"'","session_id":"wcheck","model":{"display_name":"DeepSeek V4 Pro"},"effort":{"level":"xhigh"},"context_window":{"total_input_tokens":142347,"used_percentage":71}}'
payload_arrow='{"cwd":"'"$repo_arrow"'","session_id":"warrow","model":{"display_name":"DeepSeek V4 Pro"},"effort":{"level":"xhigh"},"context_window":{"total_input_tokens":142347,"used_percentage":71}}'

[ "$check" -eq 0 ] && echo && echo "── glyph forms ──"
for width in 60 90 120 160 200 240; do
  case_render "check form $width"  "$width" "$payload_check"
  case_render "arrow form $width"  "$width" "$payload_arrow"
done

[ "$check" -eq 0 ] && echo && echo "── effort levels ──"
for e in low medium high xhigh max bogus; do
  case_render "effort $e" 100 '{"cwd":"/tmp","model":{"display_name":"Opus 5"},"effort":{"level":"'"$e"'"},"context_window":{"total_input_tokens":8200,"used_percentage":40}}'
done

[ "$check" -eq 0 ] && echo && echo "── usage thresholds ──"
for u in 0 1 12 49 50 69 70 89 90 100; do
  case_render "used $u%" 100 '{"cwd":"/tmp","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":142347,"used_percentage":'"$u"'}}'
done

[ "$check" -eq 0 ] && echo && echo "── phase parsing ──"
case_phase "live"           "2/3: Rendering" '- [x] Phase 1: Scaffold
- [/] Phase 2: Rendering
- [ ] Phase 3: Ship'

case_phase "live tilde"     "3/4: Rendering" '- [x] Phase 1: Scaffold
- [ ] Phase 2: Deferred
- [~] Phase 3: Rendering
- [ ] Phase 4: Ship'

case_phase "live reordered" "3/5: D" '- [x] Phase 0: A
- [x] Phase 1: B
- [x] Phase 2: C
- [/] Phase 3: D
- [ ] Phase 5: E
- [ ] Phase 4: F'

case_phase "live long title" "2/2" '- [x] Phase 1: A
- [/] Phase 2: A title that is definitely longer than thirty two characters'

# The flash pair, asserted from both ends of the five seconds. Every one of these
# renders twice below with a later clock, because half the contract of this
# segment is what it stops saying.
zero='- [x] Phase 0: Scaffold
- [x] Phase 1: Extract
- [x] Phase 2: Parse
- [ ] Phase 3: Rendering
- [ ] Phase 4: Ship
- [ ] Phase 5: Polish'
case_phase "flash done"     "$CHECK 2/5: Parse"     "$zero" 1000
case_phase "flash next"     "$ARROW 3/5: Rendering" "$zero" 1005
case_phase "flash boundary" "$CHECK 2/5: Parse"     "$zero" 1004
case_phase "flash off"      "$ARROW 3/5: Rendering" "$zero" 1000 0

# A cancelled phase is never the one acknowledged, so the check names phase 1
# rather than the [-] immediately above the pending line.
cancelled='- [x] Phase 1: A
- [-] Phase 2: Dropped
- [ ] Phase 3: Rendering'
case_phase "cancelled done" "$CHECK 1/3: A"         "$cancelled" 1000
case_phase "cancelled next" "$ARROW 3/3: Rendering" "$cancelled" 1099

unlabelled='- [x] Scaffold
- [ ] Rendering
- [ ] Ship'
case_phase "unlabelled done" "$CHECK 1/3: Scaffold"  "$unlabelled" 1000
case_phase "unlabelled next" "$ARROW 2/3: Rendering" "$unlabelled" 1010

# Nothing finished, so nothing to acknowledge and no flash: the arrow form is
# the only one this plan ever shows, at any clock.
unstarted='- [ ] Phase 1: Scaffold
- [ ] Phase 2: Ship'
case_phase "unstarted"      "$ARROW 1/2: Scaffold" "$unstarted" 1000
case_phase "unstarted later" "$ARROW 1/2: Scaffold" "$unstarted" 9999

# Nothing pending, so the check form is the only one, again at any clock. This
# used to render a bare "5/5" with no title at all.
alldone='- [x] Phase 0: A
- [x] Phase 1: B
- [x] Phase 5: C'
case_phase "all done"       "$CHECK 5/5: C" "$alldone" 1000
case_phase "all done later" "$CHECK 5/5: C" "$alldone" 9999

# Neither finished nor pending, so neither glyph applies and the number stands
# on its own.
case_phase "all cancelled"  "2/2" '- [-] Phase 1: A
- [-] Phase 2: B'

case_phase "no checkboxes"  "" '# just a document

Nothing to parse here.
'

# ── The flash clock ─────────────────────────────────────────────────────────
#
# What the pair shows depends on what it showed before, so the interesting cases
# are sequences rather than single renders. The script is stateless and event
# driven, and the whole point of fingerprinting the display rather than watching
# the plan's mtime is that only a change to what is being said restarts the five
# seconds. That is asserted here and nowhere else.
flash_dir="$fixtures/sequence"
flash_state="$flash_dir/state"
mkdir -p "$flash_dir"

flash_plan() { printf '%s' "$1" > "$flash_dir/PLAN.md"; }
flash_read() { # clock -> the phase group at that clock
  render_at "$1" "$flash_state" 200 \
    "{\"cwd\":\"$flash_dir\",\"session_id\":\"sequence\",\"model\":{\"display_name\":\"M\"}}" \
    | strip | phase_group
}
flash_step() { # label, clock, expected
  local got
  got="$(flash_read "$2")"
  if [ "$check" -eq 0 ]; then
    printf '%-38s -> %s\n' "$1" "$got"
    return
  fi
  if [ "$got" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  %-34s got [%s], want [%s]\n' "$1" "$got" "$3" >&2
  fi
}

[ "$check" -eq 0 ] && echo && echo "── flash clock ──"

base='- [x] Phase 1: Scaffold
- [x] Phase 2: Extraction
- [ ] Phase 3: Rendering
- [ ] Phase 4: Overflow'

rm -f "$flash_state"
flash_plan "$base"
flash_step "seq: first render acknowledges"   1000 "$CHECK 2/4: Extraction"
flash_step "seq: still inside the window"     1004 "$CHECK 2/4: Extraction"
flash_step "seq: settles on what is next"     1005 "$ARROW 3/4: Rendering"
flash_step "seq: stays settled"               1500 "$ARROW 3/4: Rendering"

# Ticking another box mid settle restarts the acknowledgement on the new phase,
# which is the case that has no answer at all without a fingerprint.
flash_plan '- [x] Phase 1: Scaffold
- [x] Phase 2: Extraction
- [x] Phase 3: Rendering
- [ ] Phase 4: Overflow'
flash_step "seq: a further tick restarts it"  1501 "$CHECK 3/4: Rendering"
flash_step "seq: the new window holds"        1505 "$CHECK 3/4: Rendering"
flash_step "seq: and then settles again"      1506 "$ARROW 4/4: Overflow"

# Prose below the checklist changes the file but not what is being said, so it
# must not restart anything. This is where mtime would have been wrong.
printf '\n## Notes\n\nSomething discovered while working.\n' >> "$flash_dir/PLAN.md"
flash_step "seq: prose edit changes nothing"  1507 "$ARROW 4/4: Overflow"

# Marking the pending phase in progress leaves flash mode altogether, so it
# renders immediately with no glyph and no window to wait out.
flash_plan '- [x] Phase 1: Scaffold
- [x] Phase 2: Extraction
- [x] Phase 3: Rendering
- [/] Phase 4: Overflow'
flash_step "seq: a [/] cancels the pair"      1508 "4/4: Overflow"

# Unticking goes backwards cleanly: phase 3 pending again, phase 2 the last
# finished, and a fresh window on that pair.
flash_plan "$base"
flash_step "seq: unticking acknowledges again" 1509 "$CHECK 2/4: Extraction"

# A timestamp from the future gives a negative age. Treating that as a reset is
# what keeps a clock that moved backwards from freezing the pair.
flash_step "seq: a backwards clock resets"    900  "$CHECK 2/4: Extraction"

# No state file at all, which is every first render of a session and every render
# after $TMPDIR is cleaned.
rm -f "$flash_state"
flash_step "seq: a missing state file"        1509 "$CHECK 2/4: Extraction"

# A state file holding something this script never wrote.
printf 'garbage\n' > "$flash_state"
flash_step "seq: an unreadable state file"    1509 "$CHECK 2/4: Extraction"

# A state file that cannot be written at all. No clock can be kept, so this has
# to settle on the pending phase: standing at age zero instead would acknowledge
# the finished phase on every render for the rest of the session.
flash_state="$fixtures/no-such-directory/state"
flash_step "seq: an unwritable state file"    1509 "$ARROW 3/4: Rendering"

# ── The overflow ladder ──────────────────────────────────────────────────────
#
# What each rung sheds, and in what order, is the whole contract of the narrow
# case. It is asserted by sweeping widths rather than by pinning a rendering at
# some fixed width, because the fixture lives under mktemp and its path length is
# not the same on two machines, so neither is the width at which a given rung
# fires.
#
# Three things are checked across the sweep: the line is exactly COLUMNS - margin
# wide at every width down to the floor, nothing that has been shed ever comes
# back, and the widths at which things vanish run in the ladder's own order.
#
# The sweep renders once per column, so the ANSI stripping and the character
# counting are batched into a single python pass at the end rather than costing
# two more processes per width.
ladder_model="Opus 5"
ladder_pct="33%"
ladder_payload='{"cwd":"'"$repo"'","model":{"display_name":"'"$ladder_model"'"},"effort":{"level":"xhigh"},"context_window":{"total_input_tokens":8200,"used_percentage":33}}'
ladder_keys="cwd_full title cwd_any bar phase_num effort tokens branch"

# The floor is the last rung: the model and the percentage, two columns apart.
# Below it there is nothing left to shed and the fallback takes over.
ladder_floor=$((${#ladder_model} + 2 + ${#ladder_pct} + margin))

ladder_present() { # key, plain line -> 0 when the key is still on the line
  case "$1" in
    cwd_full)   case "$2" in *"$repo"*)   return 0 ;; esac ;;
    cwd_any)    case "$2" in *repo*)      return 0 ;; esac ;;
    title)      case "$2" in *Rendering*) return 0 ;; esac ;;
    phase_num)  case "$2" in *1/2*)       return 0 ;; esac ;;
    bar)        case "$2" in *"$BLOCK"*)  return 0 ;; esac ;;
    effort)     case "$2" in *xhigh*)     return 0 ;; esac ;;
    tokens)     case "$2" in *8.2k*)      return 0 ;; esac ;;
    branch)     case "$2" in *main*)      return 0 ;; esac ;;
    pct)        case "$2" in *"$ladder_pct"*) return 0 ;; esac ;;
  esac
  return 1
}

case_ladder() {
  local nat w plain key g prev bad="" seen_div=0
  local raw="$fixtures/ladder-raw" flat="$fixtures/ladder-flat"

  # Natural content width: with COLUMNS unset there is no budget, so nothing is
  # shed and nothing is padded.
  nat="$(printf '%s' "$ladder_payload" | env -u COLUMNS bash "$script" | strip | cols)"

  : > "$raw"
  w=$((nat + margin))
  while [ "$w" -ge "$ladder_floor" ]; do
    printf '%s\t%s\n' "$w" "$(render "$w" "$ladder_payload")" >> "$raw"
    w=$((w - 1))
  done

  # One pass: strip the colour, check the width, hand back the plain lines.
  MARGIN="$margin" python3 - "$raw" "$flat" <<'PY' || bad="width drift, see above"
import os, re, sys
margin = int(os.environ["MARGIN"])
ansi = re.compile(r"\x1b\[[0-9;]*m")
bad = 0
with open(sys.argv[1], encoding="utf-8") as src, open(sys.argv[2], "w", encoding="utf-8") as dst:
    for line in src:
        w, _, rest = line.rstrip("\n").partition("\t")
        plain = ansi.sub("", rest)
        want = int(w) - margin
        if len(plain) != want:
            print("FAIL  ladder width %s: got %d cols, want %d" % (w, len(plain), want), file=sys.stderr)
            print("      [%s]" % plain, file=sys.stderr)
            bad = 1
        dst.write("%s\t%s\n" % (w, plain))
sys.exit(bad)
PY

  for key in $ladder_keys pct; do eval "gone_$key=0"; done
  while IFS=$'\t' read -r w plain; do
    [ -n "$bad" ] && break
    for key in $ladder_keys pct; do
      eval "g=\$gone_$key"
      if ladder_present "$key" "$plain"; then
        [ "$g" -eq 0 ] || { bad="$key came back at width $w"; break; }
      else
        [ "$g" -ne 0 ] || eval "gone_$key=$w"
        # The bar does not simply vanish. It becomes a separator in the
        # percentage's colour, and that separator goes when the token count does.
        if [ "$key" = bar ]; then
          case "$plain" in *"8.2k | $ladder_pct"*) seen_div=1 ;; esac
        fi
      fi
    done
    [ "$check" -eq 0 ] && printf '%3s  %s\n' "$w" "$plain"
  done < "$flat"

  if [ "$check" -eq 0 ]; then return; fi

  prev=999999
  for key in $ladder_keys; do
    [ -n "$bad" ] && break
    eval "g=\$gone_$key"
    [ "$g" -ne 0 ]      || bad="$key never shed, down to width $ladder_floor"
    [ "$g" -le "$prev" ] || bad="$key shed before the rung above it"
    prev="$g"
  done
  eval "g=\$gone_pct"
  [ -n "$bad" ] || [ "$g" -eq 0 ] || bad="the percentage was shed at width $g"
  [ -n "$bad" ] || [ "$seen_div" -eq 1 ] || bad="the bar never became a separator"

  if [ -z "$bad" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  %-34s %s\n' "ladder" "$bad" >&2
  fi
}

[ "$check" -eq 0 ] && echo && echo "── overflow ladder ──"
case_ladder

if [ "$check" -eq 1 ]; then
  echo "── same matrix under LC_ALL=C ──"
  gitfull='{"cwd":"'"$repo"'","model":{"display_name":"DeepSeek V4 Pro"},"effort":{"level":"xhigh"},"context_window":{"total_input_tokens":142347,"used_percentage":71}}'
  for width in 60 90 160 200 240; do
    for name in gitfull payload_check payload_arrow; do
      eval "body=\$$name"
      out="$(printf '%s' "$body" | env COLUMNS="$width" LC_ALL=C LANG=C bash "$script" | strip | cols)"
      want=$((width - margin))
      if [ "$out" -eq "$want" ]; then
        pass=$((pass + 1))
      else
        fail=$((fail + 1))
        printf 'FAIL  LC_ALL=C %s width %s: got %s cols, want %s\n' "$name" "$width" "$out" "$want" >&2
      fi
    done
  done
  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ] || exit 1
fi
