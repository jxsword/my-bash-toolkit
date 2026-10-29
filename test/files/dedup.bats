#!/usr/bin/env bats
# script-name: dedup-test
# description: dedup 的列组、跳过规则与 --delete 交互删除测试
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats
# category: files

setup() {
  load '../helpers/test_env'
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04 git-bash
  load '../helpers/sandbox'
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/files/dedup.sh"
}

teardown() {
  sandbox_teardown
}

@test "默认列出重复组（跨子目录按内容识别）" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/sub"
  printf 'hello dedup world\n' > "$SANDBOX_DIR/a.txt"
  printf 'hello dedup world\n' > "$SANDBOX_DIR/sub/b.log"
  printf 'unique content here\n' > "$SANDBOX_DIR/u.txt"
  run "$SCRIPT" "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"重复组 1: 2 个文件"* ]]
  [[ "$output" == *"$SANDBOX_DIR/a.txt"* ]]
  [[ "$output" == *"$SANDBOX_DIR/sub/b.log"* ]]
  [[ "$output" != *"u.txt"* ]]
  [[ "$output" == *"共 1 组重复文件"* ]]
}

@test "无重复时输出未发现并退出 0" {
  sandbox_setup
  printf 'one\n' > "$SANDBOX_DIR/1.txt"
  printf 'two\n' > "$SANDBOX_DIR/2.txt"
  run "$SCRIPT" "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"未发现重复文件"* ]]
}

@test "大小相同内容不同不误报" {
  sandbox_setup
  printf 'aaaaaaaaaa\n' > "$SANDBOX_DIR/x.bin"
  printf 'bbbbbbbbbb\n' > "$SANDBOX_DIR/y.bin"
  run "$SCRIPT" "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"未发现重复文件"* ]]
}

@test "空文件被跳过" {
  sandbox_setup
  : > "$SANDBOX_DIR/empty.txt"
  printf 'dup\n' > "$SANDBOX_DIR/x.txt"
  printf 'dup\n' > "$SANDBOX_DIR/y.txt"
  run "$SCRIPT" "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"重复组 1: 2 个文件"* ]]
  [[ "$output" != *"empty.txt"* ]]
}

@test "符号链接被跳过" {
  sandbox_setup
  printf 'same content\n' > "$SANDBOX_DIR/real.txt"
  if ! ln -s "$SANDBOX_DIR/real.txt" "$SANDBOX_DIR/link.txt"; then
    skip "当前环境无法创建符号链接"
  fi
  run "$SCRIPT" "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"未发现重复文件"* ]]
}

@test "目录不存在返回 1" {
  run "$SCRIPT" /nonexistent-dedup-ghost-dir
  [ "$status" -eq 1 ]
}

@test "缺参数返回 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "未知选项返回 2" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
}

@test "help 正常退出 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--delete"* ]]
}

@test "--delete 输入 y 删除组内除第一个外的文件" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/sub"
  printf 'dup-content\n' > "$SANDBOX_DIR/a.txt"
  printf 'dup-content\n' > "$SANDBOX_DIR/sub/b.txt"
  printf 'keep\n' > "$SANDBOX_DIR/c.txt"
  local ans
  ans="$(mktemp)"
  printf 'y\n' > "$ans"
  run "$SCRIPT" --delete "$SANDBOX_DIR" < "$ans"
  rm -f "$ans"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX_DIR/a.txt" ]
  [ ! -e "$SANDBOX_DIR/sub/b.txt" ]
  [ "$(cat "$SANDBOX_DIR/a.txt")" = "dup-content" ]
  [ -f "$SANDBOX_DIR/c.txt" ]
  [[ "$output" == *"已删除: $SANDBOX_DIR/sub/b.txt"* ]]
  [[ "$output" == *"共删除 1 个文件"* ]]
}

