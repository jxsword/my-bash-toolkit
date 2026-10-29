#!/usr/bin/env bats
# script-name: pkg-export-test
# description: pkg-export 的单元测试（[sandbox-only]，stub apt-mark 注入 PATH，不触真实包管理）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: bats
# category: system

setup() {
  load '../helpers/test_env'
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/system/pkg-export.sh"
  _PE_ORIG_PWD="$PWD"
  STUB_DIR="$BATS_TEST_TMPDIR/stub-bin"
  WORK_DIR="$BATS_TEST_TMPDIR/work"
  STUB_LIST_FILE="$BATS_TEST_TMPDIR/manual.txt"
  export STUB_LIST_FILE
  mkdir -p "$STUB_DIR" "$WORK_DIR"
}

teardown() {
  cd "$_PE_ORIG_PWD" || true
}

# 写入 stub apt-mark：输出 $STUB_LIST_FILE 内容并前置 PATH
install_stub() {
  cat > "$STUB_DIR/apt-mark" << 'STUB'
#!/usr/bin/env bash
cat "$STUB_LIST_FILE"
STUB
  chmod +x "$STUB_DIR/apt-mark"
  export PATH="$STUB_DIR:$PATH"
}

# 写入执行即失败的 stub apt-mark
install_failing_stub() {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB_DIR/apt-mark"
  chmod +x "$STUB_DIR/apt-mark"
  export PATH="$STUB_DIR:$PATH"
}

# 写入 fixture 清单（每参数一行）
write_list() {
  local p
  : > "$STUB_LIST_FILE"
  for p in "$@"; do
    printf '%s\n' "$p" >> "$STUB_LIST_FILE"
  done
}

@test "--help 退出 0 并含选项与退出码说明" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--out"* ]]
  [[ "$output" == *"--diff"* ]]
  [[ "$output" == *"xargs apt-get install"* ]]
}

@test "默认导出：当前目录生成时间戳清单并提示恢复命令" {
  install_stub
  write_list zebra apple banana
  pushd "$WORK_DIR" > /dev/null || return 1
  run "$SCRIPT"
  popd > /dev/null || return 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"已导出 3 个手动安装包"* ]]
  [[ "$output" == *"恢复命令提示: xargs apt-get install < "* ]]
  local f
  f="$(find "$WORK_DIR" -name 'pkg-manual-*.txt' -type f)"
  [[ -n "$f" ]]
}

@test "清单排序去重后落盘" {
  install_stub
  write_list zebra apple zebra banana
  pushd "$WORK_DIR" > /dev/null || return 1
  run "$SCRIPT"
  popd > /dev/null || return 1
  [ "$status" -eq 0 ]
  local f
  f="$(find "$WORK_DIR" -name 'pkg-manual-*.txt' -type f)"
  run cat "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == $'apple\nbanana\nzebra' ]]
}

@test "--out 写入指定文件" {
  install_stub
  write_list alpha beta
  local f="$WORK_DIR/out.txt"
  run "$SCRIPT" --out "$f"
  [ "$status" -eq 0 ]
  run cat "$f"
  [[ "$output" == $'alpha\nbeta' ]]
}

@test "--out 目标已存在时拒绝覆盖返回 3" {
  install_stub
  write_list alpha
  local f="$WORK_DIR/exists.txt"
  printf 'KEEP\n' > "$f"
  run "$SCRIPT" --out "$f"
  [ "$status" -eq 3 ]
  [[ "$output" == *"拒绝覆盖"* ]]
  run cat "$f"
  [[ "$output" == "KEEP" ]]
}

@test "--stdout 打印清单且不落盘" {
  install_stub
  write_list alpha beta
  pushd "$WORK_DIR" > /dev/null || return 1
  run "$SCRIPT" --stdout
  popd > /dev/null || return 1
  [ "$status" -eq 0 ]
  [[ "$output" == $'alpha\nbeta' ]]
  [[ -z "$(find "$WORK_DIR" -name 'pkg-manual-*.txt' -type f)" ]]
}

@test "空清单导出 0 个包且文件为空" {
  install_stub
  write_list
  pushd "$WORK_DIR" > /dev/null || return 1
  run "$SCRIPT"
  popd > /dev/null || return 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"已导出 0 个手动安装包"* ]]
  local f
  f="$(find "$WORK_DIR" -name 'pkg-manual-*.txt' -type f)"
  [[ ! -s "$f" ]]
}

@test "--diff 无差异返回 0 并输出一致结论" {
  install_stub
  write_list alpha beta gamma
  local old="$WORK_DIR/old.txt"
  printf '%s\n' alpha beta gamma > "$old"
  run "$SCRIPT" --diff "$old"
  [ "$status" -eq 0 ]
  [[ "$output" == *"无差异"* ]]
}

@test "--diff 有增有减返回 1 并列出 +/- 行" {
  install_stub
  write_list alpha beta gamma
  local old="$WORK_DIR/old.txt"
  printf '%s\n' alpha delta gamma > "$old"
  run "$SCRIPT" --diff "$old"
  [ "$status" -eq 1 ]
  [[ "$output" == *"  + beta"* ]]
  [[ "$output" == *"  - delta"* ]]
  [[ "$output" == *"xargs apt-get install"* ]]
}

@test "--diff 旧清单不可读返回 3" {
  install_stub
  write_list alpha
  run "$SCRIPT" --diff "$WORK_DIR/no-such.txt"
  [ "$status" -eq 3 ]
  [[ "$output" == *"不可读"* ]]
}

@test "apt-mark 不可用时返回 3 并给出明确错误" {
  write_list alpha
  # 最小 PATH：仅够启动脚本（env/bash/dirname），无 apt-mark
  local min="$BATS_TEST_TMPDIR/min-bin"
  mkdir -p "$min"
  ln -s "$(command -v env)" "$min/env"
  ln -s "$(command -v bash)" "$min/bash"
  ln -s "$(command -v dirname)" "$min/dirname"
  PATH="$min" run "$SCRIPT" --stdout
  [ "$status" -eq 3 ]
  [[ "$output" == *"apt-mark 不可用"* ]]
}

@test "apt-mark 执行失败时返回 3" {
  install_failing_stub
  write_list alpha
  run "$SCRIPT" --stdout
  [ "$status" -eq 3 ]
  [[ "$output" == *"apt-mark"* ]]
}

@test "未知选项返回 2" {
  install_stub
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"未知选项"* ]]
}

@test "--out 缺参数值返回 2" {
  install_stub
  run "$SCRIPT" --out
  [ "$status" -eq 2 ]
  [[ "$output" == *"--out 需要"* ]]
}

@test "--diff 缺参数值返回 2" {
  install_stub
  run "$SCRIPT" --diff
  [ "$status" -eq 2 ]
  [[ "$output" == *"--diff 需要"* ]]
}

@test "--diff 与 --out 同给返回 2" {
  install_stub
  run "$SCRIPT" --diff a.txt --out b.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *"互斥"* ]]
}

@test "--diff 与 --stdout 同给返回 2" {
  install_stub
  run "$SCRIPT" --diff a.txt --stdout
  [ "$status" -eq 2 ]
  [[ "$output" == *"互斥"* ]]
}
