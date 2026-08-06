#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_REPOSITORY="cambelljsmith/uppersky"
REMOTE_NAME="origin"
REMOTE_BRANCH="main"

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

command -v git >/dev/null 2>&1 || fail "Git is not installed or is not available in PATH."

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(git -C "$script_directory" rev-parse --show-toplevel 2>/dev/null)" \
    || fail "This script must be run from inside a Git checkout of CambellJSmith/UpperSky."
repository_root="$(cd -- "$repository_root" && pwd -P)"

[[ "$repository_root" != "/" ]] || fail "Refusing to operate on the filesystem root."
if [[ -n "${HOME:-}" ]]; then
    home_directory="$(cd -- "$HOME" 2>/dev/null && pwd -P || printf '%s' "$HOME")"
    [[ "$repository_root" != "$home_directory" ]] || fail "Refusing to operate directly on the home directory."
fi

origin_url="$(git -C "$repository_root" remote get-url "$REMOTE_NAME" 2>/dev/null)" \
    || fail "The repository has no '$REMOTE_NAME' remote."
normalized_origin="$origin_url"
normalized_origin="${normalized_origin%.git}"
normalized_origin="${normalized_origin#git@github.com:}"
normalized_origin="${normalized_origin#ssh://git@github.com/}"
normalized_origin="${normalized_origin#https://github.com/}"
normalized_origin="${normalized_origin#http://github.com/}"
normalized_origin="$(printf '%s' "$normalized_origin" | tr '[:upper:]' '[:lower:]')"
[[ "$normalized_origin" == "$EXPECTED_REPOSITORY" ]] \
    || fail "The '$REMOTE_NAME' remote is '$origin_url', not CambellJSmith/UpperSky."

printf '%s\n' "WARNING: Replacing '$repository_root' with $REMOTE_NAME/$REMOTE_BRANCH."
printf '%s\n' "All local commits, modifications, untracked files, ignored files, and generated data in this checkout will be deleted."

# Fetch the authoritative branch before changing or deleting local files.
git -C "$repository_root" fetch --prune "$REMOTE_NAME" "$REMOTE_BRANCH"
git -C "$repository_root" rev-parse --verify "$REMOTE_NAME/$REMOTE_BRANCH^{commit}" >/dev/null \
    || fail "The fetched $REMOTE_NAME/$REMOTE_BRANCH ref is not a valid commit."

# Force the local main branch and worktree to exactly match the fetched branch.
git -C "$repository_root" checkout -B "$REMOTE_BRANCH" "$REMOTE_NAME/$REMOTE_BRANCH" --force
git -C "$repository_root" reset --hard "$REMOTE_NAME/$REMOTE_BRANCH"

# Remove every untracked and ignored path, including nested untracked repositories.
git -C "$repository_root" clean -ffdx

# Make tracked submodules exact as well, when the repository contains any.
if [[ -f "$repository_root/.gitmodules" ]]; then
    git -C "$repository_root" submodule sync --recursive
    git -C "$repository_root" submodule update --init --recursive --force
    git -C "$repository_root" submodule foreach --recursive 'git reset --hard && git clean -ffdx'
fi

# Pull Git LFS objects when Git LFS is installed; ordinary Git checkout remains sufficient otherwise.
if git lfs version >/dev/null 2>&1; then
    git -C "$repository_root" lfs pull "$REMOTE_NAME" "$REMOTE_BRANCH"
fi

remaining_changes="$(git -C "$repository_root" status --porcelain --untracked-files=all)"
[[ -z "$remaining_changes" ]] || fail "The checkout is not clean after replacement:\n$remaining_changes"

current_commit="$(git -C "$repository_root" rev-parse HEAD)"
printf 'Replacement complete. Local main now matches %s/%s at %s.\n' \
    "$REMOTE_NAME" "$REMOTE_BRANCH" "$current_commit"
