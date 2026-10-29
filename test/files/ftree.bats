#!/usr/bin/env bats
# script-name: ftree-test
# description: ftree 的 -F 增强、-C 补齐与 F 字母误匹配修复测试
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: bats, tree
# category: files

setup() {
  load '../helpers/test_env'
  load '../helpers/sandbox'
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/files/ftree.sh"
}

teardown() {
  sandbox_teardown
}

# bats 文件内助手：剥离 ANSI 着色（tree -C 强制着色会打断子串断言）
strip_ansi() {
  sed $'s/\x1b\\[[0-9;]*m//g'
}

@test "无 -F 时原样透传（无着色）" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/a/b"
  touch "$SANDBOX_DIR/a/f.txt"
  run "$SCRIPT" "$SANDBOX_DIR/a"
  [ "$status" -eq 0 ]
  [[ "$output" == *"b"* ]]
  if grep -q $'\x1b' <<< "$output"; then
    flunk "非 -F 模式不应出现着色输出"
  fi
}

@test "含 -F 时自动补 -C 且过滤行尾星号" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/a/b"
  touch "$SANDBOX_DIR/a/f.txt"
  run "$SCRIPT" -F "$SANDBOX_DIR/a"
  [ "$status" -eq 0 ]
  local clean
  clean="$(strip_ansi <<< "$output")"
  [[ "$clean" == *"b/"* ]]
  if grep -q '\*$' <<< "$clean"; then
    flunk "行尾星号未被过滤"
  fi
}

@test "-F 与 -C 同时给出时不重复添加" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/a/b"
  run "$SCRIPT" -F -C "$SANDBOX_DIR/a"
  [ "$status" -eq 0 ]
  local clean
  clean="$(strip_ansi <<< "$output")"
  [[ "$clean" == *"b/"* ]]
}

@test "路径含字母 F 不误触发 -F 逻辑" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/aF"
  touch "$SANDBOX_DIR/aF/x"
  chmod +x "$SANDBOX_DIR/aF/x"
  run "$SCRIPT" "$SANDBOX_DIR/aF"
  [ "$status" -eq 0 ]
  if grep -q $'\x1b' <<< "$output"; then
    flunk "路径含字母 F 误触发了 -F 增强"
  fi
}

@test "缺少 tree 命令返回 1" {
  run env PATH="/nonexistent" /bin/bash "$SCRIPT" -F .
  [ "$status" -eq 1 ]
}
