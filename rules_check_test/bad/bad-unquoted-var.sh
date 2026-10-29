#!/usr/bin/env bash
# script-name: bad-unquoted-var
# description: bad 用例——变量未加引号（R04，shellcheck SC2086；值来自运行时参数）
# usage: bad-unquoted-var.sh <模式串>
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash
# category: dev

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
main() {
  local pattern="$1"
  grep $pattern /etc/hostname >/dev/null
}

main "$@"
