#!/usr/bin/env bats
# script-name: clip-test
# description: clip 的单元测试（[sandbox-only]，PATH 桩驱动双向路径与 interop 缺失）
# usage: （bats 测试，make test 触发）
# env: wsl-ubuntu-26.04
# deps: bats
# category: wsl

setup() {
  load '../helpers/test_env'
  skip_unless_env wsl-ubuntu-26.04
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/wsl/clip.sh"
  ORIG_PATH="$PATH"
  STUB_DIR="$BATS_TEST_TMPDIR/stub-bin"
  MIN_DIR="$BATS_TEST_TMPDIR/min-bin"
  STUB_LOG="$BATS_TEST_TMPDIR/stub-args.log"
  STUB_OUT="$BATS_TEST_TMPDIR/stub-out"
  export STUB_LOG STUB_OUT
  mkdir -p "$STUB_DIR" "$MIN_DIR"
  : > "$STUB_LOG"
  rm -f "$STUB_OUT"
}

teardown() {
  # 恢复 PATH，保证 bats 清理临时目录（rm 等）始终可用
  if [[ -n "${ORIG_PATH:-}" ]]; then
    export PATH="$ORIG_PATH"
  fi
  return 0
}

# 重置桩状态（参数日志与输出文件）
reset_stub() {
  : > "$STUB_LOG"
  rm -f "$STUB_OUT"
}

# 安装 clip.exe 桩：stdin 原样落盘到 $STUB_OUT，调用行记入 $STUB_LOG
install_clip_stub() {
  local exit_code="${1:-0}"
  cat > "$STUB_DIR/clip.exe" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "clip.exe $*" >> "$STUB_LOG"
cat > "$STUB_OUT"
STUB
  printf 'exit %s\n' "$exit_code" >> "$STUB_DIR/clip.exe"
  chmod +x "$STUB_DIR/clip.exe"
}

# 安装 powershell.exe 成功桩：模拟 Get-Clipboard，输出 $STUB_CONTENT
install_pwsh_stub() {
  local content="${1:-clipboard-text}"
  cat > "$STUB_DIR/powershell.exe" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
printf '%s\n' "$STUB_CONTENT"
exit 0
STUB
  chmod +x "$STUB_DIR/powershell.exe"
  STUB_CONTENT="$content"
  export STUB_CONTENT
}

# 安装 powershell.exe 失败桩：stderr 输出标记后以 7 退出
install_pwsh_fail_stub() {
  cat > "$STUB_DIR/powershell.exe" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
echo 'powershell-fail-marker' >&2
exit 7
STUB
  chmod +x "$STUB_DIR/powershell.exe"
}

# 桩目录前置 PATH
use_stub_path() {
  export PATH="$STUB_DIR:$PATH"
}

# 组装最小 PATH 目录（仅 env/bash/dirname），供 PATH="$MIN_DIR" 前缀式调用：
# 模拟 interop 不可用（exe 探测失败），不污染本测试进程 PATH
use_min_path() {
  ln -sf "$(command -v env)" "$MIN_DIR/env"
  ln -sf "$(command -v bash)" "$MIN_DIR/bash"
  ln -sf "$(command -v dirname)" "$MIN_DIR/dirname"
}

@test "--help 退出 0 并含模式、选项与退出码说明" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *'用法: clip.sh'* ]]
  [[ "$output" == *'--copy'* ]]
  [[ "$output" == *'--paste'* ]]
  [[ "$output" == *'退出码: 0=成功 1=interop 不可用或执行失败 2=用法错误'* ]]
}

@test "管道 stdin 自动复制：stdin 字节原样送达 clip.exe 桩" {
  install_clip_stub
  use_stub_path
  local in="$BATS_TEST_TMPDIR/in.txt"
  printf 'line1\nline2\n' > "$in"
  run "$SCRIPT" < "$in"
  [ "$status" -eq 0 ]
  cmp -s "$in" "$STUB_OUT"
  local log
  log="$(cat "$STUB_LOG")"
  [[ "$log" == 'clip.exe'* ]]
  [[ "$log" != *'powershell.exe'* ]]
}

