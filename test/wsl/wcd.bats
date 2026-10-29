#!/usr/bin/env bats
# script-name: wcd-test
# description: wcd 的路径转换、source 切目录与参数校验测试（仅 WSL 环境）
# usage: （bats 测试，make test 触发）
# env: wsl-ubuntu-26.04
# deps: bats
# category: wsl
# bash -c 内的 $1/变量为延迟展开，单引号是有意为之：
# shellcheck disable=SC2016

setup() {
  load '../helpers/test_env'
  skip_unless_env wsl-ubuntu-26.04
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/wsl/wcd.sh"
}

@test "直接执行输出转换后的 WSL 路径（C:\\ → /mnt/c）" {
  run "$SCRIPT" "C:\\"
  [ "$status" -eq 0 ]
  [ "$output" = "/mnt/c" ]
}

@test "WSL 原生路径原样通过" {
  run "$SCRIPT" "$HOME"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME" ]
}

@test "source 切换当前目录" {
  local cmd='cd /tmp && source "$1" "$HOME" 2> /dev/null;'
  cmd+=' [[ "$PWD" == "$HOME" ]] && echo CD_OK'
  run bash -c "$cmd" _ "$SCRIPT"
  [ "$output" = "CD_OK" ]
}

@test "source 不污染调用方 shell 选项" {
  local cmd='set -u -o pipefail; source "$1" "$HOME" 2> /dev/null;'
  cmd+=' [[ $- == *u* ]] && [[ -o pipefail ]] && echo CLEAN || echo DIRTY'
  run bash -c "$cmd" _ "$SCRIPT"
  [ "$output" = "CLEAN" ]
}

@test "不存在的目录返回 1" {
  run "$SCRIPT" 'C:\no-such-dir-xyz'
  [ "$status" -eq 1 ]
}

@test "缺参数返回 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}
