# Design

Why the bar looks the way it does. The harness facts behind these choices are in [payload-contract.md](payload-contract.md).

## Layout

```
{where} | {what answers} | {what is worked}                    {usage}
~/Work/DMXL/dmon-studio-com  main | DeepSeek V4 Pro  xhigh | Phase 2/5: Custom SVG wordmark    142.3k ██████ 71%
```

Left is pushed left, usage is pushed right, and the gap between them is whatever is left over. Groups are separated by a grey pipe rather than by icons or spacing alone, because at this density colour was not enough on its own to show where one thing ended and the next began. A group that has nothing in it is skipped along with its divider, so there are never dangling pipes.

## Icons

Only two, on the segments where a glyph says something a colour cannot:

| Glyph | Codepoint | Segment |
|---|---|---|
|  | `U+F126` | branch |
|  | `U+F0E7` | effort |

`U+F126` is deliberately the same glyph `POWERLEVEL9K_VCS_BRANCH_ICON` renders in the prompt two lines below, so the bar and the prompt agree. The directory, the token count and the percentage are identified by position and format, so a glyph there would be decoration. Model and phase had icons briefly and lost them once the dividers made them redundant.

Requires a Nerd Font. This machine runs MesloLGS NF in iTerm2, where every glyph is single width by design, which the width arithmetic depends on.

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

## What was dropped

**The clock.** It only advanced when something else did, which made it quietly wrong, and `refreshInterval: 1` existed largely to keep it honest. A bar answers "how much room is left" faster than a timestamp answers anything.

**`ctx:NN%` as text.** The label was doing the work the bar now does.

## Wiring: symlink versus direct path

Claude Code invokes whatever `settings.json` names. Two options:

1. **Direct path.** `"command": "bash ~/Work/DMXL/claude-statusline/statusline-command.sh"`. One less indirection and nothing to clobber.
2. **Symlink.** `~/.claude/statusline-command.sh` points into the repo, and `settings.json` is untouched.

This machine uses the symlink, but the direct path is the better default. The symlink's specific risk is that a writer which replaces a file rather than editing it in place will replace the symlink with a regular file, silently detaching the live script from the repo. Nothing warns you; the bar keeps working, and the repo simply stops being the thing that runs. Check with `ls -l ~/.claude/statusline-command.sh` if edits ever stop taking effect.

Both options share one failure mode: if the repo directory goes away, `bash` exits non-zero, the harness keeps the previous text, and nothing says why.
