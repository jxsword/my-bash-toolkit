#!/usr/bin/env bash
# script-name: good-basic
# description: good 用例——完整元数据、readonly 常量、local 变量与正确引号
# usage: good-basic.sh [名字]
# option: -h, --help    显示本帮助
# example: good-basic.sh world
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash
# category: dev

readonly _GREETING_PREFIX="你好"

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 打印问候语
greet() {
  local name="${1:-world}"
  echo "${_GREETING_PREFIX}, ${name}!"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 入口
main() {
  greet "$@"
}

main "$@"
