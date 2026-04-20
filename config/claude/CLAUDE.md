# CLAUDE.md

Shared context for any project I work on. A project-specific `CLAUDE.md` closer to the cwd adds to or overrides anything here.

## Before making changes

When I open a fresh session vaguely ("help me with this project"), read `CLAUDE.md`, check `git status` and recent commit history, and summarize the current state before doing anything. Don't edit a dirty repo without an explicit ask. I usually want to discuss first.

If the repo is clean and I've given you a clear task, go ahead. The "wait and discuss" rule is for the ambiguous starts.

When a request has multiple reasonable interpretations, state your interpretation before acting, or ask which one I meant. Don't silently pick one and proceed.

Before suggesting modifications to a file or proposing a fix, read the file. Don't guess at what the code looks like or assume what's there from the filename. Same goes for follow-the-imports work: if you need to understand how a function is used, read the call sites.

## Planning complex work

For multi-step work that touches several files or has real dependencies between steps, lay out the plan before executing rather than improvising as you go. For genuinely non-trivial changes, use plan mode (`ExitPlanMode` in Claude Code) so I can review before any code is written. Expect me to scrutinize both the plan and the resulting changes.

When you do plan, identify natural commit breakpoints rather than treating everything as one giant commit. Each breakpoint should leave the project in a working state, ideally one I'd be willing to push as its own commit.

## Sensitive files

Never stage or commit `.env`, `.env.*`, `*.pem`, `*.key`, credentials files, API keys, certificates, or anything else that looks like a secret. If a sensitive-looking file shows up in `git status` while you're preparing a commit, stop and surface it before continuing.

## Commits and branches

Use conventional commit prefixes (`feat`, `fix`, `chore`, `refactor`, `docs`, `ci`, `test`, `perf`, `build`, `style`, `revert`) unless I say otherwise. Branches follow `<type>/<short-description>` for the same reason.

Don't commit, push, or open a PR unless I've explicitly asked for it. Showing me the diff or running tests is fine. The actual git and `gh` actions are mine to authorize.

I use `gpg-touchid` (a GPG pinentry that requires Touch ID confirmation) to sign commits, so any commit you trigger will surface a Touch ID prompt I have to approve. If a commit fails because of GPG signing or pinentry rejection, it's almost always me deliberately blocking it rather than a tool failure. Don't debug it, don't work around it, and don't retry. Ask whether I meant to block the commit entirely or whether I wanted you to change something first.

Default to feature branches and PRs (via `gh pr create` for GitHub repos), even for solo projects. Most projects I work on have CI that enforces conventions on PRs.

When you need the current date or time (for a `Last Updated:` line in a doc, anywhere else), get it from `date` rather than guessing or pulling from earlier in the conversation.

### Commit message body

Commit messages summarize what changed as a whole, not itemize individual changes. Prefer a single subject line that captures everything. A commit that renames three functions and adds a call site is "refactor: renamed helpers and added geolocation check to registration flow," not four bullets. List related items inline: "docs: add Architecture section covering disposable LXC, per-container modules, hybrid access, and layered backups."

Skip the body when the subject line covers it, which should be most of the time. A body is for when a commit genuinely spans multiple unrelated areas that can't fit in one line. Even then, keep it to a few short bullets describing themes, not individual changes. Order by what matters most to a future reader. Trivial items (typo fixes, formatting, gitignore tweaks) can be tacked onto the subject line as an aside ("also fixed typos") or dropped entirely when there's more significant work in the same commit. If the commit is nothing but trivial changes, mention them normally.

## Pull requests

Before opening a PR, run all the project's checks locally (tests, linters, formatter, relevant manual smoke tests). For things genuinely untestable locally (PR-only CI workflows, deploy targets, anything that needs real credentials), it's fine to open the PR and rely on CI feedback, but call out which checks were skipped and why.

Default to squash merge via `gh pr merge --squash` unless I ask for a rebase merge. The squashed message should follow the same conventional-commit subject + bullet body shape as a regular commit.

