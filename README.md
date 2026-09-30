# superpowers-vscode

Installs [Superpowers](https://github.com/obra/superpowers) for **GitHub Copilot in VS Code**.

Superpowers is a skills framework that pushes a coding agent through a disciplined workflow —
brainstorm a design, write a plan, execute it task by task, review, then land the branch.
Upstream ships installers for Claude Code, Codex, Cursor, Gemini and others, but not for
Copilot Chat in VS Code. This repo fills that gap.

## Install

```bash
git clone https://github.com/Scalabit/superpowers-vscode.git
cd superpowers-vscode
./install.sh
```

Then reload VS Code (`Developer: Reload Window`) and start a new chat.

To check it worked, send `let's build a react todo list`. A working install asks you design
questions instead of writing code.

## What it does

Everything lands in `$HOME`. **No project repository is modified.**

| Step | Result |
| --- | --- |
| Clone | `~/.local/share/superpowers`, pinned to a tag |
| Skills | `~/.copilot/skills` → symlink to the clone's `skills/` |
| Hook | `~/.copilot/hooks/superpowers.json` |
| Settings | `chat.useAgentSkills` and `chat.useHooks` set to `true` |
| Git | `docs/superpowers/` and `.superpowers/` added to your global gitignore |

`~/.copilot/skills` and `~/.copilot/hooks` are user-level locations VS Code scans in *every*
workspace, so one install covers all your projects.

The settings step patches whichever files exist — `~/.vscode-server/data/Machine/settings.json`
for Remote-SSH, `~/.config/Code/User/settings.json` for Linux, the Insiders and macOS paths
too. It backs up before writing, and if a settings file contains comments or trailing commas
it refuses to edit and tells you to set the flags by hand rather than corrupting the file.

## Keeping specs and plans out of git

The workflow writes design docs and plans into `docs/superpowers/` of whichever project you
are working in, and the `brainstorming` skill explicitly tells the agent to commit them. That
is rarely what you want in a shared repository.

The installer adds `docs/superpowers/` and `.superpowers/` to your global gitignore — either
the file named by `core.excludesFile`, or `~/.config/git/ignore`, which git reads by default.
The artifacts still land next to your code where they are useful, they just never enter the
tree. Nothing in any project repository is edited, and the patterns are appended only if
missing, so re-running is safe.

```bash
SUPERPOWERS_SKIP_GITIGNORE=1 ./install.sh   # if you would rather commit them
```

One limit: gitignore has no effect on files git already tracks. If a repo already commits
`docs/superpowers/`, untracking it takes `git rm --cached -r docs/superpowers` — a commit
that removes the files for everyone, so agree it with your team first.

## How skills reach the agent

VS Code loads only each skill's `name` and `description` up front, then reads the full
`SKILL.md` on demand. Which skill fires is the model's judgement, so the session-start hook
injects Superpowers' `using-superpowers` bootstrap to make triggering reliable.

You can always force one by naming it:

```text
use the brainstorming skill: I want to add rate limiting to the API
use writing-plans with that spec
use subagent-driven-development to execute the plan
use requesting-code-review on the branch
```

For a sequence you run often, pin it in a `.github/agents/*.agent.md` file rather than
relying on auto-selection.

## Two things that look wrong but aren't

**`CLAUDE_PLUGIN_ROOT` in the hook config.** You do not need Claude installed. The upstream
hook emits a different JSON shape per harness, and VS Code reads
`hookSpecificOutput.additionalContext` — the shape the script produces only when
`CLAUDE_PLUGIN_ROOT` is set and `COPILOT_CLI` is not. The script derives its actual plugin
root from its own location, so this variable is a *format selector*, not a path. Set it to
garbage and the output is byte-identical; unset it and VS Code silently receives nothing.

**The bootstrap mentions a `Skill` tool.** The injected text tells the agent to use a `Skill`
tool for other skills. VS Code has no such tool — it reads `SKILL.md` files directly, which
works fine. Harmless wording mismatch from upstream.

## Maintenance

```bash
SUPERPOWERS_VERSION=v6.5.0 ./install.sh   # move to another version
./install.sh                              # re-run to repair
./install.sh --uninstall                  # unlink skills and remove the hook
```

`--uninstall` leaves the clone, the VS Code settings flags and the gitignore entries alone;
remove those by hand if you want them gone.

The version is pinned in `install.sh` rather than tracking `main`, so a team stays on one
release. Bump it deliberately.

> **The hook runs code on every session.** `~/.copilot/hooks/superpowers.json` executes a
> shell script from a third-party repository each time a chat session starts. That is the
> reason for pinning a tag. Review the diff in `~/.local/share/superpowers` before raising
> the pinned version.

## Also covers Copilot CLI

Copilot CLI reads `~/.copilot/` as well, so this install covers it too. The upstream hook
detects the harness via `COPILOT_CLI` and emits the matching output format for each.

Other harnesses have their own installers and are independent of this one — see
[upstream's installation section](https://github.com/obra/superpowers#installation).

## Requirements

`git`, `bash`, and `python3` (only for the settings step; skipped with instructions if absent).

## License

MIT. Superpowers itself is MIT, copyright Jesse Vincent and contributors.
