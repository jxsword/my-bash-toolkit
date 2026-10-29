#!/usr/bin/env bash
# script-name: bad-backticks
# description: bad 用例——反引号命令替换（R05，shellcheck SC2006）
# usage: bad-backticks.sh
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash
# category: dev

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
main() {
  local d
  d=`pwd`
  echo "$d"
}

main