PR bodies use a `## Summary` section followed by a `## Test plan` section. Summary is a short bulleted list describing the themes of the change, same as commit messages. A single-sentence summary is fine when the PR is focused enough. Test plan is a checklist with checkboxes pre-checked for anything verified locally and unchecked for things that need CI or manual verification. If the project has a `.github/PULL_REQUEST_TEMPLATE.md` (or any of the other names GitHub recognizes), use that as the starting structure. If it doesn't, prompt me once in a while to add one so the format gets enforced.

Prefer smaller, separated PRs over one big bundled PR when the changes are independent. I have a habit of making PRs too big, so help me catch myself when I'm doing it. When changes are tightly coupled (a refactor that enables a feature, a schema change that needs a code update), say so and ask whether to bundle them into one PR, stack them on a single branch, or split them into sequential PRs.

A note on stacking specifically. With squash merges, "stacking on one branch" is effectively the same as bundling into one PR, just with the intermediate commits visible during review before they collapse into a single commit on `main`. True branch-stacking (PR B targets PR A's branch instead of `main`) adds review complexity and rarely pays off when the squash will throw the intermediate state away anyway. The usual decision: separate PRs when changes are independent, one bundled PR when they're tightly coupled, and only true-stack when each step genuinely needs its own commit on `main`.

Don't force-push unless we're on a feature branch and there's a strong reason. Even then, ask first and explain why you're recommending it. Never force-push to `main`.

## Writing code

Code should look like a human wrote it, comments included. Before writing or modifying anything, look at how the rest of the project already does things and match it. Style, naming, import order, file layout, error handling patterns. If the project uses an idiom consistently, use that idiom even if you'd normally reach for something else. New code should fit in with whatever was there before instead of introducing a competing style.

Sometimes I'll point you at a reference project (like `~/Code/misc/learning/rust/personal-playground/wordify/` for Rust style) and ask you to match its style. Read it before writing code in that language. If a project's `CLAUDE.md` or `.docs/AGENTS.md` mentions a reference project, treat it the same way.

Files should end with a single trailing newline. POSIX text-file convention, and a lot of tooling expects it.

When you create temp files, scratch directories, or experimental output during a session, clean them up when you're done unless I've asked you to keep them around. The `trap 'rm -rf "$WORK_DIR"' EXIT` pattern is the right shape for shell scripts.

Don't create new documentation files (`README.md`, `TODO.md`, anything with extensive prose) unless I ask. Modifying existing docs at the project root is fine. Files inside `.docs/` follow their own rule below.

## Scope and reporting

Stick to what I asked. Don't refactor unrelated code, don't add features I didn't request, don't "improve" things I didn't mention, don't add error handling for cases that can't happen. If you notice something worth changing on the side, mention it but don't do it.

Don't auto-fix or remove `TODO`/`FIXME`/`XXX` comments in code you're touching unless I've asked, or unless resolving them is genuinely required for the change at hand. If a TODO looks like a quick win, surface it as a suggestion rather than acting on it.

The flip side: when I explicitly ask for your thoughts on an approach, speak up. If you see a better approach than mine, say so and explain why. If you spot a bug or logic issue in what I'm proposing, point it out before I commit to it. The "don't expand scope" rule is about unsolicited side quests, not about staying quiet when I'm asking for input.

On projects I own (owner: `me`), flag anti-patterns and non-idiomatic code unsolicited. If I'm doing something the wrong way for the language, the wrong way for the framework, or noticeably clumsier than the idiomatic approach, point it out. I'd rather learn the right pattern now than reinforce the wrong one. This applies whether the project is public or private. If it's public it doubles as portfolio polish, and if it's private I still want to know.

Don't apply this to projects owned by someone else, even when they're public. On forked PR contributions or open source work, follow the upstream project's conventions instead of imposing what I'd consider idiomatic. My own projects are the one place where unsolicited feedback on style and patterns is welcome.

When you say something is verified, working, or fixed, be specific about how you checked. "Ran `cargo test`, all 6 tests passed" is good. "This should work now" or "the change is complete" without saying how you verified is not. When you can't actually verify something (no credentials, the check only runs in CI, the test target isn't reachable from here), say so explicitly rather than implying it works.

## Comments

Comments are for things the code can't say on its own. If a reader can tell what a line does just by reading it, the comment is noise. Strip it before committing.

