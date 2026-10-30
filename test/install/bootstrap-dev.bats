#!/usr/bin/env bats
# script-name: bootstrap-dev-test
# description: bootstrap-dev 的单元测试（[sandbox-only]，PATH 桩 apt-get/sudo，绝不真实安装）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: bats
# category: install

setup() {
  load '../helpers/test_env'
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/install/bootstrap-dev.sh"
  BIN="$BATS_TEST_TMPDIR/bin-$BATS_TEST_NUMBER"
  LOG="$BATS_TEST_TMPDIR/apt-$BATS_TEST_NUMBER.log"
  export BD_APT_LOG="$LOG"
}

# 构造最小 PATH 环境: 运行必需工具（env/bash/dirname 符号链接，勿 chmod）+
# 指定「已安装」的工具桩 + 记录调用的 apt-get/sudo 桩；$@ = 视为已装的工具名
# 桩「安装」的工具写入 $BIN 自身（在 PATH 内），供复检 command -v 找到
fake_env() {
  rm -rf "$BIN"
  mkdir -p "$BIN"
  ln -s "$(command -v env)" "$BIN/env"
  ln -s "$(command -v bash)" "$BIN/bash"
  ln -s "$(command -v dirname)" "$BIN/dirname"
  local t
  for t in "$@"; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/$t"
    chmod +x "$BIN/$t"
  done
  cat > "$BIN/apt-get" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BD_APT_LOG"
if [[ "${BD_APT_FAIL:-0}" == "1" ]]; then
  exit 70
fi
if [[ "${1:-}" == "install" ]]; then
  shift
  [[ "${1:-}" == "-y" ]] && shift
  if [[ -n "${BD_INSTALL_DIR:-}" ]]; then
    for p in "$@"; do
      printf '#!/usr/bin/env bash\nexit 0\n' > "$BD_INSTALL_DIR/$p"
      /bin/chmod +x "$BD_INSTALL_DIR/$p"
    done
  fi
fi
exit 0
STUB
  chmod +x "$BIN/apt-get"
  cat > "$BIN/sudo" << 'STUB'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$BD_APT_LOG"
while [[ "${1:-}" == -* ]]; do
  shift
done
"$@"
STUB
  chmod +x "$BIN/sudo"
  BD_INSTALL_DIR="$BIN"
  export BD_INSTALL_DIR
  : > "$LOG"
}

# apt-get 不可用场景: 仅保留运行必需工具，无 apt-get/sudo 桩
minimal_env() {
  rm -rf "$BIN"
  mkdir -p "$BIN"
  ln -s "$(command -v env)" "$BIN/env"
  ln -s "$(command -v bash)" "$BIN/bash"
  ln -s "$(command -v dirname)" "$BIN/dirname"
}

@test "无参数返回 2 并输出用法" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"用法: bootstrap-dev.sh"* ]]
}

@test "help 退出 0 并展示选项、档位与 zcode-run 提权说明" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--profile"* ]]
  [[ "$output" == *"--apply"* ]]
  [[ "$output" == *"--sudo"* ]]
  [[ "$output" == *"--update"* ]]
  [[ "$output" == *"zcode-run"* ]]
  [[ "$output" == *"sudo -n"* ]]
  [[ "$output" == *"python3-pip"* ]]
}

@test "--profile 缺参数返回 2" {
  run "$SCRIPT" --profile
  [ "$status" -eq 2 ]
  [[ "$output" == *"--profile 需要"* ]]
}

@test "--profile 非法档位返回 2" {
  run "$SCRIPT" --profile all
  [ "$status" -eq 2 ]
  [[ "$output" == *"min 或 dev"* ]]
}

@test "未知选项返回 2" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"未知选项"* ]]
}

@test "不接受位置参数返回 2" {
  run "$SCRIPT" --profile min extra
  [ "$status" -eq 2 ]
  [[ "$output" == *"未知选项或多余参数: extra"* ]]
}

@test "min 档全缺失: dry-run 打印计划且不调用 apt-get" {
  fake_env
  PATH="$BIN" run "$SCRIPT" --profile min
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"共 2 个工具"* ]]
  [[ "$output" == *"已安装 0 个"* ]]
  [[ "$output" == *"- git -> apt 包: git"* ]]
  [[ "$output" == *"- curl -> apt 包: curl"* ]]
  [[ "$output" == *"apt-get install -y git curl"* ]]
  [[ "$output" == *"sudo -n"* ]]
  [[ "$output" == *"确认无误后加 --apply 执行"* ]]
  [ ! -s "$LOG" ]
}

