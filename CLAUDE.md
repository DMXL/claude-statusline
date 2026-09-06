# claude-statusline

A `bash` status line for Claude Code. Read `README.md` first for the layout and the install wiring, `docs/payload-contract.md` for what the harness hands the script, and `docs/design.md` for why the visual choices are what they are.

## What this project is not

It is not a Node or TypeScript project, which departs from the DMXL stack default in `../CLAUDE.md` on purpose. The command runs once a second for the whole session, so interpreter startup is the dominant cost and `bash` plus one `jq` is the cheapest thing that can do the job. Do not port it to Node without first measuring both, and record the numbers here if you do.

There is no plan doc checked in either. The DMXL convention in `../CLAUDE.md` asks for one at `docs/plan.md`; this project deliberately does without, so do not recreate it. The phase parser is covered by fixtures in `test/render-cases.sh` rather than by a plan file living here, and the Phase 0 to 4 roadmap as it stood at publication is still in history: `git show 7060a17:docs/plan.md`.

There is no build step. `statusline-command.sh` is the source and the artifact. If a future phase introduces one, the generated file must not be the file anyone edits.

## Working on the script

Test before claiming anything works:

```zsh
./test/render-cases.sh --check
```

Rendering by hand is not enough. Three things have broken silently in this script before, and all three are invisible to the eye:

1. **Width drift.** The right half is aligned by padding to `$COLUMNS`, so any segment whose printed width differs from its measured width pushes the line off. Every segment is appended twice, once with colour and once plain, and the plain copy is what gets measured.
2. **Glyph accounting.** A Nerd Font glyph and a block character are one column but three bytes, and `${#var}` only agrees with that under a UTF-8 locale. Glyphs stay out of the `*_plain` strings and are counted in `extra_cols` instead. Never put one in a measured string, and never slice one with `${str:0:n}`, which counts bytes.
3. **Silent failure.** A non-zero exit, a spawn failure or a timeout makes the harness keep the previous text with no error shown anywhere but the debug log. A broken script looks like a frozen one, so the script must never `set -e` and must degrade to rendering something.

## Performance

The command runs at 1 Hz for the session's whole life, so per-render cost is a real constraint rather than a theoretical one.

- One `jq` pass reads every field. Do not add a second.
- `git` is pinned to `/opt/homebrew/bin/git`. The `git` on PATH on this machine is a corporate auth wrapper that costs about 390ms a call against 45ms for the real binary. Three calls a render made it the most expensive thing here by an order of magnitude.
- The plan doc is parsed in a single `awk` pass.

Any new segment should cost no process at all if it can be read from the payload, which almost everything can. Check `docs/payload-contract.md` before shelling out to anything.

## Conventions

- Colours are constants in the `C_*` block at the top. Do not inline a colour in the render code.
- Basic ANSI (30 to 37) follows the terminal's colour scheme; every `38;5;N` is a fixed xterm value that does not. The location group is basic on purpose, the rest is pinned.
- Nerd Font glyphs are written by codepoint in a comment next to their constant, because a bare glyph in a diff or a paste is easy to lose. This has already happened once: both icons were silently written as empty strings and the width maths went with them.

## Local references

Neither path below is in the repo, so both are dead ends for anyone reading this on GitHub. They are the two places the design decisions here were actually worked out.

- `~/Documents/Claude/Notes/claude/claude-07-statusline.md`, deep research on the harness contract, verified against the installed binary. `docs/payload-contract.md` is the summary of it that matters to this script.
- `~/Work/DMXL/CLAUDE.md` under "The plan doc", the convention the phase segment parses. Change one and the other has to follow.
