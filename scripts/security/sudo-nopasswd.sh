#!/usr/bin/env bash
# script-name: sudo-nopasswd
# description: 开启/恢复指定用户的 sudo 免密（写入 /etc/sudoers.d/<user>-nopasswd）
# usage: sudo-nopasswd <on|off|status> [用户名] [--dry-run]
# option: -n, --dry-run    仅打印将执行的动作，不修改系统（on/off 模式生效）
# example: sudo-nopasswd status
# example: sudo-nopasswd on ssy --dry-run
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: sudo, coreutils
# category: security

set -u -o pipefail

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 打印用法到 stderr
usage() {
  echo "用法: sudo-nopasswd <on|off|status> [用户名] [--dry-run]" >&2
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 校验用户名合法、存在且属于 sudo/wheel 组
validate_user() {
  local user="$1"
  if ! [[ "$user" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
    echo "错误: 用户名 '$user' 格式非法" >&2
    return 1
  fi
  if ! id "$user" > /dev/null 2>&1; then
    echo "错误: 用户 '$user' 不存在" >&2
    return 1
  fi
  if ! id -nG "$user" | grep -Eq '(^| )(sudo|wheel)( |$)'; then
    echo "错误: 用户 '$user' 不属于 sudo/wheel 组" >&2
    return 1
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 校验 /etc/sudoers 已启用 sudoers.d 包含目录
check_includedir() {
  if ! sudo grep -q '^#includedir.*sudoers\.d' /etc/sudoers; then
    echo "警告: /etc/sudoers 未包含 #includedir /etc/sudoers.d，配置不会生效" >&2
    return 1
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 开启免密（幂等；dry-run 仅打印将执行的动作）
enable_nopasswd() {
  local user="$1" dry="$2" sudoers_file tmp_file
  sudoers_file="/etc/sudoers.d/${user}-nopasswd"
  if [[ -f "$sudoers_file" ]] \
    && sudo grep -q 'NOPASSWD: ALL' "$sudoers_file"; then
    echo "提示: $user 已是免密状态"
    return 0
  fi
  if [[ "$dry" == "true" ]]; then
    echo "[dry-run] 将写入 $sudoers_file:"
    echo "[dry-run]   $user ALL=(ALL) NOPASSWD: ALL"
    return 0
  fi
  check_includedir || return 1
  tmp_file="${sudoers_file}.tmp"
  echo "$user ALL=(ALL) NOPASSWD: ALL" \
    | sudo tee "$tmp_file" > /dev/null || return 1
  sudo chmod 440 "$tmp_file"
  if sudo visudo -c -f "$tmp_file" > /dev/null 2>&1; then
    sudo mv "$tmp_file" "$sudoers_file"
    echo "已为 $user 开启 sudo 免密"
  else
    echo "错误: visudo 语法校验失败，配置已回滚" >&2
    sudo rm -f "$tmp_file"
    return 1
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 恢复密码验证（dry-run 仅打印将执行的动作）
disable_nopasswd() {
  local user="$1" dry="$2" sudoers_file
  sudoers_file="/etc/sudoers.d/${user}-nopasswd"
  if [[ ! -f "$sudoers_file" ]]; then
    echo "提示: $user 无免密配置，无需恢复"
    return 0
  fi
  if [[ "$dry" == "true" ]]; then
    echo "[dry-run] 将删除 $sudoers_file"
    return 0
  fi
  sudo rm -f "$sudoers_file"
  echo "已为 $user 恢复 sudo 密码验证"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 查看当前免密状态
show_status() {
  local user="$1" sudoers_file
  sudoers_file="/etc/sudoers.d/${user}-nopasswd"
  if [[ -f "$sudoers_file" ]] \
    && sudo grep -q 'NOPASSWD: ALL' "$sudoers_file"; then
    echo "$user: 免密已开启 ($sudoers_file)"
  else
    echo "$user: 正常密码验证"
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 参数解析与入口分派
main() {
  local mode="${1:-}"
  shift || true
  local user="" arg dry="false"
  if [[ $# -gt 0 && "$1" != -* ]]; then
    user="$1"
    shift
  fi
  for arg in "$@"; do
    case "$arg" in
      -n | --dry-run) dry="true" ;;
      *)
        usage
        return 2
        ;;
    esac
  done
  case "$mode" in
    on | off | status) ;;
    *)
      usage
      return 2
      ;;
  esac
  user="${user:-$(id -un)}"
  validate_user "$user" || return 1
  case "$mode" in
    on) enable_nopasswd "$user" "$dry" ;;
    off) disable_nopasswd "$user" "$dry" ;;
    status) show_status "$user" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
