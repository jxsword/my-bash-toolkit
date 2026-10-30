#!/usr/bin/env bats
# script-name: wsl-export-test
# description: wsl-export 的单元测试（[sandbox-only]；wsl.exe/df 全程 PATH 桩，绝不真实导出）
# usage: （bats 测试，make test 触发）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: bats
# category: wsl

# 真实 wsl -l -v 输出形态：UTF-16LE + BOM + CRLF + 表头 + * 标记 + 多空格列
DEFAULT_LIST=''
DEFAULT_LIST+=$'  NAME               STATE           VERSION\n'
DEFAULT_LIST+=$'* Ubuntu              Running         2\n'
DEFAULT_LIST+=$'  Debian              Stopped         2\n'
DEFAULT_LIST+=$'  openSUSE Leap 15    Stopped         2\n'

setup() {
  load '../helpers/test_env'
  # 可选组件条件加载：bats 的 setup 内 skip 不中断后续语句
  if env_is_supported ubuntu-26.04 wsl-ubuntu-26.04 git-bash; then
    load '../../test/libs/bats-support/load'
    load '../../test/libs/bats-assert/load'
  fi
  # 沙箱先建立，桩目录/参数日志/fixture 都放沙箱内
  load '../helpers/sandbox'
  skip_unless_env ubuntu-26.04 wsl-ubuntu-26.04 git-bash
  # 本文件 run 使用旗标形式（run ! / run env），声明最低版本消除 BW02 警告
  bats_require_minimum_version 1.5.0
  sandbox_setup
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/wsl/wsl-export.sh"
  ORIG_PATH="$PATH"
  STUB_DIR="$SANDBOX_DIR/stub-bin"
  STUB_LOG="$SANDBOX_DIR/stub-args.log"
  LIST_FILE="$SANDBOX_DIR/list.utf16"
  ERR_FILE="$SANDBOX_DIR/err.utf16"
  mkdir -p "$STUB_DIR"
  : > "$STUB_LOG"
  # 桩旋钮经 run env 逐次注入（不污染测试进程环境，无需重置）
  export WSE_STUB_LOG="$STUB_LOG"
  export WSE_STUB_LIST_FILE="$LIST_FILE"
  install_wsl_stub
  install_df_stub
  write_list_fixture
  # wsl.exe 桩前置 PATH：git-bash/WSL 真机上屏蔽真实 wsl.exe
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  # 恢复 PATH，保证 bats 清理临时目录（rm 等）始终可用
  if [[ -n "${ORIG_PATH:-}" ]]; then
    export PATH="$ORIG_PATH"
  fi
  sandbox_teardown
}

