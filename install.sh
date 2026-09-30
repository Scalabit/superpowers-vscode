#!/usr/bin/env bash
# Set up Superpowers (https://github.com/obra/superpowers) for GitHub Copilot in
# VS Code.
#
# Everything lands in $HOME and applies to every workspace you open. No project
# repository is touched. Re-running is safe and is also how you change versions.
#
#   ./install.sh                                # install or repair
#   SUPERPOWERS_VERSION=v6.5.0 ./install.sh     # move to a different version
#   ./install.sh --uninstall                    # remove the wiring
#
# Set SUPERPOWERS_SKIP_GITIGNORE=1 to keep specs and plans committable.

set -euo pipefail

SUPERPOWERS_VERSION="${SUPERPOWERS_VERSION:-v6.4.2}"
SUPERPOWERS_REPO="${SUPERPOWERS_REPO:-https://github.com/obra/superpowers.git}"
CLONE_DIR="${SUPERPOWERS_HOME:-${HOME}/.local/share/superpowers}"

COPILOT_DIR="${HOME}/.copilot"
SKILLS_LINK="${COPILOT_DIR}/skills"
HOOK_FILE="${COPILOT_DIR}/hooks/superpowers.json"

log() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

if [[ "${1:-}" == "--uninstall" ]]; then
  log "Removing Superpowers wiring"
  [[ -L "${SKILLS_LINK}" ]] && rm -f "${SKILLS_LINK}" && note "unlinked ${SKILLS_LINK}"
  [[ -f "${HOOK_FILE}" ]] && rm -f "${HOOK_FILE}" && note "removed ${HOOK_FILE}"
  note "clone left at ${CLONE_DIR} - delete it by hand if you want it gone"
  note "chat.useAgentSkills / chat.useHooks left enabled in your VS Code settings"
  note "global gitignore entries left in place - remove them by hand if unwanted"
  exit 0
fi

command -v git >/dev/null || die "git is required"

log "Fetching Superpowers ${SUPERPOWERS_VERSION}"
if [[ -d "${CLONE_DIR}/.git" ]]; then
  git -C "${CLONE_DIR}" fetch --quiet --tags origin
else
  mkdir -p "$(dirname "${CLONE_DIR}")"
  git clone --quiet "${SUPERPOWERS_REPO}" "${CLONE_DIR}"
fi
git -C "${CLONE_DIR}" -c advice.detachedHead=false checkout --quiet "${SUPERPOWERS_VERSION}"
note "$(git -C "${CLONE_DIR}" rev-parse --short HEAD) at ${CLONE_DIR}"

# ~/.copilot/skills is a location VS Code scans in every workspace, which is what
# makes this repo-independent.
log "Linking skills into ${SKILLS_LINK}"
mkdir -p "${COPILOT_DIR}"
if [[ -e "${SKILLS_LINK}" && ! -L "${SKILLS_LINK}" ]]; then
  die "${SKILLS_LINK} exists and is not a symlink; move it aside and re-run"
fi
ln -sfn "${CLONE_DIR}/skills" "${SKILLS_LINK}"
note "$(find "${SKILLS_LINK}/" -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ') skills"

# CLAUDE_PLUGIN_ROOT selects an output format, it is not a path to a Claude
# install and Claude does not need to be present. The hook script emits a
# different JSON shape per harness; VS Code reads hookSpecificOutput.additionalContext,
# which the script only produces when this is set and COPILOT_CLI is not.
log "Registering session-start hook"
mkdir -p "$(dirname "${HOOK_FILE}")"
cat > "${HOOK_FILE}" <<JSON
{
  "hooks": {
    "sessionStart": [
      {
        "type": "command",
        "command": "${CLONE_DIR}/hooks/session-start",
        "env": {
          "CLAUDE_PLUGIN_ROOT": "${CLONE_DIR}"
        },
        "timeout": 15
      }
    ]
  }
}
JSON
CLAUDE_PLUGIN_ROOT="${CLONE_DIR}" "${CLONE_DIR}/hooks/session-start" |
  grep -q hookSpecificOutput ||
  die "hook did not produce the output shape VS Code expects"
