#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool_root="$(cd "${script_dir}/.." && pwd)"

find_dans_dev_root() {
    local start="${1:-${PWD}}"
    if [[ -f "${start}" ]]; then
        start="$(dirname "${start}")"
    fi
    start="$(cd "${start}" && pwd)"

    while [[ "${start}" != "/" ]]; do
        if [[ -f "${start}/.dans_dev" ]]; then
            printf '%s\n' "${start}"
            return 0
        fi
        start="$(dirname "${start}")"
    done

    return 1
}

repo_root="$(find_dans_dev_root "${1:-${PWD}}")"
config_path="${repo_root}/.dans_dev"

config_value() {
    local key="$1"
    local fallback="$2"
    local value
    value="$(
        awk -F '=' -v wanted="${key}" '
            /^[[:space:]]*(#|$)/ { next }
            {
                line = $0
                sub(/[[:space:]]+#.*/, "", line)
                split(line, parts, "=")
                key = parts[1]
                value = substr(line, index(line, "=") + 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                if (key == wanted) {
                    print value
                    exit
                }
            }
        ' "${config_path}"
    )"

    if [[ -n "${value}" ]]; then
        printf '%s\n' "${value}"
    else
        printf '%s\n' "${fallback}"
    fi
}

config_truthy() {
    case "$1" in
        true | TRUE | True | 1 | yes | YES | Yes | on | ON | On) return 0 ;;
        *) return 1 ;;
    esac
}

enabled="$(config_value marker_tidy false)"
if ! config_truthy "${enabled}"; then
    exit 0
fi

project_build_dir="$(config_value build_dir build)"
project_build_path="${repo_root}/${project_build_dir}"
translation_units="$(config_value marker_tidy_translation_units src/main.cpp)"

if [[ ! -f "${project_build_path}/CMakeCache.txt" ]]; then
    cmake -S "${repo_root}" -B "${project_build_path}" >/dev/null
fi

tools_build_dir="${DANS_TOOLS_BUILD_DIR:-${tool_root}/build/marker_tidy}"
plugin_target="dans_dev_marker_tidy_plugin"

cmake -S "${tool_root}/tools/marker_tidy" -B "${tools_build_dir}" >/dev/null
cmake --build "${tools_build_dir}" --target "${plugin_target}" -j >/dev/null

plugin_path="$(find "${tools_build_dir}" -name 'dans_dev_marker_tidy_plugin.*' -type f | head -n 1)"
if [[ -z "${plugin_path}" ]]; then
    echo "Could not find ${plugin_target} in ${tools_build_dir}" >&2
    exit 1
fi

if [[ "$#" -eq 0 ]]; then
    # shellcheck disable=SC2206
    files=( ${translation_units} )
else
    files=( "$@" )
fi

cd "${repo_root}"
exec clang-tidy \
    --load="${plugin_path}" \
    -p "${project_build_path}" \
    --checks='-*,dans-dev-marker-tidy' \
    --warnings-as-errors='*' \
    --header-filter='.*' \
    "${files[@]}"
