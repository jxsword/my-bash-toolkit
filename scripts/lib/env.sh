#!/usr/bin/env bash
# script-name: env
# description: bash 环境检测库——平台/环境识别与 .bash-version 区间判定（双向硬阻断）
# usage: （库，被 source；直接执行等价于运行 bash_env_check）
# option: --quiet    直接执行模式透传：仅退出码，不输出报告
# example: scripts/lib/env.sh
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: coreutils（sort -V）
# category: lib

set -u -o pipefail

readonly _ENV_ID_UBUNTU='ubuntu-26.04'
readonly _ENV_ID_WSL='wsl-ubuntu-26.04'
readonly _ENV_ID_GITBASH='git-bash'

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 定位 .bash-version（可用 BASH_VERSION_FILE 覆盖）
env_version_file() {
  if [[ -n "${BASH_VERSION_FILE:-}" ]]; then
    printf '%s\n' "$BASH_VERSION_FILE"
    return 0
  fi
  local dir
  dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  local candidate="$dir/../../.bash-version"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 识别平台：msys / wsl / linux
env_detect_platform() {
  if [[ -n "${MSYSTEM:-}" && "${OSTYPE:-}" == msys* ]]; then
    printf 'msys\n'
    return 0
  fi
  if [[ -r /proc/version ]] \
    && grep -qi microsoft /proc/version 2> /dev/null; then
    printf 'wsl\n'
    return 0
  fi
  printf 'linux\n'
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 输出 canonical 环境标识符（spec §1），无法识别输出 unknown
env_detect_id() {
  local platform distro_id="" distro_ver=""
  platform="$(env_detect_platform)"
  if [[ "$platform" == "msys" ]]; then
    printf '%s\n' "$_ENV_ID_GITBASH"
    return 0
  fi
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    distro_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
    # shellcheck disable=SC1091
    distro_ver="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
  fi
  local is_ubuntu2604="false"
  if [[ "$distro_id" == "ubuntu" && "$distro_ver" == 26.04* ]]; then
    is_ubuntu2604="true"
  fi
  if [[ "$platform" == "wsl" ]]; then
    if [[ "$is_ubuntu2604" == "true" ]]; then
      printf '%s\n' "$_ENV_ID_WSL"
    else
      printf 'unknown\n'
    fi
    return 0
  fi
  if [[ "$is_ubuntu2604" == "true" ]]; then
    printf '%s\n' "$_ENV_ID_UBUNTU"
  else
    printf 'unknown\n'
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 当前环境 id 是否在参数列表中（供测试 skip）
env_is_supported() {
  local cur id
  cur="$(env_detect_id)"
  for id in "$@"; do
    [[ "$id" == "$cur" ]] && return 0
  done
  return 1
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 输出 X.Y.Z 形式的当前 bash 版本号
env_bash_version() {
  printf '%s.%s.%s\n' \
    "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" "${BASH_VERSINFO[2]}"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 解析 .bash-version 到 _ENV_MIN/_ENV_MAX；格式非法返回 2
env_parse_range() {
  local file="$1" line re
  line="$(grep -v '^[[:space:]]*#' "$file" \
    | grep -v '^[[:space:]]*$' | head -n1 | tr -d '[:space:]')"
  re='^([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+\.[0-9]+\.[0-9]+)$'
  if ! [[ "$line" =~ $re ]]; then
    return 2
  fi
  _ENV_MIN="${BASH_REMATCH[1]}"
  _ENV_MAX="${BASH_REMATCH[2]}"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 版本比较（sort -V 实现）：a<b 输出 -1，a>b 输出 1，相等输出 0
env_version_cmp() {
  local a="$1" b="$2" first
  if [[ "$a" == "$b" ]]; then
    printf '0\n'
    return 0
  fi
  first="$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)"
  if [[ "$first" == "$a" ]]; then
    printf -- '-1\n'
  else
    printf '1\n'
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 判定当前 bash 是否在 .bash-version 区间（0 支持/1 不支持/2 配置异常）
bash_env_check() {
  local quiet="false"
  [[ "${1:-}" == "--quiet" ]] && quiet="true"
  local file min max ver rel
  local cur_platform cur_id cur_distro="unknown" cmp
  file="$(env_version_file)" || {
    [[ "$quiet" == "false" ]] \
      && echo "错误: 找不到 .bash-version（可设 BASH_VERSION_FILE）" >&2
    return 2
  }
  _ENV_MIN="" _ENV_MAX=""
  if ! env_parse_range "$file"; then
    [[ "$quiet" == "false" ]] \
      && echo "错误: .bash-version 格式非法（期望单行 MIN-MAX，如 5.2.0-5.3.9）" >&2
    return 2
  fi
  min="$_ENV_MIN"
  max="$_ENV_MAX"
  ver="$(env_bash_version)"
  cur_platform="$(env_detect_platform)"
  cur_id="$(env_detect_id)"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    cur_distro="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-unknown}")"
  fi
  cmp="$(env_version_cmp "$ver" "$min")"
  if [[ "$cmp" == "-1" ]]; then
    rel="TOO_OLD"
  else
    cmp="$(env_version_cmp "$ver" "$max")"
    if [[ "$cmp" == "1" ]]; then rel="TOO_NEW"; else rel="OK"; fi
  fi
  if [[ "$quiet" == "false" ]]; then
    echo "[env] platform=$cur_platform id=$cur_id distro=$cur_distro"
    echo "[env] bash=$ver range=$min-$max verdict=$rel"
    if [[ "$rel" != "OK" ]]; then
      echo "错误: bash $ver 超出支持区间 $min-$max" >&2
      echo "指引: 在新环境重测通过后更新 .bash-version" >&2
      echo "      （流程见 docs/bash_env_and_doc_spec.md §8）" >&2
    fi
  fi
  if [[ "$rel" == "OK" ]]; then
    return 0
  fi
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  bash_env_check "$@"
fi
