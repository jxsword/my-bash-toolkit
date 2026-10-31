#!/usr/bin/env bats
# script-name: bench-tests-test
# description: bench-tests 的报告生成、--save 保护与范围选择测试
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats
# category: dev

setup() {
  load '../helpers/test_env'
  load '../helpers/sandbox'
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/dev/bench-tests.sh"
}

teardown() {
  sandbox_teardown
}

@test "--files 单文件产出双列 markdown 报告与环境头" {
  run "$SCRIPT" --files test/lib/env.bats < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"# 测试基准报告"* ]]
  [[ "$output" == *"platform="* ]]
  [[ "$output" == *"全跑墙钟"* ]]
  [[ "$output" == *"test/lib/env.bats"* ]]
}

@test "--save 落盘且 stdout 只出摘要" {
  local out_file
  out_file="$(mktemp)"
  rm -f "$out_file"
  run "$SCRIPT" --files test/lib/env.bats --save "$out_file" < /dev/null
  [ "$status" -eq 0 ]
  [ -f "$out_file" ]
  [[ "$(cat "$out_file")" == *"# 测试基准报告"* ]]
  [[ "$output" == *"报告已写入"* ]]
  rm -f "$out_file"
}

@test "--save 已存在拒绝覆盖" {
  local out_file
  out_file="$(mktemp)"
  run "$SCRIPT" --files test/lib/env.bats --save "$out_file" < /dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"拒绝覆盖"* ]]
  rm -f "$out_file"
}

@test "--staged 透传 test-changed 在沙箱仓库运行" {
  sandbox_setup
  git -C "$SANDBOX_DIR" init < /dev/null > /dev/null 2>&1
  git -C "$SANDBOX_DIR" config user.name t
  git -C "$SANDBOX_DIR" config user.email t@t
  mkdir -p "$SANDBOX_DIR/scripts/net" "$SANDBOX_DIR/test/net"
  touch "$SANDBOX_DIR/scripts/net/x.sh"
  printf '@test "ok" { true; }\n' > "$SANDBOX_DIR/test/net/x.bats"
  git -C "$SANDBOX_DIR" add -A
  run bash -c \
    "cd '$SANDBOX_DIR' && '$SCRIPT' --staged < /dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"x.bats"* ]]
}

@test "--files 仅 docs 变更时跳过" {
  sandbox_setup
  git -C "$SANDBOX_DIR" init < /dev/null > /dev/null 2>&1
  git -C "$SANDBOX_DIR" config user.name t
  git -C "$SANDBOX_DIR" config user.email t@t
  mkdir -p "$SANDBOX_DIR/docs"
  touch "$SANDBOX_DIR/docs/a.md"
  run bash -c "cd '$SANDBOX_DIR' && '$SCRIPT' --files docs/a.md < /dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"无匹配用例，跳过"* ]]
}

@test "未知参数返回 2" {
  run "$SCRIPT" --bogus < /dev/null
  [ "$status" -eq 2 ]
}
