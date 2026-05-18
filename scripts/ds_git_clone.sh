#!/usr/bin/env bash
set -euo pipefail

commit_message="initial setup"
clone_url=""
selected_template=""

template_ids=("nothing" "ds-core")
template_labels=("nothing" "ds-core (most recent version)")
template_urls=("" "https://github.com/Daniel-Sinkin/ds-core")

usage() {
    cat <<'EOF'
Usage:
  ds_git_clone
  ds_git_clone --clone <repo-url>
  ds_git_clone -c <repo-url>
  ds_git_clone --template <template-id>
  ds_git_clone --list
  ds_git_clone -l

Modes:
  Run inside an empty git repo with zero commits, or run from a non-git parent
  directory with --clone/-c <repo-url> to clone the target repo first.

Templates:
  nothing   Leave the repo empty.
  ds-core   Copy the latest files from https://github.com/Daniel-Sinkin/ds-core.

Interactive selection also accepts "a" to abort before any clone happens.
EOF
}

die() {
    printf 'ds_git_clone: %s\n' "$*" >&2
    exit 1
}

list_templates() {
    local i
    for i in "${!template_ids[@]}"; do
        printf '%d) %s [%s]\n' "$((i + 1))" "${template_labels[$i]}" "${template_ids[$i]}"
    done
}

list_template_menu() {
    list_templates
    printf 'a) Abort\n'
}

template_index_for() {
    local wanted="$1"
    local i

    if [[ "${wanted}" =~ ^[0-9]+$ ]]; then
        local index=$((wanted - 1))
        if ((index >= 0 && index < ${#template_ids[@]})); then
            printf '%s\n' "${index}"
            return 0
        fi
    fi

    for i in "${!template_ids[@]}"; do
        if [[ "${template_ids[$i]}" == "${wanted}" ]]; then
            printf '%s\n' "${i}"
            return 0
        fi
    done

    return 1
}

choose_template() {
    if [[ -n "${selected_template}" ]]; then
        template_index_for "${selected_template}"
        return
    fi

    printf 'Select repo template:\n' >&2
    list_template_menu >&2
    printf '> ' >&2

    local choice
    read -r choice
    if [[ "${choice}" == "a" || "${choice}" == "A" || "${choice}" == "abort" || "${choice}" == "q" || "${choice}" == "quit" ]]; then
        return 130
    fi
    template_index_for "${choice}"
}

repo_name_from_url() {
    local url="${1%/}"
    local name="${url##*/}"
    printf '%s\n' "${name%.git}"
}

current_git_root() {
    git rev-parse --show-toplevel 2>/dev/null || true
}

repo_has_commits() {
    git -C "$1" rev-parse --verify HEAD >/dev/null 2>&1
}

repo_has_visible_contents() {
    find "$1" -mindepth 1 -maxdepth 1 ! -name '.git' -print -quit | grep -q .
}

assert_zero_commit_repo() {
    local repo_root="$1"
    if repo_has_commits "${repo_root}"; then
        die "${repo_root} already has commits; refusing to apply a starter template"
    fi
}

remote_has_refs() {
    local url="$1"
    local refs

    if ! refs="$(git ls-remote "${url}")"; then
        die "could not inspect ${url}; refusing to clone"
    fi

    [[ -n "${refs}" ]]
}

assert_zero_commit_remote() {
    local url="$1"
    if remote_has_refs "${url}"; then
        die "${url} already has commits; refusing to clone before applying a starter template"
    fi
}

clone_target_repo() {
    local url="$1"
    local name
    name="$(repo_name_from_url "${url}")"
    [[ -n "${name}" ]] || die "could not infer repo directory name from ${url}"
    [[ ! -e "${name}" ]] || die "${PWD}/${name} already exists"

    git clone "${url}" "${name}" >&2
    printf '%s/%s\n' "${PWD}" "${name}"
}

copy_template_files() {
    local template_index="$1"
    local target_root="$2"
    local template_id="${template_ids[$template_index]}"
    local template_url="${template_urls[$template_index]}"

    printf 'Target repo: %s\n' "${target_root}"
    printf 'Template: %s\n' "${template_labels[$template_index]}"

    if [[ "${template_id}" == "nothing" ]]; then
        printf 'No template selected; repo left unchanged.\n'
        return 0
    fi

    if repo_has_visible_contents "${target_root}"; then
        die "${target_root} is not empty; refusing to copy template files over existing files"
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap "rm -rf '${tmp_dir}'" EXIT

    git clone --depth 1 "${template_url}" "${tmp_dir}/template"

    if repo_has_visible_contents "${tmp_dir}/template"; then
        rsync -a --exclude '.git' "${tmp_dir}/template/" "${target_root}/"
    else
        printf 'Template repo has no files yet; nothing copied.\n'
    fi
}

commit_if_changed() {
    local repo_root="$1"
    if [[ -z "$(git -C "${repo_root}" status --short)" ]]; then
        printf 'No file changes to commit.\n'
        return 1
    fi

    git -C "${repo_root}" add .
    git -C "${repo_root}" commit -m "${commit_message}"
}

push_initial_commit() {
    local repo_root="$1"
    local branch

    if ! git -C "${repo_root}" remote get-url origin >/dev/null 2>&1; then
        printf 'No origin remote configured; skipping push.\n'
        return 0
    fi

    branch="$(git -C "${repo_root}" symbolic-ref --quiet --short HEAD)"
    [[ -n "${branch}" ]] || die "could not determine current branch for ${repo_root}"

    git -C "${repo_root}" push -u origin "${branch}"
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -c | --clone)
            [[ "$#" -ge 2 ]] || die "$1 requires a repo URL"
            clone_url="$2"
            shift 2
            ;;
        -t | --template)
            [[ "$#" -ge 2 ]] || die "$1 requires a template id"
            selected_template="$2"
            shift 2
            ;;
        -l | --list)
            list_templates
            exit 0
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

git_root="$(current_git_root)"

if [[ -n "${clone_url}" ]]; then
    [[ -z "${git_root}" ]] || die "--clone must be run from outside an existing git repo"
    assert_zero_commit_remote "${clone_url}"
else
    [[ -n "${git_root}" ]] || die "not inside a git repo; use --clone or -c <repo-url> from the parent folder"
    assert_zero_commit_repo "${git_root}"
fi

set +e
template_index="$(choose_template)"
choose_status="$?"
set -e

if [[ "${choose_status}" -eq 130 ]]; then
    printf 'Aborted.\n'
    exit 130
fi
if [[ "${choose_status}" -ne 0 ]]; then
    die "unknown template: ${selected_template:-<empty>}"
fi

target_root=""
if [[ -n "${clone_url}" ]]; then
    target_root="$(clone_target_repo "${clone_url}")"
else
    target_root="${git_root}"
fi

assert_zero_commit_repo "${target_root}"
copy_template_files "${template_index}" "${target_root}"
if commit_if_changed "${target_root}"; then
    push_initial_commit "${target_root}"
fi
