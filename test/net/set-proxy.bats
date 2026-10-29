#!/usr/bin/env bats
# script-name: set-proxy-test
# description: set-proxy 的 source/执行双模式、变量生效与参数校验测试
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats
# category: net
# bash -c 内的 $1/变量为延迟展开，单引号是有意为之：
# shellcheck disable=SC2016

setup() {
  load '../helpers/test_env'
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/net/set-proxy.sh"
}

@test "直接执行 on 打印 export 语句（宿主网关默认值）" {
  run "$SCRIPT" on
  [ "$status" -eq 0 ]
  [[ "$output" == *"export http_proxy='172.19.240.1:10808'"* ]]
  [[ "$output" == *"export all_proxy='socks5://172.19.240.1:10808'"* ]]
}

@test "直接执行 local 打印回环地址" {
  run "$SCRIPT" local
  [ "$status" -eq 0 ]
  [[ "$output" == *"127.0.0.1:10808"* ]]
}

@test "直接执行 off 打印 unset 语句" {
  run "$SCRIPT" off
  [ "$status" -eq 0 ]
  [[ "$output" == *"unset http_proxy https_proxy all_proxy"* ]]
}

@test "自定义地址覆盖默认值" {
  run "$SCRIPT" on '10.0.0.1:9999'
  [ "$status" -eq 0 ]
  [[ "$output" == *"export http_proxy='10.0.0.1:9999'"* ]]
}

@test "source on 在当前 shell 生效" {
  local cmd='source "$1" on 2> /dev/null'
  cmd+=' && printf "%s" "$http_proxy"'
  run bash -c "$cmd" _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "172.19.240.1:10808" ]
}

@test "source off 清除变量" {
  local cmd='export http_proxy=x; source "$1" off 2> /dev/null;'
  cmd+=' [[ -z "${http_proxy:-}" ]] && echo CLEARED'
  run bash -c "$cmd" _ "$SCRIPT"
  [ "$output" = "CLEARED" ]
}

@test "source 不污染调用方 shell 选项" {
  local cmd='set -u -o pipefail; source "$1" on 2> /dev/null;'
  cmd+=' [[ $- == *u* ]] && [[ -o pipefail ]] && echo CLEAN || echo DIRTY'
  run bash -c "$cmd" _ "$SCRIPT"
  [ "$output" = "CLEAN" ]
}

@test "未知子命令返回 2" {
  run "$SCRIPT" bogus
  [ "$status" -eq 2 ]
}

@test "非法地址返回 1" {
  run "$SCRIPT" on 'bad addr'
  [ "$status" -eq 1 ]
}
