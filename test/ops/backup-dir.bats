#!/usr/bin/env bats
# script-name: backup-dir-test
# description: backup-dir 的 dry-run 计划、快照/恢复主路径与错误分支测试（[sandbox-only]）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: bats, tar
# category: ops

setup() {
  load '../helpers/test_env'
  # 可选组件条件加载：bats 的 setup 内 skip 不中断后续语句
  if env_is_supported ubuntu-26.04 wsl-ubuntu-26.04; then
    load '../../test/libs/bats-support/load'
    load '../../test/libs/bats-assert/load'
  fi
  # sandbox 先于 skip 加载，保证 teardown 中 sandbox_teardown 可用
  load '../helpers/sandbox'
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/ops/backup-dir.sh"
}

teardown() {
  sandbox_teardown
}

@test "无参数返回 2 并输出用法" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"用法: backup-dir.sh"* ]]
}

@test "help 退出 0 并展示关键选项" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dest"* ]]
  [[ "$output" == *"--keep"* ]]
  [[ "$output" == *"--apply"* ]]
}

@test "默认 dry-run 打印计划且不产生任何写入" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/src"
  printf 'x' > "$SANDBOX_DIR/src/f.txt"
  run "$SCRIPT" "$SANDBOX_DIR/src"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"tar czf"* ]]
  [[ "$output" == *"restore.sh"* ]]
  [[ "$output" == *"确认无误后加 --apply 执行"* ]]
  # 默认备份根 ~/backups（沙箱 HOME 下）未被创建，源目录原样
  [ ! -e "$SANDBOX_DIR/home/backups" ]
  [ -f "$SANDBOX_DIR/src/f.txt" ]
}

@test "dry-run 打印默认备份根与 --keep 计划" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/src"
  run "$SCRIPT" --keep 3 "$SANDBOX_DIR/src"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$SANDBOX_DIR/home/backups"* ]]
  [[ "$output" == *"保留最新 3 份 src-*.tar.gz"* ]]
  run "$SCRIPT" "$SANDBOX_DIR/src"
  [[ "$output" == *"未指定 --keep"* ]]
}

@test "--apply 生成快照与 restore.sh 且可恢复到原路径" {
  sandbox_setup
  local src="$SANDBOX_DIR/src" dest="$SANDBOX_DIR/backups" tarball cnt
  mkdir -p "$src"
  printf 'hello' > "$src/a.txt"
  run "$SCRIPT" --dest "$dest" --apply "$src"
  [ "$status" -eq 0 ]
  [[ "$output" == *"快照完成"* ]]
  cnt="$(find "$dest" -maxdepth 1 -name 'src-*.tar.gz' | wc -l)"
  [ "$cnt" -eq 1 ]
  tarball="$(printf '%s\n' "$dest"/src-*.tar.gz)"
  [ -s "$tarball" ]
  [ -x "$tarball.restore.sh" ]
  # -P 语义：tar 包内保留绝对路径成员（对齐 backup_restore 助手）
  tar tzf "$tarball" | grep -Fq "$src/a.txt"
  grep -q 'tar xzf' "$tarball.restore.sh"
  grep -q -- '-P' "$tarball.restore.sh"
  # 用 restore.sh 恢复：删源后恢复，内容一致
  rm -rf "$src"
  run bash "$tarball.restore.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$src/a.txt")" = "hello" ]
}

@test "--keep 2 滚动清理最旧快照及其恢复脚本" {
  sandbox_setup
  local src="$SANDBOX_DIR/src" dest="$SANDBOX_DIR/backups" cnt
  mkdir -p "$src" "$dest"
  printf 'x' > "$src/f.txt"
  : > "$dest/src-20260101-000001.tar.gz"
  : > "$dest/src-20260101-000002.tar.gz"
  : > "$dest/src-20260101-000003.tar.gz"
  : > "$dest/src-20260101-000002.tar.gz.restore.sh"
  : > "$dest/src-20260101-000003.tar.gz.restore.sh"
  run "$SCRIPT" --dest "$dest" --keep 2 --apply "$src"
  [ "$status" -eq 0 ]
  [[ "$output" == *"已清理旧快照"* ]]
  [ ! -e "$dest/src-20260101-000001.tar.gz" ]
  [ ! -e "$dest/src-20260101-000002.tar.gz" ]
  [ ! -e "$dest/src-20260101-000002.tar.gz.restore.sh" ]
  [ -e "$dest/src-20260101-000003.tar.gz" ]
  [ -e "$dest/src-20260101-000003.tar.gz.restore.sh" ]
  cnt="$(find "$dest" -maxdepth 1 -name 'src-*.tar.gz' | wc -l)"
  [ "$cnt" -eq 2 ]
}

@test "快照文件已存在时拒绝覆盖返回 1" {
  sandbox_setup
  local src="$SANDBOX_DIR/src" dest="$SANDBOX_DIR/backups"
  local ts tries=0 hit=0
  mkdir -p "$src" "$dest"
  printf 'x' > "$src/f.txt"
  while ((tries < 3 && hit == 0)); do
    tries=$((tries + 1))
    ts="$(date +%Y%m%d-%H%M%S)"
    : > "$dest/src-$ts.tar.gz"
    run "$SCRIPT" --dest "$dest" --apply "$src"
    if [[ "$output" == *"拒绝覆盖"* ]]; then
      hit=1
      break
    fi
  done
  [ "$hit" -eq 1 ]
  [ "$status" -eq 1 ]
}

@test "源目录不存在返回 1" {
  run "$SCRIPT" /nonexistent-backup-dir-ghost
  [ "$status" -eq 1 ]
  [[ "$output" == *"源目录不存在"* ]]
}

@test "拒绝备份根目录 /" {
  run "$SCRIPT" --apply /
  [ "$status" -eq 1 ]
  [[ "$output" == *"拒绝备份根目录"* ]]
}

@test "未知选项返回 2" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"未知选项"* ]]
}

@test "--keep 非法值返回 2" {
  run "$SCRIPT" --keep 0
  [ "$status" -eq 2 ]
  run "$SCRIPT" --keep abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"正整数"* ]]
}

@test "--keep 缺少参数返回 2" {
  run "$SCRIPT" --keep
  [ "$status" -eq 2 ]
}

@test "--dest 缺少参数返回 2" {
  run "$SCRIPT" --dest
  [ "$status" -eq 2 ]
}