@test "--delete 输入 n 跳过该组全部保留" {
  sandbox_setup
  printf 'dup-content\n' > "$SANDBOX_DIR/a.txt"
  printf 'dup-content\n' > "$SANDBOX_DIR/b.txt"
  local ans
  ans="$(mktemp)"
  printf 'n\n' > "$ans"
  run "$SCRIPT" --delete "$SANDBOX_DIR" < "$ans"
  rm -f "$ans"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX_DIR/a.txt" ]
  [ -f "$SANDBOX_DIR/b.txt" ]
  [[ "$output" == *"共删除 0 个文件"* ]]
}

@test "--delete 输入 q 立即取消后续组" {
  sandbox_setup
  printf 'AAAA\n' > "$SANDBOX_DIR/a1.txt"
  printf 'AAAA\n' > "$SANDBOX_DIR/a2.txt"
  printf 'BBBB\n' > "$SANDBOX_DIR/b1.txt"
  printf 'BBBB\n' > "$SANDBOX_DIR/b2.txt"
  local ans
  ans="$(mktemp)"
  printf 'y\nq\n' > "$ans"
  run "$SCRIPT" --delete "$SANDBOX_DIR" < "$ans"
  rm -f "$ans"
  [ "$status" -eq 0 ]
  [[ "$output" == *"已取消（未删除任何文件）"* ]]
  [ -f "$SANDBOX_DIR/a1.txt" ]
  [ -f "$SANDBOX_DIR/b1.txt" ]
  local left
  left="$(find "$SANDBOX_DIR" -type f | wc -l)"
  [ "$left" -eq 3 ]
}

@test "--delete 空输入（EOF）取消不删除" {
  sandbox_setup
  printf 'dup-content\n' > "$SANDBOX_DIR/a.txt"
  printf 'dup-content\n' > "$SANDBOX_DIR/b.txt"
  run "$SCRIPT" --delete "$SANDBOX_DIR" < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"已取消（未删除任何文件）"* ]]
  [ -f "$SANDBOX_DIR/a.txt" ]
  [ -f "$SANDBOX_DIR/b.txt" ]
  [[ "$output" == *"共删除 0 个文件"* ]]
}

@test "--delete 输入 a 自该组起全部删除（各组保留第一个）" {
  sandbox_setup
  printf 'AAAA\n' > "$SANDBOX_DIR/a1.txt"
  printf 'AAAA\n' > "$SANDBOX_DIR/a2.txt"
  printf 'BBBB\n' > "$SANDBOX_DIR/b1.txt"
  printf 'BBBB\n' > "$SANDBOX_DIR/b2.txt"
  local ans
  ans="$(mktemp)"
  printf 'a\n' > "$ans"
  run "$SCRIPT" --delete "$SANDBOX_DIR" < "$ans"
  rm -f "$ans"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX_DIR/a1.txt" ]
  [ ! -e "$SANDBOX_DIR/a2.txt" ]
  [ -f "$SANDBOX_DIR/b1.txt" ]
  [ ! -e "$SANDBOX_DIR/b2.txt" ]
  [[ "$output" == *"共删除 2 个文件"* ]]
}

@test "--delete 多组逐组输入 y" {
  sandbox_setup
  printf 'AAAA\n' > "$SANDBOX_DIR/a1.txt"
  printf 'AAAA\n' > "$SANDBOX_DIR/a2.txt"
  printf 'BBBB\n' > "$SANDBOX_DIR/b1.txt"
  printf 'BBBB\n' > "$SANDBOX_DIR/b2.txt"
  local ans
  ans="$(mktemp)"
  printf 'y\ny\n' > "$ans"
  run "$SCRIPT" --delete "$SANDBOX_DIR" < "$ans"
  rm -f "$ans"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX_DIR/a1.txt" ]
  [ ! -e "$SANDBOX_DIR/a2.txt" ]
  [ -f "$SANDBOX_DIR/b1.txt" ]
  [ ! -e "$SANDBOX_DIR/b2.txt" ]
  [[ "$output" == *"共删除 2 个文件"* ]]
}
