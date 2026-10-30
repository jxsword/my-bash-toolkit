#!/usr/bin/env bats
# script-name: perm-audit-test
# description: perm-audit 的沙箱审计主路径、ssh 私钥与错误分支测试（[sandbox-only]）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: bats, findutils, coreutils
# category: security

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
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/security/perm-audit.sh"
}

teardown() {
  sandbox_teardown
}

@test "help 退出 0 并展示选项与退出码语义" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--path"* ]]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"0=无发现"* ]]
  [[ "$output" == *"1=有发现"* ]]
}

@test "无参数按默认目录扫描并给出摘要" {
  sandbox_setup
  run "$SCRIPT"
  # 真实 /etc /usr/local 的发现项因环境而异，退出码 0/1 均合法
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
  [[ "$output" == *"扫描目录: /etc /usr/local"* ]]
  [[ "$output" == *"只读权限巡检"* ]]
}

@test "沙箱树审计：ww 文件与目录、粘滞位标注、干净文件不报" {
  sandbox_setup
  local tree="$SANDBOX_DIR/tree"
  mkdir -p "$tree/wwdir" "$tree/stickydir"
  printf 'x' > "$tree/wwfile.txt"
  chmod 666 "$tree/wwfile.txt"
  printf 'x' > "$tree/okfile.txt"
  chmod 644 "$tree/okfile.txt"
  chmod 777 "$tree/wwdir"
  chmod 1777 "$tree/stickydir"
  run "$SCRIPT" --path "$tree"
  [ "$status" -eq 1 ]
  [[ "$output" == *"world-writable 文件 (1)"* ]]
  [[ "$output" == *"666  $tree/wwfile.txt"* ]]
  [[ "$output" == *"world-writable 目录 (2)"* ]]
  [[ "$output" == *"777  $tree/wwdir（无粘滞位）"* ]]
  [[ "$output" == *"1777  $tree/stickydir"* ]]
  # 已含粘滞位的目录不追加标注
  [[ "$output" != *"stickydir（无粘滞位）"* ]]
  # 权限正常的文件不出现
  [[ "$output" != *"$tree/okfile.txt"* ]]
  [[ "$output" == *"共发现 3 项权限问题"* ]]
}

@test "干净目录返回 0 且 ~/.ssh 不存在时提示跳过" {
  sandbox_setup
  mkdir -p "$SANDBOX_DIR/clean"
  run "$SCRIPT" --path "$SANDBOX_DIR/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"未发现权限问题"* ]]
  [[ "$output" == *"不存在，跳过"* ]]
}

@test "ssh 私钥：非 600 报告、600 与排除名单不报、内容识别兜底" {
  sandbox_setup
  local ssh="$SANDBOX_DIR/home/.ssh" scan="$SANDBOX_DIR/scan"
  mkdir -p "$ssh" "$scan"
  printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n' > "$ssh/id_rsa"
  chmod 644 "$ssh/id_rsa"
  printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n' > "$ssh/id_ed25519"
  chmod 600 "$ssh/id_ed25519"
  printf 'ssh-rsa AAAA x' > "$ssh/id_rsa.pub"
  chmod 644 "$ssh/id_rsa.pub"
  printf 'y' > "$ssh/known_hosts"
  printf 'z' > "$ssh/authorized_keys"
  printf 'w' > "$ssh/config"
  printf 'garbage' > "$ssh/notakey.txt"
  chmod 644 "$ssh/notakey.txt"
  # 非标准名但内容含 PRIVATE KEY，靠内容识别兜底
  printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nq\n' > "$ssh/backup.pem"
  chmod 664 "$ssh/backup.pem"
  run "$SCRIPT" --path "$scan"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ssh 私钥检查: $ssh"* ]]
  [[ "$output" == *"ssh 私钥权限非 600 (2)"* ]]
  [[ "$output" == *"644  $ssh/id_rsa"* ]]
  [[ "$output" == *"664  $ssh/backup.pem"* ]]
  [[ "$output" != *id_ed25519* ]]
  [[ "$output" != *known_hosts* ]]
  [[ "$output" != *authorized_keys* ]]
  [[ "$output" != *notakey* ]]
}

@test "多个 --path 目录都被扫描" {
  sandbox_setup
  local d1="$SANDBOX_DIR/a" d2="$SANDBOX_DIR/b"
  mkdir -p "$d1" "$d2"
  printf 'x' > "$d1/ww1.txt"
  chmod 666 "$d1/ww1.txt"
  printf 'x' > "$d2/ww2.txt"
  chmod 666 "$d2/ww2.txt"
  run "$SCRIPT" --path "$d1" --path "$d2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"扫描目录: $d1 $d2"* ]]
  [[ "$output" == *"$d1/ww1.txt"* ]]
  [[ "$output" == *"$d2/ww2.txt"* ]]
  [[ "$output" == *"共发现 2 项权限问题"* ]]
}

