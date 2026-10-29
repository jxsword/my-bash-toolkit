#!/usr/bin/env bash
# script-name: bad-read-nor
# description: bad 用例——read 缺少 -r（R06，shellcheck SC2162）
# usage: bad-read-nor.sh
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash
# category: dev

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
main() {
  local line
  read line
  echo "$line"
}

main
