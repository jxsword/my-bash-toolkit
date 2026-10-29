#!/usr/bin/env bats
# script-name: bulk-rename-test
# description: bulk-rename 的 dry-run 计划、四种规则、冲突拒绝与错误分支测试
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats
# category: files

setup() {
  load '../helpers/test_env'
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04 git-bash
  load '../helpers/sandbox'
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/files/bulk-rename.sh"
}

teardown() {
  sandbox_teardown
}

@test "默认 dry-run 打印 mv 计划且不改动文件" {
  sandbox_setup
  printf 'a' > "$SANDBOX_DIR/a.txt"
  printf 'b' > "$SANDBOX_DIR/b.txt"
  run "$SCRIPT" -p p- "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"mv 'a.txt' -> 'p-a.txt'"* ]]
  [[ "$output" == *"mv 'b.txt' -> 'p-b.txt'"* ]]
  [ -f "$SANDBOX_DIR/a.txt" ]
  [ -f "$SANDBOX_DIR/b.txt" ]
  [ ! -e "$SANDBOX_DIR/p-a.txt" ]
}

@test "--apply 执行 --prefix/--suffix 重命名（扩展名保留）" {
  sandbox_setup
  printf 'a' > "$SANDBOX_DIR/a.txt"
  printf 'n' > "$SANDBOX_DIR/note.md"
  run "$SCRIPT" -p x- -s -old --apply "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [ ! -e "$SANDBOX_DIR/a.txt" ]
  [ "$(cat "$SANDBOX_DIR/x-a-old.txt")" = "a" ]
  [ "$(cat "$SANDBOX_DIR/x-note-old.md")" = "n" ]
  [[ "$output" == *"完成 2 条，失败 0 条，跳过 0 条"* ]]
}

@test "--start 序号模式按名称排序编号" {
  sandbox_setup
  printf '3' > "$SANDBOX_DIR/c.txt"
  printf '1' > "$SANDBOX_DIR/a.txt"
  printf '2' > "$SANDBOX_DIR/b.txt"
  run "$SCRIPT" -p n- --start 10 --apply "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [ "$(cat "$SANDBOX_DIR/n-10.txt")" = "1" ]
  [ "$(cat "$SANDBOX_DIR/n-11.txt")" = "2" ]
  [ "$(cat "$SANDBOX_DIR/n-12.txt")" = "3" ]
}

@test "--regex 无 g 标志只替换首次匹配" {
  sandbox_setup
  printf 'x' > "$SANDBOX_DIR/a-b-b.txt"
  run "$SCRIPT" -r 's/-/+/' --apply "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX_DIR/a+b-b.txt" ]
}

@test "--regex g 标志替换全部匹配" {
  sandbox_setup
  printf 'x' > "$SANDBOX_DIR/a-b-b.txt"
  run "$SCRIPT" -r 's/-/+/g' --apply "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX_DIR/a+b+b.txt" ]
}

@test "目标已存在的条目被拒绝且不覆盖" {
  sandbox_setup
  printf 'orig-b' > "$SANDBOX_DIR/b.txt"
  printf 'keep' > "$SANDBOX_DIR/p-b.txt"
  run "$SCRIPT" -p p- --apply "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"跳过: 目标已存在: 'b.txt' -> 'p-b.txt'"* ]]
  [ -f "$SANDBOX_DIR/b.txt" ]
  # p-b.txt 本身不被占用，改名为 p-p-b.txt，内容原样保留
  [ "$(cat "$SANDBOX_DIR/p-p-b.txt")" = "keep" ]
  [[ "$output" == *"跳过 1 条"* ]]
}

@test "批内目标冲突时第二条被拒绝" {
  sandbox_setup
  printf '1' > "$SANDBOX_DIR/q-1.txt"
  printf '2' > "$SANDBOX_DIR/q-2.txt"
  run "$SCRIPT" -r 's/-[0-9]//' --apply "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"跳过: 目标已存在: 'q-2.txt' -> 'q.txt'"* ]]
  [ -f "$SANDBOX_DIR/q.txt" ]
  [ "$(cat "$SANDBOX_DIR/q.txt")" = "1" ]
  [ -f "$SANDBOX_DIR/q-2.txt" ]
}

@test "规则前后名相同的文件不计入计划" {
  sandbox_setup
  printf 'a' > "$SANDBOX_DIR/a.txt"
  run "$SCRIPT" -r 's/zzz/qqq/' "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"没有需要重命名的文件"* ]]
  [ -f "$SANDBOX_DIR/a.txt" ]
}

@test "目录无普通文件时提示并退出 0" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/empty"
  run "$SCRIPT" -p p- "$SANDBOX_DIR/empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"没有可重命名的普通文件"* ]]
}

@test "子目录与符号链接不参与重命名" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/sub"
  printf 'x' > "$SANDBOX_DIR/real.txt"
  printf 'y' > "$SANDBOX_DIR/sub/inner.txt"
  if ! ln -s "$SANDBOX_DIR/real.txt" "$SANDBOX_DIR/link.txt"; then
    skip "当前环境无法创建符号链接"
  fi
  run "$SCRIPT" -p p- "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" != *"inner"* ]]
  [[ "$output" != *"'link.txt'"* ]]
  run "$SCRIPT" -p p- --apply "$SANDBOX_DIR"
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX_DIR/sub/inner.txt" ]
  [ -L "$SANDBOX_DIR/link.txt" ]
}

@test "目录不存在返回 1" {
  run "$SCRIPT" -p p- /nonexistent-bulk-rename-ghost-dir
  [ "$status" -eq 1 ]
}

@test "缺参数返回 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "未指定任何规则返回 2" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/d"
  run "$SCRIPT" "$SANDBOX_DIR/d"
  [ "$status" -eq 2 ]
  [[ "$output" == *"未指定任何重命名规则"* ]]
}

@test "未知选项返回 2" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
}

@test "--start 与 --regex 同时使用返回 2" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/d"
  run "$SCRIPT" --start 1 -r 's/a/b/' "$SANDBOX_DIR/d"
  [ "$status" -eq 2 ]
  [[ "$output" == *"不能同时使用"* ]]
}

@test "--start 非整数返回 2" {
  run "$SCRIPT" --start abc
  [ "$status" -eq 2 ]
}

@test "非法 --regex（缺结尾斜杠）返回 2" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/d"
  run "$SCRIPT" -r 's/a/b' "$SANDBOX_DIR/d"
  [ "$status" -eq 2 ]
  [[ "$output" == *"表达式非法"* ]]
}

@test "选项缺少参数返回 2" {
  run "$SCRIPT" -p
  [ "$status" -eq 2 ]
}

@test "help 正常退出 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--start"* ]]
  [[ "$output" == *"--apply"* ]]
}