# 将 ASCII 文本编码为 UTF-16LE（含 BOM、CRLF），模拟 wsl.exe 真实输出
utf16le() {
  local text="$1" i ch
  printf '\xff\xfe'
  for ((i = 0; i < ${#text}; i++)); do
    ch="${text:i:1}"
    if [[ "$ch" == $'\n' ]]; then
      printf '\r\x00\n\x00'
    else
      printf '%s\x00' "$ch"
    fi
  done
}

write_list_fixture() {
  local text="${1:-$DEFAULT_LIST}"
  utf16le "$text" > "$LIST_FILE"
}

# 安装 wsl.exe 桩：调用参数记入 WSE_STUB_LOG；-l 按 fixture 输出 UTF-16LE；
# --export 按 WSE_STUB_EXPORT_* 旋钮生成非空/空/半成品文件或失败
install_wsl_stub() {
  cat > "$STUB_DIR/wsl.exe" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "wsl.exe $*" >> "${WSE_STUB_LOG:?}"
if [[ "${1:-}" == "-l" || "${1:-}" == "--list" ]]; then
  if [[ "${WSE_STUB_LIST_RC:-0}" != "0" && -n "${WSE_STUB_ERR_FILE:-}" ]]; then
    cat "$WSE_STUB_ERR_FILE" >&2
  fi
  cat "${WSE_STUB_LIST_FILE:-/dev/null}"
  exit "${WSE_STUB_LIST_RC:-0}"
fi
if [[ "${1:-}" == "--export" || "${1:-}" == "-export" ]]; then
  if [[ "${WSE_STUB_EXPORT_FAIL:-}" == "1" ]]; then
    cat "${WSE_STUB_ERR_FILE:-/dev/null}" >&2
    exit "${WSE_STUB_EXPORT_RC:-1}"
  fi
  if [[ "${WSE_STUB_EXPORT_PARTIAL:-}" == "1" ]]; then
    printf 'partial-tar' > "${3:-}"
    exit "${WSE_STUB_EXPORT_RC:-1}"
  fi
  if [[ "${WSE_STUB_EXPORT_EMPTY:-}" == "1" ]]; then
    : > "${3:-}"
    exit 0
  fi
  printf 'stub-tar-content\n' > "${3:-}" || exit 3
  exit 0
fi
exit 9
STUB
  chmod +x "$STUB_DIR/wsl.exe"
}

# 安装 df 桩：输出 df -P 固定格式，可用空间由 WSE_DF_AVAIL（KB）控制
install_df_stub() {
  cat > "$STUB_DIR/df" << 'STUB'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf 'stub-fs 999999999 999 %s 1%% /stub\n' "${WSE_DF_AVAIL:-999999000}"
STUB
  chmod +x "$STUB_DIR/df"
}

@test "无参数返回 2 并输出用法" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"用法: wsl-export.sh"* ]]
}

@test "--help 退出 0 并含关键选项与 Windows 侧说明" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dest"* ]]
  [[ "$output" == *"--manifest"* ]]
  [[ "$output" == *"--min-free"* ]]
  [[ "$output" == *"--apply"* ]]
  [[ "$output" == *"git-bash"* ]]
  [[ "$output" == *"UTF-16LE"* ]]
}

@test "--list 解码 UTF-16LE 输出并列出发行版（无表头无 BOM 残留）" {
  run "$SCRIPT" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ubuntu"* ]]
  [[ "$output" == *"Running"* ]]
  [[ "$output" == *"Debian"* ]]
  [[ "$output" == *"Stopped"* ]]
  [[ "$output" == *"openSUSE Leap 15"* ]]
  [[ "$output" != *"NAME"* ]]
  [[ "$output" != *$'\xff\xfe'* ]]
  grep -q -- '-l -v' "$STUB_LOG"
}

@test "--list 带位置参数返回 2" {
  run "$SCRIPT" --list Ubuntu
  [ "$status" -eq 2 ]
  [[ "$output" == *"--list 不接受位置参数"* ]]
}

@test "--list wsl -l -v 失败返回 1 并解码 UTF-16LE stderr" {
  utf16le $'\nExport list failed: simulated\r\n' > "$ERR_FILE"
  run env WSE_STUB_LIST_RC=1 WSE_STUB_ERR_FILE="$ERR_FILE" "$SCRIPT" --list
  [ "$status" -eq 1 ]
  [[ "$output" == *"wsl.exe -l -v 失败（退出码 1）"* ]]
  [[ "$output" == *"Export list failed: simulated"* ]]
}

@test "--list 输出无法解析（仅表头）返回 1" {
  write_list_fixture $'  NAME               STATE           VERSION\n'
  run "$SCRIPT" --list
  [ "$status" -eq 1 ]
  [[ "$output" == *"未能从 wsl -l -v 输出解析出任何发行版"* ]]
}

@test "默认 dry-run 打印计划且零写入（不导出不建目录）" {
  local dest="$SANDBOX_DIR/dest"
  run "$SCRIPT" --dest "$dest" Ubuntu
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"Running"* ]]
  [[ "$output" == *"WSL2"* ]]
  [[ "$output" == *"--export Ubuntu"* ]]
  [[ "$output" == *"$dest"* ]]
  [[ "$output" == *"wsl-export.log"* ]]
  [[ "$output" == *"剩余空间"* ]]
  [[ "$output" == *"--terminate"* ]]
  [[ "$output" == *"确认无误后加 --apply 执行"* ]]
  grep -q -- '-l -v' "$STUB_LOG"
  run ! grep -q -- '--export' "$STUB_LOG"
  [ ! -e "$dest" ]
}