Keep comments for cases like:
- Workarounds someone would otherwise question (a sleep to dodge a race, a magic number from a vendor doc)
- Edge cases the code handles silently
- The why behind a non-obvious choice

Surviving comments should be tight. One line where one line will do. More detail only when it's actually warranted.

No em-dashes mid-sentence as a pause. If you reach for one, rewrite the sentence instead. The only place an em-dash is fine is as the bullet marker itself (in place of `-` or `*`), never inside the text of the bullet.

These same rules apply to markdown I'm adding to a project (`README.md`, `TODO.md`, files inside `.docs/`, anything else): concise by default, no em-dashes as pauses.

## The `.docs/` pattern

Many projects I work on use a `.docs/` directory for rules, specs, planning notes, and private session context (briefing/debriefing, persisted notes, local overrides to this file). Used across personal, employer, and open source projects where I want private notes that don't end up upstream. The conventions:

- `.docs/` is its own git repo (the directory contains a `.git/`). It is not tracked by the parent project's git history.
- `.docs/` is gitignored globally at `~/.gitignore` (line `.docs`), so it never appears in `git status` for the parent project.
- The parent project's `CLAUDE.md` is typically a symlink to `.docs/AGENTS.md` so Claude Code picks up the rules while they live in the nested repo.
- A project may also keep an `archived/` subdirectory inside `.docs/` for old planning docs that have been replaced.

What this means in practice:

- To commit doc changes, `cd .docs/` first. Committing from the parent repo will silently do nothing because `.docs/` is gitignored.
- The nested repo usually has no remote. Doc history stays local unless I set one up.
- Watch out for symlinks in both directions: a parent project's `CLAUDE.md` may actually be `.docs/AGENTS.md` through a symlink, and `.docs/` itself may eventually be a symlink to a centralized docs repo. Run `ls -l` on either before assuming you're editing the file you think you are.
- Don't modify files inside `.docs/` without asking first. If you notice docs are stale (significant changes since last update, or enough accumulated drift), suggest an update. Before making changes, list what you'd update and which files you'd touch so I can approve or trim the scope.
- When I ask you to create a new doc inside `.docs/`, include a date near the top. The pattern I use is a `Last Updated: YYYY-MM-DD` line in the file header, matching how the existing `SPEC.md` does it.

### Files inside `.docs/`

`.docs/` always contains `AGENTS.md`. Beyond that it will usually contain either a `SPEC.md` or an `ARCHITECTURE.md`, but almost never both. Default to `SPEC.md`, since it's the broader of the two and can include architecture as a section while also covering goals, features, behavior, and interface. Reach for `ARCHITECTURE.md` only when the doc is purely about how the code is organized and there's no behavior or interface worth spelling out.

When `.docs/` ends up with more than two markdown files (counting beyond `AGENTS.md` and the spec/architecture file), add a `README.md` inside `.docs/` that acts as an index. One short line per file explaining what it's for.

### Project metadata

A project's `CLAUDE.md` (or `.docs/README.md` if there is one) can include a metadata block at the top describing the project's context. This helps you apply rules at the right strictness level. Useful fields:

- **Reference project**: a path or name of an existing project whose style or conventions I want this one to follow. Multiple references can be listed in priority order, with the first being the strongest influence and each subsequent one a step below. If two references contradict each other on something specific, ask me which to follow.
- **Visibility**: `public` or `private`.
- **Owner**: `me`, `employer`, or `other` (forked repo, collaborator project I'm helping with, etc.).
- **Assistance level**: `hints`, `suggestions`, or `solutions`. Controls how much I want spelled out when I hit a problem. Default is `solutions` (give me the answer). The one exception: Rust projects I own default to `hints`, since I'm actively learning Rust.

Strictness comes from combining the two: a project is relaxed only when it's both `private` and owned by `me`. Anything else (public regardless of owner, or any visibility when the owner isn't me) gets the strict treatment, with the rules in this file followed closely. When the owner isn't me, the owning party's existing conventions take precedence over mine if there's a conflict, so check the project's existing files and patterns before assuming any rule from this file applies.

If a project has no metadata block, assume the worst case: public, not owned by me, strict.

If a metadata block is present, treat it as authoritative. Metadata reflects intent, not current state. I might set `public` for a repo that's currently private on GitHub but I plan to share, or `private` for one I'm pulling back. Follow the metadata, not the GitHub setting.

