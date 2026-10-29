#!/usr/bin/env bash
# script-name: bad-missing-env-annotation
# description: bad 用例——函数缺 # env: 标注（R10，check-metadata 应报错）
# usage: bad-missing-env-annotation.sh
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash
# category: dev

main() {
  echo "function without env annotation"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
helper() {
  main
}

main
