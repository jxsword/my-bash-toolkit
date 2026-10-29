# script-name: bad-shebang-missing
# description: bad 用例——缺少 shebang（R01，check-metadata 应报错）
# usage: bad-shebang-missing.sh
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bash
# category: dev

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
main() {
  echo "no shebang above"
}

main
