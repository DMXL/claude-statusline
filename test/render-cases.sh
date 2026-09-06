#!/usr/bin/env bash
# Render matrix for statusline-command.sh.
#   ./test/render-cases.sh          render every case for eyeballing
#   ./test/render-cases.sh --check  assert widths and phase parsing, exit non-zero on drift
#
# The width assertion is the point. Every segment is appended twice, once with
# colour and once plain, and only the plain copy is measured, so any new segment
# whose printed width differs from its measured width silently pushes the line
# off. Glyphs are one column but three bytes, so the check runs under LC_ALL=C
# as well to catch a glyph that leaked into a measured string.

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

pass=0
fail=0

strip() { sed 's/\x1b\[[0-9;]*m//g'; }
cols()  { python3 -c 'import sys;print(len(sys.stdin.read()))'; }

render() { printf '%s' "$2" | env COLUMNS="$1" bash "$script"; }

# name, columns, payload, [loose]
#
# Strict by default: the line must be exactly COLUMNS - margin wide. "loose" is
# only for cases whose content cannot fit, where the script deliberately falls
# back to a two-space join. Do not relax a case to loose to make it pass; an
# over-long line is exactly what an under-counted glyph produces.
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
  elif [ "$mode" = "loose" ]; then
    [ "$n" -gt "$want" ] && ok=1           # content overflows, fallback expected
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

# name, expected "Phase N/M: title" (or empty), plan body
case_phase() {
  local name="$1" want="$2" body="$3"
  local dir="$fixtures/$name"
  mkdir -p "$dir"
  printf '%s' "$body" > "$dir/PLAN.md"
  local got
  # Pull the phase group out by pattern rather than by position, so a missing
  # group yields an empty string instead of whatever segment sat next to it.
  got="$(render 200 "{\"cwd\":\"$dir\",\"model\":{\"display_name\":\"M\"}}" | strip \
        | grep -oE 'Phase [0-9]+/[0-9]+(: [^|]*)?' | head -1 | sed 's/[[:space:]]*$//')"
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
case_render "full narrow"        96 "$full" loose
case_render "full wide"         240 "$full"
case_render "no effort"         120 '{"cwd":"'"$D"'","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":8200,"used_percentage":12}}'
case_render "no model"          120 '{"cwd":"'"$D"'","context_window":{"total_input_tokens":8200,"used_percentage":12}}'
case_render "no git no plan"    120 '{"cwd":"/tmp","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":8200,"used_percentage":12}}'
case_render "no usage yet"      120 '{"cwd":"/tmp","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":0,"used_percentage":null}}'
case_render "million tokens"    120 '{"cwd":"/tmp","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":1420000,"used_percentage":100}}'
case_render "git branch"        180 '{"cwd":"'"$repo"'","model":{"display_name":"Opus 5"},"effort":{"level":"high"},"context_window":{"total_input_tokens":8200,"used_percentage":33}}'
case_render "git branch narrow"  96 '{"cwd":"'"$repo"'","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":8200,"used_percentage":33}}' loose
case_render "git subdir"        180 '{"cwd":"'"$repo"'/docs","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":8200,"used_percentage":33}}'
case_render "empty payload"     120 '{}'
case_render "malformed stdin"   120 'not json'

[ "$check" -eq 0 ] && echo && echo "── effort levels ──"
for e in low medium high xhigh max bogus; do
  case_render "effort $e" 100 '{"cwd":"/tmp","model":{"display_name":"Opus 5"},"effort":{"level":"'"$e"'"},"context_window":{"total_input_tokens":8200,"used_percentage":40}}'
done

[ "$check" -eq 0 ] && echo && echo "── usage thresholds ──"
for u in 0 1 12 49 50 69 70 89 90 100; do
  case_render "used $u%" 100 '{"cwd":"/tmp","model":{"display_name":"Opus 5"},"context_window":{"total_input_tokens":142347,"used_percentage":'"$u"'}}'
done

[ "$check" -eq 0 ] && echo && echo "── phase parsing ──"
case_phase "zero-indexed"   "Phase 3/5: Rendering" '- [x] Phase 0: Scaffold
- [x] Phase 1: Extract
- [x] Phase 2: Parse
- [ ] Phase 3: Rendering
  - [ ] indented step
- [ ] Phase 4: Ship
- [ ] Phase 5: Polish
'
case_phase "one-indexed"    "Phase 2/3: Rendering" '- [x] Phase 1: Scaffold
- [/] Phase 2: Rendering
- [ ] Phase 3: Ship
'
case_phase "in-progress-wins" "Phase 3/4: Rendering" '- [x] Phase 1: Scaffold
- [ ] Phase 2: Deferred
- [~] Phase 3: Rendering
- [ ] Phase 4: Ship
'
case_phase "reordered"      "Phase 3/5: D" '- [x] Phase 0: A
- [x] Phase 1: B
- [x] Phase 2: C
- [/] Phase 3: D
- [ ] Phase 5: E
- [ ] Phase 4: F
'
case_phase "cancelled"      "Phase 3/3: Rendering" '- [x] Phase 1: A
- [-] Phase 2: Dropped
- [ ] Phase 3: Rendering
'
case_phase "all done"       "Phase 5/5" '- [x] Phase 0: A
- [x] Phase 1: B
- [x] Phase 5: C
'
case_phase "unlabelled"     "Phase 2/3: Rendering" '- [x] Scaffold
- [/] Rendering
- [ ] Ship
'
case_phase "long title"     "Phase 2/2" '- [x] Phase 1: A
- [/] Phase 2: A title that is definitely longer than thirty two characters
'
case_phase "no checkboxes"  "" '# just a document

Nothing to parse here.
'

if [ "$check" -eq 1 ]; then
  echo "── same matrix under LC_ALL=C ──"
  gitfull='{"cwd":"'"$repo"'","model":{"display_name":"DeepSeek V4 Pro"},"effort":{"level":"xhigh"},"context_window":{"total_input_tokens":142347,"used_percentage":71}}'
  for width in 160 200 240; do
    out="$(printf '%s' "$gitfull" | env COLUMNS="$width" LC_ALL=C LANG=C bash "$script" | strip | cols)"
    want=$((width - margin))
    if [ "$out" -eq "$want" ]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      printf 'FAIL  LC_ALL=C width %s: got %s cols, want %s\n' "$width" "$out" "$want" >&2
    fi
  done
  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ] || exit 1
fi
