# Design

Why the bar looks the way it does. The harness facts behind these choices are in [payload-contract.md](payload-contract.md).

## Layout

```
{where} | {what answers} | {what is worked}                    {usage}
~/Work/DMXL/dmon-studio-com  main | DeepSeek V4 Pro  xhigh | 2/5: Custom SVG wordmark    142.3k ██████ 71%
```

Left is pushed left, usage is pushed right, and the gap between them is whatever is left over. Groups are separated by a grey pipe rather than by icons or spacing alone, because at this density colour was not enough on its own to show where one thing ended and the next began. A group that has nothing in it is skipped along with its divider, so there are never dangling pipes.

## Icons

Only where a glyph says something a colour cannot:

| Glyph | Codepoint | Segment | Says |
|---|---|---|---|
|  | `U+F126` | branch | this is a branch |
|  | `U+F0E7` | effort | this is effort |
| ✓ | `U+2713` | phase | this phase is finished |
| → | `U+2192` | phase | this phase has not started |

`U+F126` is deliberately the same glyph `POWERLEVEL9K_VCS_BRANCH_ICON` renders in the prompt two lines below, so the bar and the prompt agree. The directory, the token count and the percentage are identified by position and format, so a glyph there would be decoration. The model had an icon briefly and lost it once the dividers made it redundant.

The two on the phase are a later addition and do different work from the first two. They are not labels, they are the segment's state: a number with no glyph is a phase in flight, with a check is one just finished, with an arrow is one not yet started. A word would have said the same and cost five to seven columns; the glyph costs one and leaves the fraction on the line, which the [overflow ladder](#overflow) then has something to collapse to.

They are also plain Unicode rather than Nerd Font private use, unlike the first two. The branch and effort icons are decoration and degrade to a missing glyph box on an unpatched font; these two carry meaning, so they come from a range an ordinary monospace font already has. The first two require a Nerd Font. This machine runs MesloLGS NF in iTerm2, where every glyph is single width by design, which the width arithmetic depends on.

All four stay out of the measured copy of their cell and are counted in that cell's own `extra_cols` instead, because each is one column but three bytes and `${#var}` only agrees with that under a UTF-8 locale.

## Palette

Every colour is a `C_*` constant at the top of the script. Two rules govern the choices.

**Basic ANSI versus 256.** Basic ANSI (30 to 37) is remapped by the terminal's colour scheme and so follows a theme change; every `38;5;N` is a fixed xterm value that does not. The location group is basic on purpose, the rest is pinned. The status line has no way to detect the terminal's theme: the payload carries no such field and `settings.json` says `"theme": "auto"`, so the only alternatives would be shelling out to `defaults read -g AppleInterfaceStyle` once a second, or making everything basic ANSI and losing the finer hues.

**Nothing warm next to anything warm.** The original bar had the model in dim blue and the phase title in dim magenta, which read as one colour at a glance. Categories now separate cleanly.

| Constant | Value | Notes |
|---|---|---|
| `C_DIR` | 36 | basic cyan |
| `C_BRANCH` | 32 | basic green |
| `C_PHASE` | 35 | basic magenta |
| `C_DIVIDER` | 240 | grey pipe |
| `C_MODEL` | 250 | light grey |
| `C_PHASE_TITLE` | 141 | light purple, a shade up from the phase number. 183 was tried and reads as pink |

The phase glyphs take `C_PHASE` along with the number rather than a colour of their own. A green check was the obvious first try and is wrong twice over: green is already the low end of the usage scale, and colouring the glyph would make the phase the one group on the line whose colour means something other than which group it belongs to.
| `C_TOKENS` | 245 | grey |
| `C_BAR_EMPTY` | 239 | a shade below the divider, so the track recedes |

Only two values were taken from the p10k config: 76 (`VCS_CLEAN_FOREGROUND`) and 178 (`VCS_MODIFIED_FOREGROUND`). The rest are ordinary xterm-256 picks.

## Effort

Colour coded rather than merely printed, because the level is the thing worth spotting and the word is nearly always the same.

| Level | Constant | Colour |
|---|---|---|
| `max` | `C_EFFORT_MAX` | red 196 |
| `high`, `xhigh` | `C_EFFORT_HIGH` | blue 75 |
| `medium` | `C_EFFORT_MEDIUM` | green 76 |
| `low`, `xlow` | `C_EFFORT_LOW` | orange 208 |
| anything else | `C_EFFORT_OTHER` | grey 245 |

## The usage bar

Six cells, driven by `used_percentage` so the fill and the colour point the same way.