What each assistance level means:

- `hints`: don't give the answer. Nudge with leading questions, doc references, or pointers at where to look. Make me work it out.
- `suggestions`: describe the approach in plain language without writing the code. "You could use a `match` here with arms for `Some` and `None`," or "Implement the `From` trait for this conversion."
- `solutions`: give me the answer or code directly.

Don't escalate on your own. If `hints` aren't enough, I'll ask for `suggestions`. If `suggestions` aren't enough, I'll ask for `solutions`. Each new problem in a session starts at the project's default level. The exception is when I ask for a specific level on a one-off basis ("just give me the answer here").

#### Keeping metadata fresh

The metadata block is meant to evolve with the project. Two cases to watch for:

- If a metadata block exists but is missing one of the always-required fields (`owner`, `visibility`, `assistance`), ask me what the value should be rather than silently falling back to the worst-case default. Same for open-ended fields like `reference project` when the context suggests one ought to be set.
- If a project has no `CLAUDE.md` at the root and no `AGENTS.md` anywhere (root or `.docs/`), but the project has grown enough to warrant rules (it has a `.docs/SPEC.md` or `.docs/ARCHITECTURE.md`, or it's clearly past the toy stage), suggest creating one. The default placement is `.docs/AGENTS.md` with a symlink at the project root as `CLAUDE.md`. At minimum the new file should establish the metadata block so future sessions have something to anchor on.

Note on the symlink-to-`.docs/AGENTS.md` pattern: this only works for personal projects where you don't expect anyone else to clone the repo, since `.docs/` is gitignored and the symlink would be broken on a fresh clone. For projects intended to be shared with collaborators, create `CLAUDE.md` as a real committed file at the project root instead, with `.docs/AGENTS.md` serving as your private extended notes.

Related: if `git status` shows an LLM rules file being added or modified, and the file is a symlink whose target sits outside the repo or inside a gitignored directory (typically `.docs/`), ask whether the commit was intended. If yes, default to replacing the symlink with a real file containing the resolved content before committing. Only leave it as a symlink if I tell you there's a specific reason to keep it that way. Committing a broken symlink means anyone cloning the repo ends up with a rules file that fails to read, which defeats the point of committing it.

By "LLM rules file" I mean any of the standard project-instruction conventions used by AI coding tools:

- `CLAUDE.md` (Claude Code, the main one for me)
- `AGENTS.md` (OpenAI Codex, also adopted as a cross-tool convention)
- `GEMINI.md` (Gemini CLI)
- `.cursorrules` or files under `.cursor/rules/` (Cursor)
- `.windsurfrules` (Windsurf)
- `.github/copilot-instructions.md` (GitHub Copilot)
- any other well-known equivalent you recognize that I may have missed

`CLAUDE.md` is the one that matters most to me, but I sometimes use other tools alongside it, so the same rule applies to all of them.

## TODO files

TODO content for a project lives in exactly one place. Where depends on whether I want it public or private:

- Public TODO: rolled into the project's root `README.md`, or split out as a `TODO.md` at the project root when the list gets too noisy for a README. Lately I prefer rolling it into the README.
- Private TODO: kept as a `TODO.md` inside `.docs/`. Since `.docs/` is its own gitignored repo, the TODO never shows up publicly.

Either location is valid. The important thing is there should be only one canonical TODO for the project. If you find TODOs in two places, one is almost certainly stale and worth flagging. If both look reasonable and current, ask which one I want to keep.

## Toolchains

Toolchains are managed via `mise`. Check `mise list` and the project's `mise.toml` (or `.mise.toml`) before reaching for `brew install` for a language runtime.

---

When this file's defaults (commit format, branch naming, code style, file structure) conflict with what a project already does, follow the project. The rules here are my defaults for new or greenfield projects, not laws to impose on existing ones. The exceptions are the safety and personal-preference rules: no committing secrets, no em-dashes mid-sentence, no force-pushing without permission. These apply everywhere regardless of project convention.

Any of these can be overridden when I say so explicitly. When you're not sure whether something here applies, ask before breaking it.

@~/.claude/preferences.md
