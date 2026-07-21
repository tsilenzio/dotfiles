# ~/.claude/CHANGES.md

Location-scoped changelog for the home environment. Records shifts that matter across
projects: directories that moved, conventions that were renamed, tools that changed shape.
`CLAUDE.md` points here. When an expected path is missing or the environment seems
rearranged, read this before improvising, because a vanished path is often a recorded move
rather than a mistake to route around.

Entries append at the bottom, newest last, and are not edited once written.

## 2026-07-21 The docs standard and its instance directory were renamed to engrata

The documentation standard, its repository, and the per-project instance directory were
all renamed on this date. Literal old and new names:

- Standard name: `docs-system` became `engrata`.
- Standard repository: `~/Code/misc/docs/docs-system` became `~/Code/misc/docs/engrata`.
- Instance directory: `.docs` became `.engrata`.
- Citation form inside an adopting project: `docs-system/NNNN` became `engrata/NNNN`.

Both generations are supported during the transition. Most projects in the fleet still hold
a `.docs` directory, because the rename reached the standard first. Where `.engrata` exists
it is the working layer, and where it is absent a legacy `.docs` is the same thing. Old
names surviving in frozen records, session notes, and commit messages are history and stay
as written.

The machine-global gitignore (`~/.gitignore`, sourced from
`config/git/gitignore` in dotfiles) carries both a `.engrata` line and a `.docs` line for
the duration of the transition, so neither generation of the instance directory appears in
a parent repo's `git status`.

Recovery gap during the transition window: a dotfiles-only restore before this commit
lacked the `.engrata` guard, so projects renamed to `.engrata` before it relied on a
hand-added `.engrata` line in the deployed gitignore or on repo-local guards to stay
ignored. This commit folds the guard into the managed source, closing the gap for restores
after it.

## 2026-07-21 Possible move of the code root from misc to workspace

The code root `/Volumes/Code/misc/` may migrate to `/Volumes/Code/workspace/`. The shape of
the change is not yet decided: `~/Code` may be repointed, or a new `~/workspace` symlink may
appear alongside it. All of this is TBD as of this entry.

If a `/Volumes/Code/misc/...` path has vanished, check whether this move happened before
treating it as missing. Absolute paths into `misc/` appear in rules files and in engrata
docs across the fleet, including this environment's pointer to the engrata standard at
`~/Code/misc/docs/engrata`. When the move lands, update any engrata docs that cite a
`misc/` path.
