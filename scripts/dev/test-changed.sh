#!/usr/bin/env bash
# script-name: test-changed
# description: 变更 → 测试用例映射器——按变更文件计算需运行的 .bats 集合（含回退全量规则）
# usage: test-changed.sh [--run] [--staged] [--base <ref>] [--files <文件>...]
# option: --run    直接运行映射出的 bats 集合（缺省仅打印清单，每行一个文件）
# option: --staged    输入源=暂存区变更（git diff --cached）
# option: --base <ref>    输入源=<ref> 到 HEAD 的两点 diff（CI 多提交推送传 event.before）
# option: --files <文件>...    输入源=显式文件列表（pre-commit 传入；须在仓库根运行）
# example: scripts/dev/test-changed.sh --run --staged
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: git, bash
# category: dev
#
# 映射与回退规则（单一事实源，docs/PROJECT_CONTEXT.md §7 指向此处）：
#   scripts/<分类>/<名>.sh -> test/<分类>/<名>.bats（缺测试则 stderr 警告不阻断）
#   test/**/*.bats         -> 自身
#   rules_check_test/**    -> test/rules_check_test.bats
#   scripts/lib/**、hooks/**、.pre-commit-config.yaml、.shellcheckrc、
#   .bash-version、Makefile、run_tests.sh、本脚本 -> 回退全量
#   docs 等无用例文件 -> 忽略；混合批次任一回退项 -> 全量
# 注意：git 操作作用于调用方当前目录所在仓库（须在仓库根运行）。

set -u -o pipefail

_ROOT=""
_RUN="false"
_MODE="default"
_BASE=""
declare -a _FILES_ARGS=()

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 打印用法与映射规则
usage() {
  sed -n '3,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 规范化输入路径（去 ./ 前缀与仓库根前缀），输出仓库相对路径
norm_path() {
  local f="$1"
  f="${f#./}"
  f="${f#"$_ROOT/"}"
  printf '%s\n' "$f"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 收集输入源文件清单到全局 _INPUTS（按 --staged/--base/--files/缺省）
collect_inputs() {
  local f
  case "$_MODE" in
    staged)
      while IFS= read -r f; do
        [[ -n "$f" ]] && _INPUTS+=("$(norm_path "$f")")
      done < <(git diff --cached --name-only)
      ;;
    base)
      while IFS= read -r f; do
        [[ -n "$f" ]] && _INPUTS+=("$(norm_path "$f")")
      done < <(git diff --name-only "$_BASE" HEAD)
      ;;
    files) : ;; # _FILES_ARGS 已装填
    *)
      while IFS= read -r f; do
        [[ -n "$f" ]] && _INPUTS+=("$(norm_path "$f")")
      done < <(
        {
          git diff --cached --name-only
          git diff --name-only HEAD 2> /dev/null || true
          git ls-files --others --exclude-standard
        } | sort -u
      )
      ;;
  esac
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 映射单个变更文件；命中回退规则置 _FALLBACK，docs 等置 _IGNORED
map_one() {
  local f="$1" rel t
  case "$f" in
    scripts/lib/*)
      _FALLBACK="true"
      ;;
    scripts/dev/test-changed.sh)
      _FALLBACK="true"
      ;;
    hooks/* | .pre-commit-config.yaml | .shellcheckrc | .bash-version)
      _FALLBACK="true"
      ;;
    Makefile | run_tests.sh)
      _FALLBACK="true"
      ;;
    test/*.bats)
      _MAPPED+=("$_ROOT/$f")
      ;;
    rules_check_test/*)
      _MAPPED+=("$_ROOT/test/rules_check_test.bats")
      ;;
    scripts/*.sh)
      rel="${f#scripts/}"
      rel="${rel%.sh}"
      t="$_ROOT/test/${rel}.bats"
      if [[ -f "$t" ]]; then
        _MAPPED+=("$t")
      else
        echo "警告: 脚本缺测试（按 SOP 应有）: test/${rel}.bats" >&2
      fi
      ;;
    *)
      _IGNORED="true"
      ;;
  esac
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 对全部输入执行映射，产出 _MAPPED 集合与 _FALLBACK 标记
map_inputs() {
  _MAPPED=()
  _FALLBACK="false"
  _IGNORED="false"
  local f
  for f in "${_INPUTS[@]}"; do
    case "$f" in
      test/libs/*) : ;;
      *) map_one "$f" ;;
    esac
  done
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 入口——参数解析、输入收集、映射与输出/运行
main() {
  local rc=0
  while (($# > 0)); do
    case "$1" in
      --run) _RUN="true" ;;
      --staged) _MODE="staged" ;;
      --base)
        [[ $# -ge 2 ]] || {
          echo "错误: --base 需要参数" >&2
          return 2
        }
        _MODE="base"
        _BASE="$2"
        shift
        ;;
      --files) _MODE="files" ;;
      -h | --help)
        usage
        return 0
        ;;
      *)
        if [[ "$_MODE" == "files" ]]; then
          _FILES_ARGS+=("$1")
        else
          echo "错误: 未知参数 '$1'" >&2
          return 2
        fi
        ;;
    esac
    shift
  done
  _ROOT="$(git rev-parse --show-toplevel 2> /dev/null)" || {
    echo "错误: 当前目录不在 git 仓库内（须在目标仓库根运行）" >&2
    return 2
  }
  case "$_MODE" in
    base)
      git rev-parse --verify --quiet "$_BASE" > /dev/null \
        || git rev-parse --verify --quiet "$_BASE^{commit}" > /dev/null || {
        echo "错误: --base 引用不存在: $_BASE" >&2
        return 2
      }
      ;;
    files)
      if ((${#_FILES_ARGS[@]} == 0)); then
        echo "错误: --files 后未提供文件" >&2
        return 2
      fi
      ;;
  esac
  declare -a _INPUTS=()
  collect_inputs
  if [[ "$_MODE" == "files" ]]; then
    local f
    for f in "${_FILES_ARGS[@]}"; do
      _INPUTS+=("$(norm_path "$f")")
    done
  fi
  map_inputs
  if [[ "$_FALLBACK" == "true" ]]; then
    mapfile -t _MAPPED < <(
      source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/test_files.sh" \
        && collect_bats_files "$_ROOT"
    )
  fi
  if ((${#_MAPPED[@]} > 0)); then
    # 脚本与其测试文件同时变更时同一 .bats 会映射两次，去重
    mapfile -t _MAPPED < <(printf '%s\n' "${_MAPPED[@]}" | sort -u)
  fi
  if ((${#_MAPPED[@]} == 0)); then
    # 提示走 stderr：stdout 是文件清单流，供调用方（bench/make）安全消费
    echo "test-changed: 无匹配用例，跳过" >&2
    return 0
  fi
  if [[ "$_RUN" == "true" ]]; then
    bats "${_MAPPED[@]}" || rc=1
    return "$rc"
  fi
  local f
  for f in "${_MAPPED[@]}"; do
    printf '%s\n' "$f"
  done
}

main "$@"
