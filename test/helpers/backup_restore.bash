#!/usr/bin/env bash
# script-name: backup-restore
# description: bats 测试助手——系统级脚本测试前的 tar 快照与自动恢复
# usage: （bats 助手，被 load；仅 [system-touch] 级测试使用）
# option: （函数）backup_paths <tar 包> <路径>...    快照指定路径（保留绝对路径）
# option: （函数）restore_paths <tar 包>             覆盖恢复原路径
# example: backup_paths "$SANDBOX_DIR/sudoers.tgz" /etc/sudoers
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: tar
# category: dev

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 将目标路径快照到 tar 包（-P 保留绝对路径）
backup_paths() {
  local tarball="$1"
  shift
  tar czf "$tarball" -P -- "$@"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 从 tar 包覆盖恢复原路径（-P 保留绝对路径）
restore_paths() {
  local tarball="$1"
  tar xzf "$tarball" -P
}