| Used | Constant | Colour |
|---|---|---|
| under 50% | `C_USE_LOW` | green 76 |
| 50 to 69% | `C_USE_MID` | yellow 178 |
| 70 to 89% | `C_USE_HIGH` | orange 208 |
| 90% and over | `C_USE_FULL` | red 196 |

Three decisions worth keeping:

- **Six cells is coarse on purpose.** Each is about 17%, so 44% and 55% both show three filled and the bar saturates around 92%. The colour carries the threshold and the fill carries rough magnitude; neither needs the other to be precise. `BAR_CELLS` is one constant if that trade stops being worth it.
- **The fill never shows empty while any context is in use**, so a fresh session reads one cell rather than none.
- **Both halves are the same solid block**, the empty half simply darker, so the bar reads as one object with a track. An earlier version drew the empty half as a shade character, which at six cells looked like texture rather than a track.

The token count beside it is window occupancy, not session spend. See the payload contract for why nothing better exists.

## Overflow

Before the ladder existed the script had no concept of not fitting. Once the padding arithmetic went negative it fell back to a two-space join and emitted whatever it had, and the harness truncated the result. That truncation cuts the tail, so the order in which things died was purely positional: the percentage first, then the bar, then the token count. The right half exists to show how much room is left, and it was the first thing to go.

The line now owns its own width. Every printable piece is a cell carrying its own column count, groups are recomposed from whatever is still alive, and a ladder sheds cells one rung at a time until the line fits.

| Rung | Sheds | Leaves |
|---|---|---|
| 1 | the leading path | the last folder |
| 2 | the phase title | the glyph and `3/5` |
| 3 | the last folder | nothing of the directory |
| 4 | the six bar cells | a separator in the percentage's colour |
| 5 | the glyph and `3/5` | nothing of the phase |
| 6 | effort | |
| 7 | the token count | and with it the separator from rung 4 |
| 8 | branch | |

Three things this ordering is built on:

**The coarse form of a thing outlives its detail.** The directory gives up its path before it gives up its name, and the phase gives up its title before it gives up its number. Two rungs of graceful degradation for each, rather than a single cliff. The phase glyph rides along with the number rather than with the title, because one column buying the difference between a phase finished and a phase pending is the best trade on the line.

**The bar degrades into punctuation rather than vanishing.** `122.8k | 78%` still reads as one object at a glance, where `122.8k 78%` reads as two numbers that happen to be adjacent. The separator takes the percentage's colour so the threshold is still legible at a glance, and because it is only a separator it disappears on its own once the token count goes.

**Model and percentage are the floor.** Everything else on the line is recoverable from somewhere else on screen or from a moment's thought. Which model is answering, and how close the window is to full, are not.

A separator only exists to divide two things, so it is skipped whenever it would land at either end of what survives in its group. That is what keeps a shed segment from leaving a dangling pipe behind, and it applies to the group pipes and to the degraded bar alike.

Two constraints the rungs respect. Nothing spawns a process, since this runs at 1 Hz for the whole session: the whole ladder is bash arithmetic over the cell arrays, and it costs about 3ms against a 59ms render dominated by the `jq` and `git` calls. Nothing slices a string either, because `${str:0:n}` counts bytes and would split a glyph, so every rung either drops a cell outright or swaps it for a shorter whole token.

One consequence worth knowing: the rung a line sits on can change without the terminal resizing, because the content moves too. A token count crossing from `9.9k` to `10.1k` is one column wider and can be enough to push a line onto the next rung.

## What was dropped

**The clock.** It only advanced when something else did, which made it quietly wrong, and `refreshInterval: 1` existed largely to keep it honest. A bar answers "how much room is left" faster than a timestamp answers anything.

**`ctx:NN%` as text.** The label was doing the work the bar now does.

## Wiring: symlink versus direct path

Claude Code invokes whatever `settings.json` names. Two options:

1. **Direct path.** `"command": "bash ~/Work/DMXL/claude-statusline/statusline-command.sh"`. One less indirection and nothing to clobber.
2. **Symlink.** `~/.claude/statusline-command.sh` points into the repo, and `settings.json` is untouched.

This machine uses the symlink, but the direct path is the better default. The symlink's specific risk is that a writer which replaces a file rather than editing it in place will replace the symlink with a regular file, silently detaching the live script from the repo. Nothing warns you; the bar keeps working, and the repo simply stops being the thing that runs. Check with `ls -l ~/.claude/statusline-command.sh` if edits ever stop taking effect.

Both options share one failure mode: if the repo directory goes away, `bash` exits non-zero, the harness keeps the previous text, and nothing says why.
