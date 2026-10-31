#!/usr/bin/env bash
# script-name: bench-tests
# description: 测试基准计时——逐文件分时与全程墙钟双列统计，输出 markdown 报告（优化前后对比用）
# usage: bench-tests.sh [--changed] [--staged] [--base <ref>]
#          [--files <文件>...] [--save <file>]
# option: --changed/--staged/--base/--files    测试范围选择（透传 test-changed.sh；缺省=全量）
# option: --save <file>    报告落盘（已存在拒绝覆盖；缺省仅打印）
# example: make bench-tests ARGS="--save /tmp/bench-before.md"
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats, bash
# category: dev
# 注意: 本工具刻意不加 timeout——慢正是被测对象；各文件分时含独立启动开销，
#       分时总和 > 单次全跑墙钟属正常，报告已双列呈现。

set -u -o pipefail

_ROOT="$(git rev-parse --show-toplevel 2> /dev/null)" || {
  echo "错误: 当前目录不在 git 仓库内" >&2
  exit 2
}
# test-changed 助手与本脚本同级：即使被测仓库是沙箱（无 scripts/dev/）也可用
_HELPER="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test-changed.sh"
declare -a _SELECTION=()
_SAVE=""

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 打印用法
usage() {
  sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 计算两个 EPOCHREALTIME 的毫秒差
elapsed_ms() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.0f", (b - a) * 1000 }'
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 选定测试文件集合——有选择旗标则透传 test-changed.sh，否则全量
select_files() {
  if ((${#_SELECTION[@]} > 0)); then
    "$_HELPER" "${_SELECTION[@]}"
  else
    # shellcheck source=../../scripts/lib/test_files.sh
    source "$_ROOT/scripts/lib/test_files.sh"
    collect_bats_files "$_ROOT"
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 入口——参数解析、范围选择、全程墙钟 + 逐文件分时统计与报告
main() {
  local rc=0
  while (($# > 0)); do
    case "$1" in
      --changed | --staged)
        _SELECTION+=("$1")
        ;;
      --base)
        [[ $# -ge 2 ]] || {
          echo "错误: --base 需要参数" >&2
          return 2
        }
        _SELECTION+=("--base" "$2")
        shift
        ;;
      --files)
        _SELECTION+=("--files")
        ;;
      --save)
        [[ $# -ge 2 ]] || {
          echo "错误: --save 需要参数" >&2
          return 2
        }
        _SAVE="$2"
        shift
        ;;
      -h | --help)
        usage
        return 0
        ;;
      *)
        if [[ "${_SELECTION[${#_SELECTION[@]} - 1]:-}" == "--files" ]]; then
          _SELECTION+=("$1")
        else
          echo "错误: 未知参数 '$1'" >&2
          return 2
        fi
        ;;
    esac
    shift
  done
  declare -a files=()
  mapfile -t files < <(select_files)
  if ((${#files[@]} == 0)); then
    echo "bench-tests: 无匹配用例，跳过"
    return 0
  fi
  local wall_start="${EPOCHREALTIME}"
  bats "${files[@]}" > /dev/null 2>&1 || rc=1
  local wall_ms
  wall_ms="$(elapsed_ms "$wall_start" "${EPOCHREALTIME}")"
  local platform id bver
  platform="$(env_detect_platform 2> /dev/null || echo unknown)"
  id="$(env_detect_id 2> /dev/null || echo unknown)"
  bver="$(env_bash_version 2> /dev/null || echo unknown)"
  local -a report=()
  report+=("# 测试基准报告" ""
    "- 生成时间: $(date '+%F %T')"
    "- 环境: platform=$platform id=$id bash=$bver"
    "- 范围: ${#files[@]} 个测试文件（$([ "$rc" -eq 0 ] && echo 全部通过 || echo 含失败)）"
    "- 全跑墙钟: ${wall_ms} ms" ""
    "| 测试文件 | 分时 (ms) |" "|---|---|")
  local f s e ms sum=0
  for f in "${files[@]}"; do
    s="${EPOCHREALTIME}"
    bats "$f" > /dev/null 2>&1 || true
    e="${EPOCHREALTIME}"
    ms="$(elapsed_ms "$s" "$e")"
    sum=$((sum + ms))
    report+=("| ${f#"$_ROOT/"} | $ms |")
  done
  report+=(""
    "- 说明: 分时合计 $sum ms > 全跑墙钟 ${wall_ms} ms 属正常（各文件独立启动开销）。")
  if [[ -n "$_SAVE" ]]; then
    if [[ -e "$_SAVE" ]]; then
      echo "错误: 报告文件已存在，拒绝覆盖: $_SAVE" >&2
      return 2
    fi
    printf '%s\n' "${report[@]}" > "$_SAVE"
    echo "bench-tests: 报告已写入 $_SAVE（全跑墙钟 ${wall_ms} ms）"
  else
    printf '%s\n' "${report[@]}"
  fi
  return "$rc"
}

main "$@"