@test "-n/--dry-run 显式指定与默认行为一致" {
  run "$SCRIPT" -n --dest "$SANDBOX_DIR/dest" Debian
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"Debian"* ]]
  run "$SCRIPT" --dry-run --dest "$SANDBOX_DIR/dest" Debian
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
}

@test "dry-run 空间不足仅告警退出 0" {
  run env WSE_DF_AVAIL=5 "$SCRIPT" --dest "$SANDBOX_DIR/dest" --min-free 1 \
    Ubuntu
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"不足"* ]]
  [ ! -e "$SANDBOX_DIR/dest" ]
}

@test "dry-run 未知发行版提示未找到退出 0" {
  run "$SCRIPT" --dest "$SANDBOX_DIR/dest" Ghost
  [ "$status" -eq 0 ]
  [[ "$output" == *"未在 wsl -l -v 中找到"* ]]
}

@test "--apply 主路径：--dest 自动命名 + manifest 记录正确" {
  local dest="$SANDBOX_DIR/dest" tarball log
  local mts mname mpath mbytes
  run "$SCRIPT" --dest "$dest" --min-free 1 --apply Debian
  [ "$status" -eq 0 ]
  [[ "$output" == *"导出完成"* ]]
  [[ "$output" == *"已追加记录"* ]]
  [ -d "$dest" ]
  tarball="$(printf '%s\n' "$dest"/Debian-*.tar)"
  [ -s "$tarball" ]
  log="$(cat "$STUB_LOG")"
  grep -q -- '--export Debian' "$STUB_LOG"
  [[ "$log" == *"$tarball"* ]]
  [ -f "$dest/wsl-export.log" ]
  IFS=$'\t' read -r mts mname mpath mbytes < "$dest/wsl-export.log"
  [[ "$mname" == "Debian" ]]
  [[ "$mpath" == "$tarball" ]]
  [[ "$mbytes" == "$(wc -c < "$tarball")" ]]
  [[ "$mts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "--apply 显式目标文件：父目录自动创建（含空格发行版名）" {
  local target="$SANDBOX_DIR/out/leap.tar"
  run "$SCRIPT" --apply "openSUSE Leap 15" "$target"
  [ "$status" -eq 0 ]
  [ -s "$target" ]
  grep -q -- '--export openSUSE Leap 15' "$STUB_LOG"
  [ -f "$SANDBOX_DIR/out/wsl-export.log" ]
  grep -q 'openSUSE Leap 15' "$SANDBOX_DIR/out/wsl-export.log"
}

@test "--apply --manifest 自定义路径生效（父目录自动创建）" {
  local m="$SANDBOX_DIR/records/my.log"
  run "$SCRIPT" --dest "$SANDBOX_DIR/dest" --manifest "$m" --apply Debian
  [ "$status" -eq 0 ]
  [ -f "$m" ]
  grep -q 'Debian' "$m"
}

@test "--apply Running 发行版拒绝并提示 wsl --terminate" {
  run "$SCRIPT" --dest "$SANDBOX_DIR/dest" --apply Ubuntu
  [ "$status" -eq 1 ]
  [[ "$output" == *"导出要求 Stopped"* ]]
  [[ "$output" == *"wsl --terminate Ubuntu"* ]]
  run ! grep -q -- '--export' "$STUB_LOG"
}

@test "--apply 未知发行版拒绝" {
  run "$SCRIPT" --dest "$SANDBOX_DIR/dest" --apply Ghost
  [ "$status" -eq 1 ]
  [[ "$output" == *"未在 wsl -l -v 中找到发行版: Ghost"* ]]
  run ! grep -q -- '--export' "$STUB_LOG"
}

@test "--apply 目标文件已存在拒绝覆盖" {
  local target="$SANDBOX_DIR/exists.tar"
  : > "$target"
  run "$SCRIPT" --apply Debian "$target"
  [ "$status" -eq 1 ]
  [[ "$output" == *"拒绝覆盖"* ]]
  run ! grep -q -- '--export' "$STUB_LOG"
}

@test "--apply 空间不足拒绝且不创建目录" {
  run env WSE_DF_AVAIL=5 "$SCRIPT" --dest "$SANDBOX_DIR/dest" --min-free 1 \
    --apply Debian
  [ "$status" -eq 1 ]
  [[ "$output" == *"剩余空间不足"* ]]
  run ! grep -q -- '--export' "$STUB_LOG"
  [ ! -e "$SANDBOX_DIR/dest" ]
}

@test "--apply wsl.exe --export 失败返回 1 并解码 UTF-16LE stderr" {
  utf16le $'\nExport failed: simulated\r\n' > "$ERR_FILE"
  run env WSE_STUB_EXPORT_FAIL=1 WSE_STUB_ERR_FILE="$ERR_FILE" \
    "$SCRIPT" --dest "$SANDBOX_DIR/dest" --apply Debian
  [ "$status" -eq 1 ]
  [[ "$output" == *"wsl.exe --export 失败（退出码 1）"* ]]
  [[ "$output" == *"Export failed: simulated"* ]]
}

@test "--apply 导出失败时清理残留文件" {
  run env WSE_STUB_EXPORT_PARTIAL=1 "$SCRIPT" --dest "$SANDBOX_DIR/dest" \
    --apply Debian
  [ "$status" -eq 1 ]
  [[ "$output" == *"已清理导出失败残留文件"* ]]
  [ -z "$(compgen -G "$SANDBOX_DIR/dest/Debian-*.tar")" ]
}

@test "--apply 导出文件为空时清理并返回 1" {
  run env WSE_STUB_EXPORT_EMPTY=1 "$SCRIPT" --dest "$SANDBOX_DIR/dest" \
    --apply Debian
  [ "$status" -eq 1 ]
  [[ "$output" == *"tar 文件为空"* ]]
  [ -z "$(compgen -G "$SANDBOX_DIR/dest/Debian-*.tar")" ]
}

@test "非 git-bash 平台输出告警，git-bash 平台不告警" {
  run "$SCRIPT" --list
  [ "$status" -eq 0 ]
  if [[ "$(env_detect_platform)" == "msys" ]]; then
    [[ "$output" != *"设计在 Windows 侧"* ]]
  else
    [[ "$output" == *"设计在 Windows 侧（git-bash）运行"* ]]
  fi
}

@test "未知选项返回 2" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"未知选项"* ]]
}

@test "--min-free 非法值或缺参数返回 2" {
  run "$SCRIPT" --min-free abc --dest "$SANDBOX_DIR/x" Ubuntu
  [ "$status" -eq 2 ]
  [[ "$output" == *"非负整数"* ]]
  run "$SCRIPT" --min-free
  [ "$status" -eq 2 ]
}

@test "--dest/--manifest 缺少参数返回 2" {
  run "$SCRIPT" --dest
  [ "$status" -eq 2 ]
  run "$SCRIPT" --manifest
  [ "$status" -eq 2 ]
}

@test "单个发行版参数缺少 --dest 返回 2" {
  run "$SCRIPT" Ubuntu
  [ "$status" -eq 2 ]
  [[ "$output" == *"缺少导出目标"* ]]
}

@test "--dest 与第二个位置参数（目标文件）冲突返回 2" {
  run "$SCRIPT" --dest "$SANDBOX_DIR/d" Debian "$SANDBOX_DIR/o.tar"
  [ "$status" -eq 2 ]
  [[ "$output" == *"不能同时使用"* ]]
}

@test "位置参数过多返回 2" {
  run "$SCRIPT" A B C
  [ "$status" -eq 2 ]
  [[ "$output" == *"位置参数过多"* ]]
}