@test "--path 全部无效时逐条告警并返回 2" {
  sandbox_setup
  run "$SCRIPT" --path /nope-perm-audit-a --path /nope-perm-audit-b
  [ "$status" -eq 2 ]
  [[ "$output" == *"跳过无效目录"*"/nope-perm-audit-a"* ]]
  [[ "$output" == *"跳过无效目录"*"/nope-perm-audit-b"* ]]
  [[ "$output" == *"没有可扫描的有效目录"* ]]
}

@test "--path 指向普通文件视为无效目录" {
  sandbox_setup
  local f="$SANDBOX_DIR/afile"
  printf 'x' > "$f"
  run "$SCRIPT" --path "$f"
  [ "$status" -eq 2 ]
  [[ "$output" == *"跳过无效目录"* ]]
}

@test "混合有效与无效 --path 仍扫描有效目录" {
  sandbox_setup
  local tree="$SANDBOX_DIR/tree"
  mkdir -p "$tree"
  printf 'x' > "$tree/ww.txt"
  chmod 666 "$tree/ww.txt"
  run "$SCRIPT" --path /nope-perm-audit-c --path "$tree"
  [ "$status" -eq 1 ]
  [[ "$output" == *"跳过无效目录"* ]]
  [[ "$output" == *"666  $tree/ww.txt"* ]]
}

@test "未知选项返回 2" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"未知选项"* ]]
}

@test "--path 缺少参数返回 2" {
  run "$SCRIPT" --path
  [ "$status" -eq 2 ]
  [[ "$output" == *"--path 缺少目录参数"* ]]
}

@test "位置参数被拒绝返回 2" {
  run "$SCRIPT" /tmp
  [ "$status" -eq 2 ]
  [[ "$output" == *"不接受位置参数"* ]]
}

@test "-n/--dry-run 与默认行为一致（只读无副作用）" {
  sandbox_setup
  local tree="$SANDBOX_DIR/tree"
  mkdir -p "$tree"
  run "$SCRIPT" -n --path "$tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"未发现权限问题"* ]]
}

@test "假 find 桩驱动无主/无组分支（沙箱无 root 无法真实构造）" {
  sandbox_setup
  local stub="$SANDBOX_DIR/stubbin" tree="$SANDBOX_DIR/tree"
  local fake="$tree/fake"
  mkdir -p "$stub" "$fake"
  printf 'x' > "$tree/wwfile.txt"
  chmod 666 "$tree/wwfile.txt"
  # 注: 无主文件需 root chown 才能在沙箱真实构造，此处用 PATH 注入假 find
  #     桩伪造 -nouser/-nogroup 查询结果，其余 find 调用转发真实二进制。
  REAL_FIND="$(command -v find)"
  export REAL_FIND
  FAKE_UNOWNED_DIR="$fake"
  export FAKE_UNOWNED_DIR
  cat > "$stub/find" << 'EOF'
#!/usr/bin/env bash
# 测试桩 find: 仅伪造 -nouser/-nogroup 查询输出，其余转发真实 find
if [[ "$*" == *-nouser* ]]; then
  printf '%s\t%s\n' '2755' "$FAKE_UNOWNED_DIR/orphan-file"
  printf '%s\t%s\n' '2777' "$FAKE_UNOWNED_DIR/orphan-dir"
  exit 0
fi
exec "$REAL_FIND" "$@"
EOF
  chmod +x "$stub/find"
  PATH="$stub:$PATH" run "$SCRIPT" --path "$tree"
  [ "$status" -eq 1 ]
  [[ "$output" == *"无主/无组 (2)"* ]]
  [[ "$output" == *"2755  $fake/orphan-file"* ]]
  [[ "$output" == *"2777  $fake/orphan-dir"* ]]
  # 桩不干扰 world-writable 真实分支
  [[ "$output" == *"world-writable 文件 (1)"* ]]
  [[ "$output" == *"666  $tree/wwfile.txt"* ]]
  [[ "$output" == *"共发现 3 项权限问题"* ]]
}

@test "不可读子目录计入警告且其余发现正常输出" {
  sandbox_setup
  local tree="$SANDBOX_DIR/tree"
  mkdir -p "$tree/locked/sub"
  printf 'x' > "$tree/wwfile.txt"
  chmod 666 "$tree/wwfile.txt"
  chmod 000 "$tree/locked"
  run "$SCRIPT" --path "$tree"
  # 立即恢复权限，保证沙箱可清理
  chmod 700 "$tree/locked"
  [ "$status" -eq 1 ]
  [[ "$output" == *"无法读取"* ]]
  [[ "$output" == *"world-writable 文件 (1)"* ]]
  [[ "$output" == *"666  $tree/wwfile.txt"* ]]
}
