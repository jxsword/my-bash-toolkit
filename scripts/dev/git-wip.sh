#!/usr/bin/env bash
# script-name: git-wip
# description: 个人 git 助手——wip 快照提交、wip 历史列表与 wip 提交合并
# usage: git-wip.sh <wip [备注] | list [n] | squash [n] [-m 信息] [-f]>
# option: -m <信息>      squash 指定正式提交信息（省略则交互输入）
# option: -f, --force    squash 允许在 main 分支执行
# option: -h, --help     显示帮助
# example: git-wip.sh wip 修完解析边界
# example: git-wip.sh list 5
# example: git-wip.sh squash 3 -m "feat: 完成解析器"
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash, git, coreutils
# category: dev

set -u -o pipefail

_GW_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_GW_ROOT/scripts/lib/common.sh"

# wip 提交识别正则（git log --grep）与时间戳格式
readonly _GW_WIP_RE='^wip: '
readonly _GW_TS_FMT='%Y%m%d-%H%M%S'
readonly _GW_LIST_DEFAULT_N=10
readonly _GW_SQUASH_DEFAULT_N=2

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 打印用法到 stderr
usage() {
  echo "用法: git-wip.sh <子命令> [参数]" >&2
  echo "  wip [备注]   暂存全部改动并提交（提交信息: wip: 备注|时间戳）" >&2
  echo "  list [n]     列最近 n 个 wip 提交（默认 10）" >&2
  echo "  squash [n] [-m 信息] [-f]" >&2
  echo "               合并最近 n 个 wip 提交为一个正式提交（默认 2）" >&2
  echo "               main 分支默认拒绝，-f/--force 解除" >&2
  echo "选项: -h, --help 显示本帮助" >&2
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 校验当前目录位于 git 工作树内（bare 仓库视为不适用）
require_repo() {
  if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    log_err "当前目录不在 git 仓库工作树内，无法执行"
    return 1
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 校验参数为正整数
is_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: wip 子命令——add -A 并提交 wip: 备注|时间戳（无变更时跳过）
cmd_wip() {
  local note="$*"
  local ts msg
  ts="$(date +"$_GW_TS_FMT")"
  if [[ -n "$note" ]]; then
    msg="wip: ${note}|${ts}"
  else
    msg="wip: ${ts}"
  fi
  if [[ -z "$(git status --porcelain)" ]]; then
    log_info "工作区无变更，跳过提交"
    return 0
  fi
  if ! git add -A; then
    log_err "git add -A 失败"
    return 1
  fi
  if ! git commit -m "$msg"; then
    log_err "git commit 失败（改动已暂存，可手动检查后提交）"
    return 1
  fi
  log_info "已提交: $msg"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: list 子命令——列最近 n 个 wip 提交（短哈希 + 提交信息）
cmd_list() {
  local n="${1:-$_GW_LIST_DEFAULT_N}"
  if ! is_positive_int "$n"; then
    log_err "list 参数必须是正整数: $n"
    return 2
  fi
  local out
  out="$(git log -n "$n" --grep="$_GW_WIP_RE" --format='%h %s')"
  if [[ -z "$out" ]]; then
    log_info "没有 wip 提交"
    return 0
  fi
  printf '%s\n' "$out"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: squash 子命令——soft reset 合并最近 n 个连续 wip 提交为一个正式提交
cmd_squash() {
  local n="$_GW_SQUASH_DEFAULT_N" force="false" msg=""
  local -a pos=()
  while (($# > 0)); do
    case "$1" in
      -f | --force)
        force="true"
        shift
        ;;
      -m)
        if (($# < 2)); then
          log_err "-m 需要一个提交信息参数"
          return 2
        fi
        msg="$2"
        shift 2
        ;;
      -*)
        log_err "未知选项: $1"
        usage
        return 2
        ;;
      *)
        pos+=("$1")
        shift
        ;;
    esac
  done
  if ((${#pos[@]} > 1)); then
    usage
    return 2
  fi
  if ((${#pos[@]} == 1)); then
    n="${pos[0]}"
  fi
  if ! is_positive_int "$n"; then
    log_err "squash 参数必须是正整数: $n"
    return 2
  fi
  if ((n < 2)); then
    log_err "squash 至少需要合并 2 个 wip 提交（当前 n=$n）"
    return 1
  fi
  local branch
  branch="$(git branch --show-current)"
  if [[ "$branch" == "main" && "$force" != "true" ]]; then
    log_err "默认拒绝在 main 分支 squash（-f/--force 解除）"
    return 1
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    log_err "工作区有未提交改动，请先 wip 或 stash"
    return 1
  fi
  local -a hashes=() h
  while IFS= read -r h; do
    hashes+=("$h")
  done < <(git log -n "$n" --grep="$_GW_WIP_RE" --format='%H')
  if ((${#hashes[@]} < n)); then
    log_err "最近 wip 提交不足 $n 个（实际 ${#hashes[@]} 个）"
    return 1
  fi
  local oldest="${hashes[${#hashes[@]} - 1]}"
  if [[ "$(git rev-parse "HEAD~$((n - 1))")" != "$oldest" ]]; then
    log_err "最近 $n 个 wip 提交中间夹有其他提交（不连续），拒绝合并"
    return 1
  fi
  if [[ -z "$msg" ]]; then
    printf '请输入正式提交信息（空输入取消）: ' >&2
    read -r msg || msg=""
  fi
  if [[ -z "$msg" ]]; then
    log_err "提交信息为空，已取消 squash"
    return 1
  fi
  if ! git reset --soft "HEAD~$n"; then
    log_err "git reset --soft 失败"
    return 1
  fi
  if ! git commit -m "$msg"; then
    log_err "git commit 失败（改动已暂存，可手动检查后提交）"
    return 1
  fi
  log_info "已将 $n 个 wip 提交合并为: $msg"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 参数解析与子命令分派（非 git 目录统一报错）
main() {
  if (($# == 0)); then
    usage
    return 2
  fi
  local cmd="$1"
  shift
  case "$cmd" in
    -h | --help)
      usage
      return 0
      ;;
    wip)
      require_repo || return 1
      cmd_wip "$@"
      ;;
    list)
      require_repo || return 1
      cmd_list "$@"
      ;;
    squash)
      require_repo || return 1
      cmd_squash "$@"
      ;;
    *)
      usage
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
