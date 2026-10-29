#!/usr/bin/env bash
# script-name: bad-long-line
# description: bad 用例——超过 80 列的行（R03，line-length hook 应报错）
# usage: bad-long-line.sh
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash
# category: dev

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
main() {
  echo "this line is intentionally longer than eighty columns so the line-length hook will flag it"
}

main
