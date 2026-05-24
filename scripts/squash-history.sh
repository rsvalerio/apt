#!/usr/bin/env bash
# Squash git history to a single commit and optionally keep only the latest
# .deb per package in pool/. See README.md "How it works".
#
# WARNING: Rewrites history. Requires force-push and re-clone for other copies.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

readonly DEFAULT_BRANCH="main"
readonly DEFAULT_REMOTE="origin"
readonly DEFAULT_MESSAGE="chore(apt): squash history; keep latest packages only"

squash_history_usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Squash this repository to one commit so old .deb blobs are dropped from git
history. Run from a clone of rsvalerio/apt.

Commands:
  help          Show this message
  prune-pool    Remove older pool/*.deb files; keep latest version per package
  squash        Replace branch history with one commit from the current tree
  run           prune-pool, then squash (typical workflow)
  push          Force-push the current branch to the remote

Options (prune-pool, squash, run):
  --dry-run     Print actions without changing files or git state
  --yes         Skip interactive confirmation
  --message MSG Commit message for squash (default: ${DEFAULT_MESSAGE})

Options (push):
  --remote NAME Remote name (default: ${DEFAULT_REMOTE})
  --branch NAME Branch name (default: ${DEFAULT_BRANCH})
  --yes         Skip interactive confirmation

Examples:
  $(basename "$0") run --dry-run
  $(basename "$0") run --yes
  $(basename "$0") push --yes

After run + push, re-clone this repository elsewhere. GitHub Pages republish
is triggered automatically when pool/*.deb or public.key changes on main.
EOF
}

squash_history_die() {
  echo "error: $*" >&2
  exit 1
}

squash_history_info() {
  echo "$*"
}

squash_history_require_repo() {
  if ! git -C "${REPO_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
    squash_history_die "not a git repository: ${REPO_ROOT}"
  fi
}

squash_history_require_clean_tree() {
  if ! git -C "${REPO_ROOT}" diff --quiet || ! git -C "${REPO_ROOT}" diff --cached --quiet; then
    squash_history_die "working tree has uncommitted changes; commit or stash first"
  fi
}

squash_history_parse_deb_filename() {
  local filename="$1"

  if [[ "${filename}" =~ ^(.+)_(.+)_(.+)\.deb$ ]]; then
    DEB_PKG_NAME="${BASH_REMATCH[1]}"
    DEB_PKG_VERSION="${BASH_REMATCH[2]}"
    DEB_PKG_ARCH="${BASH_REMATCH[3]}"
    return 0
  fi

  return 1
}

squash_history_pool_key() {
  printf '%s_%s' "${DEB_PKG_NAME}" "${DEB_PKG_ARCH}"
}

squash_history_list_pool_debs() {
  local deb

  shopt -s nullglob
  for deb in "${REPO_ROOT}"/pool/*.deb; do
    printf '%s\n' "${deb}"
  done
  shopt -u nullglob
}

squash_history_prune_pool() {
  local dry_run=false
  local assume_yes=false
  local fs_only=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true ;;
      --yes) assume_yes=true ;;
      --fs-only) fs_only=true ;;
      *)
        squash_history_die "unknown option for prune-pool: $1"
        ;;
    esac
    shift
  done

  squash_history_require_repo

  local -a all_debs=()
  local deb
  while IFS= read -r deb; do
    [[ -n "${deb}" ]] && all_debs+=("${deb}")
  done < <(squash_history_list_pool_debs)

  if [[ ${#all_debs[@]} -eq 0 ]]; then
    squash_history_info "pool/ has no .deb files; nothing to prune"
    return 0
  fi

  local inventory keep_list
  inventory="$(mktemp)"
  keep_list="$(mktemp)"

  for deb in "${all_debs[@]}"; do
    local base key
    base="$(basename "${deb}")"
    if ! squash_history_parse_deb_filename "${base}"; then
      rm -f "${inventory}" "${keep_list}"
      squash_history_die "cannot parse pool filename (expected name_version_arch.deb): ${base}"
    fi
    key="$(squash_history_pool_key)"
    printf '%s\t%s\t%s\n' "${key}" "${DEB_PKG_VERSION}" "${deb}" >> "${inventory}"
  done

  sort -t $'\t' -k1,1 -k2,2V "${inventory}" \
    | awk -F '\t' '{ last[$1] = $3 } END { for (k in last) print last[k] }' \
    > "${keep_list}"

  local -a keep_debs=()
  while IFS= read -r keep_path; do
    [[ -n "${keep_path}" ]] && keep_debs+=("${keep_path}")
  done < "${keep_list}"

  rm -f "${inventory}" "${keep_list}"

  local -a to_remove=()
  for deb in "${all_debs[@]}"; do
    local keep=false
    local kept
    for kept in "${keep_debs[@]}"; do
      if [[ "${deb}" == "${kept}" ]]; then
        keep=true
        break
      fi
    done
    if ! ${keep}; then
      to_remove+=("${deb}")
    fi
  done

  squash_history_info "Keeping latest .deb per package:"
  for kept in "${keep_debs[@]}"; do
    squash_history_info "  $(basename "${kept}")"
  done

  if [[ ${#to_remove[@]} -eq 0 ]]; then
    squash_history_info "pool/ already has only the latest version per package"
    return 0
  fi

  squash_history_info "Removing older pool packages:"
  for deb in "${to_remove[@]}"; do
    squash_history_info "  $(basename "${deb}")"
  done

  if ${dry_run}; then
    squash_history_info "dry-run: no files removed"
    return 0
  fi

  if ! ${assume_yes}; then
    printf 'Remove %d older .deb file(s) from pool/? [y/N] ' "${#to_remove[@]}"
    local reply
    read -r reply
    case "${reply}" in
      y | Y | yes | YES) ;;
      *)
        squash_history_die "aborted"
        ;;
    esac
  fi

  for deb in "${to_remove[@]}"; do
    if ${fs_only}; then
      rm -f -- "${deb}"
    else
      git -C "${REPO_ROOT}" rm -f -- "${deb#${REPO_ROOT}/}"
    fi
  done

  if ${fs_only}; then
    squash_history_info "Removed ${#to_remove[@]} file(s) from disk."
  else
    squash_history_info "Removed ${#to_remove[@]} file(s). Commit before squash, or run 'run' to prune and squash together."
  fi
}

squash_history_confirm() {
  local prompt="$1"
  local assume_yes="${2:-false}"

  if ${assume_yes}; then
    return 0
  fi

  printf '%s [y/N] ' "${prompt}"
  local reply
  read -r reply
  case "${reply}" in
    y | Y | yes | YES) ;;
    *)
      squash_history_die "aborted"
      ;;
  esac
}

squash_history_squash() {
  local dry_run=false
  local assume_yes=false
  local allow_dirty=false
  local message="${DEFAULT_MESSAGE}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true ;;
      --yes) assume_yes=true ;;
      --allow-dirty) allow_dirty=true ;;
      --message)
        shift
        [[ $# -gt 0 ]] || squash_history_die "--message requires a value"
        message="$1"
        ;;
      *)
        squash_history_die "unknown option for squash: $1"
        ;;
    esac
    shift
  done

  squash_history_require_repo
  if ! ${allow_dirty}; then
    squash_history_require_clean_tree
  fi

  local branch
  branch="$(git -C "${REPO_ROOT}" branch --show-current)"
  [[ -n "${branch}" ]] || squash_history_die "detached HEAD; checkout ${DEFAULT_BRANCH} first"

  local commit_count
  commit_count="$(git -C "${REPO_ROOT}" rev-list --count HEAD)"

  squash_history_info "Branch: ${branch}"
  squash_history_info "Commits to replace: ${commit_count}"
  squash_history_info "New commit message: ${message}"

  squash_history_info "Files that will be included:"
  git -C "${REPO_ROOT}" ls-files -z | while IFS= read -r -d '' path; do
    if [[ -f "${REPO_ROOT}/${path}" ]]; then
      squash_history_info "  ${path}"
    fi
  done

  if ${dry_run}; then
    squash_history_info "dry-run: history not rewritten"
    return 0
  fi

  squash_history_confirm \
    "Rewrite ${branch} to a single commit and delete ${commit_count} commit(s) from local history?" \
    "${assume_yes}"

  local orphan_branch="squash-tmp-$$"

  git -C "${REPO_ROOT}" checkout --orphan "${orphan_branch}"
  git -C "${REPO_ROOT}" add -A
  git -C "${REPO_ROOT}" commit -m "${message}"

  if git -C "${REPO_ROOT}" show-ref --verify --quiet "refs/heads/${branch}"; then
    git -C "${REPO_ROOT}" branch -D "${branch}"
  fi

  git -C "${REPO_ROOT}" branch -m "${branch}"

  squash_history_info "Squashed ${branch} to one commit: $(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
  squash_history_info "Next: $(basename "$0") push --yes"
}

squash_history_push() {
  local remote="${DEFAULT_REMOTE}"
  local branch="${DEFAULT_BRANCH}"
  local assume_yes=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --remote)
        shift
        [[ $# -gt 0 ]] || squash_history_die "--remote requires a value"
        remote="$1"
        ;;
      --branch)
        shift
        [[ $# -gt 0 ]] || squash_history_die "--branch requires a value"
        branch="$1"
        ;;
      --yes) assume_yes=true ;;
      *)
        squash_history_die "unknown option for push: $1"
        ;;
    esac
    shift
  done

  squash_history_require_repo

  local current_branch
  current_branch="$(git -C "${REPO_ROOT}" branch --show-current)"
  [[ "${current_branch}" == "${branch}" ]] \
    || squash_history_die "checkout ${branch} before push (currently on ${current_branch:-detached HEAD})"

  if ! git -C "${REPO_ROOT}" remote get-url "${remote}" >/dev/null 2>&1; then
    squash_history_die "remote not found: ${remote}"
  fi

  squash_history_info "Will run: git push --force ${remote} ${branch}"

  squash_history_confirm \
    "Force-push ${branch} to ${remote}? Other clones must re-clone." \
    "${assume_yes}"

  git -C "${REPO_ROOT}" push --force "${remote}" "${branch}"
  squash_history_info "Force-push complete."
}

squash_history_run() {
  local dry_run=false
  local assume_yes=false
  local message="${DEFAULT_MESSAGE}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true ;;
      --yes) assume_yes=true ;;
      --message)
        shift
        [[ $# -gt 0 ]] || squash_history_die "--message requires a value"
        message="$1"
        ;;
      *)
        squash_history_die "unknown option for run: $1"
        ;;
    esac
    shift
  done

  local -a common_flags=()
  ${dry_run} && common_flags+=(--dry-run)
  ${assume_yes} && common_flags+=(--yes)

  if ! ${dry_run}; then
    squash_history_require_clean_tree
  fi

  squash_history_prune_pool "${common_flags[@]}" --fs-only
  squash_history_squash \
    "${common_flags[@]}" \
    --allow-dirty \
    --message "${message}"
}

squash_history_main() {
  local command="${1:-help}"
  shift || true

  case "${command}" in
    help | -h | --help)
      squash_history_usage
      ;;
    prune-pool)
      squash_history_prune_pool "$@"
      ;;
    squash)
      squash_history_squash "$@"
      ;;
    run)
      squash_history_run "$@"
      ;;
    push)
      squash_history_push "$@"
      ;;
    *)
      echo "error: unknown command: ${command}" >&2
      echo >&2
      squash_history_usage >&2
      exit 1
      ;;
  esac
}

squash_history_main "$@"