note "verified hookSpecificOutput.additionalContext"

# chat.useAgentSkills and chat.useHooks gate skill and hook discovery. Which
# settings file applies depends on whether VS Code runs locally or over
# Remote-SSH, so patch every one that exists.
log "Enabling chat.useAgentSkills and chat.useHooks"
patched=0
if command -v python3 >/dev/null; then
  for f in \
    "${HOME}/.vscode-server/data/Machine/settings.json" \
    "${HOME}/.config/Code/User/settings.json" \
    "${HOME}/.config/Code - Insiders/User/settings.json" \
    "${HOME}/Library/Application Support/Code/User/settings.json"; do
    # Only touch installs that actually exist.
    [[ "$f" == *".vscode-server"* && ! -d "${HOME}/.vscode-server" ]] && continue
    [[ "$f" != *".vscode-server"* && ! -d "$(dirname "$(dirname "$f")")" ]] && continue

    result=$(python3 - "$f" <<'PY'
import json, os, sys

path = sys.argv[1]
wanted = {"chat.useAgentSkills": True, "chat.useHooks": True}
raw = ""

if os.path.exists(path):
    with open(path) as fh:
        raw = fh.read()
    try:
        data = json.loads(raw) if raw.strip() else {}
    except ValueError:
        # Comments or trailing commas: editing would corrupt the file.
        print("MANUAL")
        sys.exit(0)
else:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = {}

if all(data.get(k) is True for k in wanted):
    print("ALREADY")
    sys.exit(0)

if raw:
    with open(path + ".bak", "w") as fh:
        fh.write(raw)

data.update(wanted)
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
print("PATCHED")
PY
)
    case "$result" in
      PATCHED) note "updated $f"; patched=1 ;;
      ALREADY) note "already set in $f"; patched=1 ;;
      MANUAL)  note "could not parse $f (comments?) - set the flags there by hand" ;;
    esac
  done
else
  note "python3 not found - set the flags by hand"
fi

if [[ "$patched" -eq 0 ]]; then
  cat <<'EOF'

    Add these to your VS Code user settings (Preferences: Open User Settings (JSON)):

        "chat.useAgentSkills": true,
        "chat.useHooks": true
EOF
fi

# Superpowers writes specs and plans into docs/superpowers/ of whatever project
# you happen to be in, and tells the agent to commit them. Listing the paths in
# the global gitignore keeps them out of every repo without editing any of them.
if [[ -z "${SUPERPOWERS_SKIP_GITIGNORE:-}" ]]; then
  log "Keeping docs/superpowers/ out of git"
  configured=$(git config --global --get core.excludesFile || true)
  if [[ -n "${configured}" ]]; then
    ignore_file="${configured/#\~/${HOME}}"
  else
    ignore_file="${XDG_CONFIG_HOME:-${HOME}/.config}/git/ignore"
  fi

  mkdir -p "$(dirname "${ignore_file}")"
  touch "${ignore_file}"

  appended=0
  for pattern in 'docs/superpowers/' '.superpowers/'; do
    grep -qxF "${pattern}" "${ignore_file}" && continue
    if [[ "${appended}" -eq 0 ]]; then
      printf '\n# Superpowers working artifacts - kept local, never committed\n' >> "${ignore_file}"
      appended=1
    fi
    printf '%s\n' "${pattern}" >> "${ignore_file}"
  done

  if [[ "${appended}" -eq 1 ]]; then
    note "added patterns to ${ignore_file}"
  else
    note "already listed in ${ignore_file}"
  fi
  # Ignore rules never apply to files git is already tracking.
  note "already-committed docs/superpowers/ needs 'git rm --cached -r' to untrack"
fi

cat <<'EOF'

Done. Reload VS Code (Developer: Reload Window) and start a new chat.

To check it worked, send: let's build a react todo list
A working install asks you design questions instead of writing code.

Superpowers now applies in every repo you open. Its workflow writes specs and
plans into docs/superpowers/ of whatever project you are working on.
EOF