@test "dev 档部分已装: dry-run 仅列缺失（pip3 映射 python3-pip）" {
  fake_env git curl make
  PATH="$BIN" run "$SCRIPT" --profile dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"共 7 个工具"* ]]
  [[ "$output" == *"已安装 3 个: git curl make"* ]]
  [[ "$output" == *"缺失 4 个"* ]]
  [[ "$output" == *"- bats -> apt 包: bats"* ]]
  [[ "$output" == *"- shfmt -> apt 包: shfmt"* ]]
  [[ "$output" == *"- shellcheck -> apt 包: shellcheck"* ]]
  [[ "$output" == *"- pip3 -> apt 包: python3-pip"* ]]
  [[ "$output" == *"apt-get install -y bats shfmt shellcheck python3-pip"* ]]
  [[ "$output" != *"git -> apt 包"* ]]
  [ ! -s "$LOG" ]
}

@test "dev 档全缺失: dry-run 列出全部 7 个工具" {
  fake_env
  PATH="$BIN" run "$SCRIPT" --profile dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"缺失 7 个"* ]]
  local t
  for t in git curl make bats shfmt shellcheck pip3; do
    [[ "$output" == *"- $t -> apt 包"* ]]
  done
  [ ! -s "$LOG" ]
}

@test "全部已装: dry-run 提示无需安装且无安装命令行" {
  fake_env git curl make bats shfmt shellcheck pip3
  PATH="$BIN" run "$SCRIPT" --profile dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"已安装 7 个"* ]]
  [[ "$output" == *"全部已安装，无需安装"* ]]
  [[ "$output" != *"apt-get install"* ]]
  [ ! -s "$LOG" ]
}

@test "-n/--dry-run 与默认行为一致" {
  fake_env
  PATH="$BIN" run "$SCRIPT" -n --profile min
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [ ! -s "$LOG" ]
  PATH="$BIN" run "$SCRIPT" --dry-run --profile min
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [ ! -s "$LOG" ]
}

@test "apply 主路径: 桩 apt-get 收到 install -y 且复检通过" {
  fake_env
  PATH="$BIN" run "$SCRIPT" --profile min --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"apt-get install -y git curl"* ]]
  [[ "$output" == *"复检通过"* ]]
  [ -x "$BIN/git" ]
  [ -x "$BIN/curl" ]
  run cat "$LOG"
  [[ "$output" == *"install -y git curl"* ]]
  [[ "$output" != *"update"* ]]
  [[ "$output" != *"sudo"* ]]
}

@test "apply 幂等: 全部已装时不调用 apt-get" {
  fake_env git curl
  PATH="$BIN" run "$SCRIPT" --profile min --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"无需安装（幂等无操作）"* ]]
  [ ! -s "$LOG" ]
}

@test "apply 安装失败返回 1" {
  fake_env
  BD_APT_FAIL=1 PATH="$BIN" run "$SCRIPT" --profile min --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"apt-get install 失败"* ]]
}

@test "apply 复检仍缺失返回 1" {
  fake_env
  BD_INSTALL_DIR="" PATH="$BIN" run "$SCRIPT" --profile min --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"复检仍缺失: git"* ]]
  [[ "$output" == *"复检仍缺失: curl"* ]]
  [[ "$output" == *"复检仍有 2 个工具不可用"* ]]
}

@test "--sudo 时以 sudo -n 前缀调用 apt-get" {
  fake_env
  PATH="$BIN" run "$SCRIPT" --profile min --apply --sudo
  [ "$status" -eq 0 ]
  run cat "$LOG"
  [[ "$output" == *"sudo -n apt-get install -y git curl"* ]]
  [[ "$output" == *"install -y git curl"* ]]
}

@test "--update 时先 update 再 install（apply）" {
  fake_env
  PATH="$BIN" run "$SCRIPT" --profile min --apply --update
  [ "$status" -eq 0 ]
  run cat "$LOG"
  [[ "$output" == $'update\ninstall -y git curl' ]]
}

@test "--update 在 dry-run 中仅打印不执行" {
  fake_env
  PATH="$BIN" run "$SCRIPT" --profile min --update
  [ "$status" -eq 0 ]
  [[ "$output" == *"将执行: apt-get update"* ]]
  [[ "$output" == *"[dry-run]"* ]]
  [ ! -s "$LOG" ]
}

@test "非 root 且无 --sudo 时 apply 打印提权警告但继续" {
  if [[ "$EUID" -eq 0 ]]; then
    skip "以 root 运行，非 root 警告用例不适用"
  fi
  fake_env
  PATH="$BIN" run "$SCRIPT" --profile min --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"[警告] 当前非 root 且未加 --sudo"* ]]
  [[ "$output" == *"zcode-run + sudo -n"* ]]
}

@test "apply 时 apt-get 不可用返回 1" {
  minimal_env
  PATH="$BIN" run "$SCRIPT" --profile dev --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"apt-get 不可用"* ]]
}