@test "显式 --copy 与 stdin 重定向同样送达 clip.exe 桩" {
  install_clip_stub
  use_stub_path
  local in="$BATS_TEST_TMPDIR/in2.txt"
  printf 'explicit-copy-content\n' > "$in"
  run "$SCRIPT" --copy < "$in"
  [ "$status" -eq 0 ]
  cmp -s "$in" "$STUB_OUT"
}

@test "无 stdin（非终端）自动复制：空内容成功且不调用 powershell" {
  install_clip_stub
  install_pwsh_stub
  use_stub_path
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ -f "$STUB_OUT" && ! -s "$STUB_OUT" ]]
  local log
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *'clip.exe'* ]]
  [[ "$log" != *'powershell.exe'* ]]
}

@test "--paste 输出剪贴板内容并按预期参数调用 powershell.exe" {
  install_pwsh_stub 'pasted-内容-123'
  use_stub_path
  run "$SCRIPT" --paste
  [ "$status" -eq 0 ]
  [[ "$output" == 'pasted-内容-123' ]]
  local log
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *'-NoProfile'* ]]
  [[ "$log" == *'-NonInteractive'* ]]
  [[ "$log" == *'Get-Clipboard'* ]]
}

@test "短选项 -p 显式粘贴优先于管道 stdin" {
  install_pwsh_stub 'explicit-flag-wins'
  use_stub_path
  run "$SCRIPT" -p < <(printf 'ignored-piped-input')
  [ "$status" -eq 0 ]
  [[ "$output" == 'explicit-flag-wins' ]]
}

@test "clip.exe 桩执行失败：退出 1 并报执行失败" {
  install_clip_stub 7
  use_stub_path
  run "$SCRIPT" -c < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *'clip.exe 执行失败（退出码 7）'* ]]
}

@test "powershell.exe 桩执行失败：退出 1 并报执行失败" {
  install_pwsh_fail_stub
  use_stub_path
  run "$SCRIPT" --paste
  [ "$status" -eq 1 ]
  [[ "$output" == *'powershell.exe 执行失败（退出码 7）'* ]]
  [[ "$output" == *'powershell-fail-marker'* ]]
}

@test "interop 不可用（复制模式）：退出 1 并给出 wsl.conf 指引" {
  use_min_path
  PATH="$MIN_DIR" run "$SCRIPT" --copy < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *'未找到 clip.exe'* ]]
  [[ "$output" == *'[interop]'* ]]
  [[ "$output" == *'enabled=true'* ]]
  [[ "$output" == *'appendWindowsPath=true'* ]]
  [[ "$output" == *'wsl --shutdown'* ]]
}

@test "interop 不可用（粘贴模式）：退出 1 并给出 wsl.conf 指引" {
  use_min_path
  PATH="$MIN_DIR" run "$SCRIPT" --paste
  [ "$status" -eq 1 ]
  [[ "$output" == *'未找到 powershell.exe'* ]]
  [[ "$output" == *'[interop]'* ]]
  [[ "$output" == *'wsl --shutdown'* ]]
}

@test "未知选项退出 2 并输出用法" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *'未知选项或参数'* ]]
  [[ "$output" == *'用法: clip.sh'* ]]
}

@test "位置参数被拒绝退出 2" {
  run "$SCRIPT" somefile.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *'未知选项或参数'* ]]
}

@test "-c 与 -p 同给退出 2（互斥）" {
  run "$SCRIPT" -c -p
  [ "$status" -eq 2 ]
  [[ "$output" == *'互斥'* ]]
  run "$SCRIPT" --paste --copy
  [ "$status" -eq 2 ]
  [[ "$output" == *'互斥'* ]]
}
