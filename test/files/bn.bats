#!/usr/bin/env bats
# script-name: bn-test
# description: bn 的备份重建、dry-run 与冲突校验测试
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats
# category: files

setup() {
  load '../helpers/test_env'
  load '../helpers/sandbox'
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/files/bn.sh"
}

teardown() {
  sandbox_teardown
}

@test "备份内容并新建空文件" {
  sandbox_setup
  printf 'content-v1\n' > "$SANDBOX_DIR/f.txt"
  run "$SCRIPT" "$SANDBOX_DIR/f.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$SANDBOX_DIR/f.txt.b")" = "content-v1" ]
  [ ! -s "$SANDBOX_DIR/f.txt" ]
}

@test "dry-run 不改动文件" {
  sandbox_setup
  printf 'content-v1\n' > "$SANDBOX_DIR/f.txt"
  run "$SCRIPT" --dry-run "$SANDBOX_DIR/f.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$SANDBOX_DIR/f.txt")" = "content-v1" ]
  [ ! -e "$SANDBOX_DIR/f.txt.b" ]
  [[ "$output" == *"[dry-run]"* ]]
}

@test "备份已存在返回 1 且不动原文件" {
  sandbox_setup
  printf 'new\n' > "$SANDBOX_DIR/f.txt"
  printf 'old\n' > "$SANDBOX_DIR/f.txt.b"
  run "$SCRIPT" "$SANDBOX_DIR/f.txt"
  [ "$status" -eq 1 ]
  [ "$(cat "$SANDBOX_DIR/f.txt")" = "new" ]
  [ "$(cat "$SANDBOX_DIR/f.txt.b")" = "old" ]
}

@test "文件不存在返回 1" {
  sandbox_setup
  run "$SCRIPT" "$SANDBOX_DIR/ghost.txt"
  [ "$status" -eq 1 ]
}

@test "缺参数返回 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}
