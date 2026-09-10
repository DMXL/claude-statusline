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

Rendering by hand is not enough. Five things have broken silently in this script before, and every one of them is invisible to the eye:

1. **Width drift.** The right half is aligned by padding to `$COLUMNS`, so any cell whose printed width differs from its measured width pushes the line off. Every cell is built twice, once with colour and once plain, and carries its own count of the columns the plain copy does not hold. That count belongs on the cell rather than in one shared accumulator, because the overflow ladder has to know what a given cell gives back when it is shed.
2. **Glyph accounting.** A Nerd Font glyph and a block character are one column but three bytes, and `${#var}` only agrees with that under a UTF-8 locale. Glyphs stay out of the `*_plain` strings and are counted in `extra_cols` instead. Never put one in a measured string, and never slice one with `${str:0:n}`, which counts bytes.
3. **Silent failure.** A non-zero exit, a spawn failure or a timeout makes the harness keep the previous text with no error shown anywhere but the debug log. A broken script looks like a frozen one, so the script must never `set -e` and must degrade to rendering something.
4. **Time dependence.** The phase group has two forms and picks between them from a clock, so a render is no longer a pure function of the payload. Every test therefore runs on a frozen clock (`CLAUDE_STATUSLINE_NOW`) against a per-case state file (`CLAUDE_STATUSLINE_STATE`), and anything new that reads a clock has to be injectable the same way or the suite starts failing one run in ten.
5. **Payload trust.** Claude Code reads its whole context gauge off the `usage` object on the last assistant message in the transcript, so a message carrying an all-zero usage reaches the payload as `total_input_tokens: 0` with a flat `used_percentage: 0`, and stays there until a later message corrects it. A translating proxy emits that shape for any turn whose upstream reported no usage, which is how the bar came to empty and refill mid session on the OpenAI bridge. The script now treats a numeric percentage with zero tokens as no reading and holds the last one instead. Nothing else in the payload is second guessed, and nothing else should be without evidence of the same kind.

Two things now depend on what the last render saw, so a single render proves nothing about either: the two-form phase group, and the context reading, which stands in the last believable figure when the harness hands over a zeroed one. Both are asserted as sequences, under `── flash clock ──` and `── context cache ──`.

The phase group's trap is the sharper of the two. The clock lives in a fingerprint of the displayed state plus an epoch, kept in one line in `$TMPDIR` keyed by session id, and the reason it is a fingerprint rather than the plan file's mtime is that an edit to prose below the checklist must not restart the acknowledgement. That property, and every other mid-flash edit, is asserted as a sequence rather than as isolated cases. Change the fingerprint's contents and those sequences are what tells you what you broke.

The state file now carries four fields on its one line: the fingerprint, the epoch, and the cached token count and percentage. Adding a fifth means changing the single `read`, the single `printf` and the guard that drops a cache whose numbers are not plain integers.

The overflow ladder fails the same silent way: a rung that gives back the wrong number of columns leaves the line long, and the harness eats its tail. `--check` sweeps every column width from the natural width down to the floor, so a broken rung fails there rather than in whatever terminal someone happens to resize. Changing what a rung sheds means changing the `for rung in ...` list in the script and the matching order in `ladder_keys` in the test.

## Performance

The command runs at 1 Hz for the session's whole life, so per-render cost is a real constraint rather than a theoretical one.

- One `jq` pass reads every field. Do not add a second.
- `git` is pinned to `/opt/homebrew/bin/git`. The `git` on PATH on this machine is a corporate auth wrapper that costs about 390ms a call against 45ms for the real binary. Three calls a render made it the most expensive thing here by an order of magnitude.
- The plan doc is parsed in a single `awk` pass, which now yields a mode and two candidate phases rather than one phase, so the two-form logic needs no second look at the file.
- The acknowledgement clock reads and writes one small file, both with bash builtins, and spawns nothing. Measured at 29ms a render against 28ms before it, which is inside the noise. The context cache shares that file and that single write, rather than opening one of its own: the write is skipped entirely on a render where nothing in it moved, which at 1 Hz is most of them.

Any new segment should cost no process at all if it can be read from the payload, which almost everything can. Check `docs/payload-contract.md` before shelling out to anything.

The overflow ladder recomposes the whole line once per rung, which sounds expensive and is not: it is bash arithmetic over the cell arrays and measures at about 3ms on a 59ms render, where the `jq` and `git` spawns are the rest. Keep it that way, and in particular keep every rung to whole tokens, since anything that needs to measure a substring wants a process.

## Conventions

- Colours are constants in the `C_*` block at the top. Do not inline a colour in the render code.
- Basic ANSI (30 to 37) follows the terminal's colour scheme; every `38;5;N` is a fixed xterm value that does not. The location group is basic on purpose, the rest is pinned.
- Nerd Font glyphs are written by codepoint in a comment next to their constant, because a bare glyph in a diff or a paste is easy to lose. This has already happened once: both icons were silently written as empty strings and the width maths went with them.

## Local references

Neither path below is in the repo, so both are dead ends for anyone reading this on GitHub. They are the two places the design decisions here were actually worked out.

- `~/Documents/Claude/Notes/claude/claude-07-statusline.md`, deep research on the harness contract, verified against the installed binary. `docs/payload-contract.md` is the summary of it that matters to this script.
- `~/Work/DMXL/CLAUDE.md` under "The plan doc", the convention the phase segment parses. Change one and the other has to follow.
