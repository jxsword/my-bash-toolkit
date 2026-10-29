#!/usr/bin/env bash
# script-name: env-dump
# description: 输出环境清单（markdown）——平台/bash/PATH/工具版本/白名单环境变量，用于跨机比对与复现
# usage: env-dump.sh [--out <file>] [-h, --help]
# option: --out <file>    将清单写入指定文件（stdout 不再输出正文）
# option: -h, --help      显示帮助
# example: env-dump.sh
# example: env-dump.sh --out env-wsl-20261030.md
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash, coreutils
# category: dev

set -u -o pipefail

_ED_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_ED_ROOT/scripts/lib/common.sh"

# shellcheck source=../lib/env.sh
source "$_ED_ROOT/scripts/lib/env.sh"

# 探测工具清单（存在才列，缺失自动跳过）
readonly -a _ED_TOOLS=(
  git python3 node npm go docker bats shfmt shellcheck make curl
)

# 环境变量白名单（跨机比对关注项，未设置不列）
readonly -a _ED_ENVVARS=(
  HOME USER LOGNAME SHELL TERM LANG LC_ALL TZ EDITOR VISUAL PAGER
  XDG_CONFIG_HOME XDG_CACHE_HOME MSYSTEM WSL_DISTRO_NAME WSL_INTEROP
)

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 打印用法到 stderr
usage() {
  echo "用法: env-dump.sh [--out <file>] [-h, --help]" >&2
  echo "  默认向 stdout 输出 markdown 环境清单" >&2
  echo "  --out <file>  将清单写入指定文件（stdout 不再输出正文）" >&2
  echo "清单内容: 平台/发行版、bash 版本与区间判定、PATH 各项、" >&2
  echo "          常见工具实测版本（存在才列）、白名单环境变量" >&2
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 探测单个工具的版本首行（未安装输出空串）
_tool_version() {
  local cmd="$1" out=""
  command -v "$cmd" > /dev/null 2>&1 || return 0
  case "$cmd" in
    go)
      out="$(go version 2> /dev/null || true)"
      ;;
    shellcheck)
      out="$(shellcheck --version 2> /dev/null \
        | grep -m1 '^version:' || true)"
      ;;
    *)
      out="$("$cmd" --version 2> /dev/null | head -n1 || true)"
      ;;
  esac
  printf '%s\n' "$out"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 输出平台/发行版/bash 版本段（复用 lib/env.sh 的 bash_env_check 报告）
_dump_platform() {
  local report l1 l2
  local platform="" id="" distro="" bashver="" range="" verdict=""
  report="$(bash_env_check 2> /dev/null || true)"
  l1="$(printf '%s\n' "$report" | sed -n '1s/^\[env\] //p')"
  l2="$(printf '%s\n' "$report" | sed -n '2s/^\[env\] //p')"
  local re1='^platform=(.*) id=([^ ]+) distro=(.*)$'
  local re2='^bash=([^ ]+) range=([^ ]+) verdict=([^ ]+)$'
  if [[ "$l1" =~ $re1 ]]; then
    platform="${BASH_REMATCH[1]}"
    id="${BASH_REMATCH[2]}"
    distro="${BASH_REMATCH[3]}"
  fi
  if [[ "$l2" =~ $re2 ]]; then
    bashver="${BASH_REMATCH[1]}"
    range="${BASH_REMATCH[2]}"
    verdict="${BASH_REMATCH[3]}"
  fi
  # .bash-version 缺失/非法时降级：仅输出平台与 bash 版本
  if [[ -z "$platform" ]]; then
    platform="$(env_detect_platform)"
    id="$(env_detect_id)"
  fi
  if [[ -z "$distro" && -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    distro="$(. /etc/os-release \
      && printf '%s' "${PRETTY_NAME:-unknown}")" || distro="unknown"
  fi
  [[ -z "$bashver" ]] && bashver="$(env_bash_version)"
  echo "- platform: $platform"
  echo "- env id: $id"
  echo "- distro: ${distro:-unknown}"
  echo "- bash: $bashver"
  if [[ -n "$range" ]]; then
    echo "- bash range: $range"
    echo "- verdict: $verdict"
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 输出 PATH 各项（按冒号拆分，编号列表）
_dump_path() {
  local -a parts=()
  IFS=: read -r -a parts <<< "$PATH"
  echo "## PATH（${#parts[@]} 项）"
  echo
  local i
  for i in "${!parts[@]}"; do
    printf '%d. %s\n' "$((i + 1))" "\`${parts[$i]}\`"
  done
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 输出工具版本表（存在才列）
_dump_tools() {
  echo '## 工具版本（存在才列）'
  echo
  echo '| 工具 | 版本 |'
  echo '|---|---|'
  local t v
  for t in "${_ED_TOOLS[@]}"; do
    v="$(_tool_version "$t")"
    [[ -z "$v" ]] && continue
    printf '| %s | %s |\n' "$t" "$v"
  done
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 输出白名单环境变量表（未设置不列）
_dump_envvars() {
  echo '## 环境变量（白名单，未设置不列）'
  echo
  echo '| 变量 | 值 |'
  echo '|---|---|'
  local name val
  for name in "${_ED_ENVVARS[@]}"; do
    val="${!name:-}"
    [[ -n "$val" ]] || continue
    printf '| %s | %s |\n' "$name" "$val"
  done
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 组装完整 markdown 清单输出到 stdout
build_dump() {
  echo '# 环境清单（env-dump）'
  echo
  echo "- 生成时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo
  _dump_platform
  echo
  _dump_path
  echo
  _dump_tools
  echo
  _dump_envvars
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 参数解析与入口分派（--out 落盘，默认 stdout）
main() {
  local out_file=""
  while (($# > 0)); do
    case "$1" in
      --out)
        if (($# < 2)); then
          log_err "--out 需要一个文件参数"
          return 2
        fi
        out_file="$2"
        shift 2
        ;;
      -h | --help)
        usage
        return 0
        ;;
      *)
        usage
        return 2
        ;;
    esac
  done
  if [[ -n "$out_file" ]]; then
    local dir
    dir="$(dirname -- "$out_file")"
    if [[ ! -d "$dir" ]]; then
      log_err "目标目录不存在: $dir"
      return 1
    fi
    if ! build_dump > "$out_file"; then
      log_err "写入失败: $out_file"
      return 1
    fi
    log_info "已写入: $out_file"
    return 0
  fi
  build_dump
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
