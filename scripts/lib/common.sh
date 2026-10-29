#!/usr/bin/env bash
# script-name: common
# description: 通用日志函数库（被 source，零副作用）
# usage: （库，被 source）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash
# category: lib

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 信息日志（stdout）
log_info() {
  printf '[info] %s\n' "$*"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 错误日志（stderr）
log_err() {
  printf '[错误] %s\n' "$*" >&2
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 警告日志（stderr）
log_warn() {
  printf '[警告] %s\n' "$*" >&2
}
