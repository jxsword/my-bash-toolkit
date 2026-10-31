#!/usr/bin/env bash
# script-name: run-tests
# description: 免 make 的全量测试入口（git bash 等 make 不可用环境使用）
# usage: run_tests.sh [--quiet] [--changed]
# option: --quiet    透传给 bash_env_check：预检只看退出码
# option: --changed    只运行与变更文件对应的用例（缺省全量）
# example: ./run_tests.sh
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats, bash
# category: dev

set -u -o pipefail

_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 入口——bash 版本预检后执行 bats 测试（全量或按变更定向）
main() {
  local pre=() changed="false"
  local arg
  for arg in "$@"; do
    case "$arg" in
      --quiet) pre+=(--quiet) ;;
      --changed) changed="true" ;;
      *)
        echo "run_tests: 未知参数 '$arg'（可用: --quiet --changed）" >&2
        return 2
        ;;
    esac
  done
  if ! "$_ROOT/scripts/lib/env.sh" "${pre[@]+"${pre[@]}"}"; then
    echo "run_tests: bash 环境预检未通过，终止" >&2
    return 1
  fi
  if ! command -v bats > /dev/null 2>&1; then
    echo "run_tests: 未找到 bats（安装方式见 README §4）" >&2
    return 2
  fi
  if [[ ! -e "$_ROOT/test/libs/bats-support/load.bash" ]]; then
    echo "run_tests: 提示——bats 助手库子模块未初始化，依赖它的用例将失败" >&2
    echo "  执行: git submodule update --init --recursive" >&2
  fi
  # shellcheck source=scripts/lib/test_files.sh
  source "$_ROOT/scripts/lib/test_files.sh"
  if [[ "$changed" == "true" ]]; then
    scripts/dev/test-changed.sh --run
    return "$?"
  fi
  local files=()
  mapfile -t files < <(collect_bats_files "$_ROOT")
  bats "${files[@]}"
}

main "$@"
