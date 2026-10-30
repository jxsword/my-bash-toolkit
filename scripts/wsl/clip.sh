#!/usr/bin/env bash
# script-name: clip
# description: WSL↔Windows 剪贴板——stdin 经 clip.exe 复制，Get-Clipboard 粘贴
# usage: clip.sh [-c, --copy | -p, --paste] [-h, --help]
# option: -c, --copy    复制模式：把 stdin 写入 Windows 剪贴板（clip.exe）
# option: -p, --paste   粘贴模式：输出 Windows 剪贴板内容（Get-Clipboard）
# option: -h, --help    显示帮助
# example: echo hello | clip.sh
# example: clip.sh --paste > pasted.txt
# env: wsl-ubuntu-26.04
# deps: clip.exe, powershell.exe
# category: wsl

set -u -o pipefail

_CLIP_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_CLIP_ROOT/scripts/lib/common.sh"

# env: wsl-ubuntu-26.04
# fn: 打印用法到 stdout
usage() {
  cat << 'EOF'
用法: clip.sh [-c, --copy | -p, --paste] [-h, --help]
WSL ↔ Windows 剪贴板互通（依赖 WSL interop）.

模式:
  复制  stdin 为管道/重定向时自动选择（或显式 --copy）:
          echo hello | clip.sh      # 文本送入 Windows 剪贴板
  粘贴  无参数且 stdin 为终端时自动选择（或显式 --paste）:
          clip.sh > pasted.txt      # 剪贴板内容输出到 stdout

选项:
  -c, --copy    复制模式：把 stdin 写入 Windows 剪贴板（clip.exe）
  -p, --paste   粘贴模式：输出 Windows 剪贴板内容（Get-Clipboard）
  -h, --help    显示本帮助

interop 不可用（找不到 clip.exe/powershell.exe）时退出 1,
并给出 /etc/wsl.conf 的 [interop] 段开启指引.

退出码: 0=成功 1=interop 不可用或执行失败 2=用法错误
EOF
}

# env: wsl-ubuntu-26.04
# fn: 校验指定 exe 可用；不可用时输出 wsl.conf interop 开启指引并返回 1
require_exe() {
  local exe="$1"
  if command -v "$exe" > /dev/null 2>&1; then
    return 0
  fi
  log_err "未找到 $exe —— WSL interop 不可用或未追加 Windows PATH"
  echo "指引: 检查 /etc/wsl.conf 的 [interop] 段，两行均为 true 才可用:" >&2
  echo "    [interop]" >&2
  echo "    enabled=true            # 允许 WSL 运行 Windows 可执行文件" >&2
  echo "    appendWindowsPath=true  # 将 Windows PATH 追加进 \$PATH" >&2
  echo "指引: 修改后需重启 WSL 生效——在 PowerShell 执行 wsl --shutdown 后重开" >&2
  return 1
}

# env: wsl-ubuntu-26.04
# fn: 复制模式——stdin 原样流经 clip.exe 写入 Windows 剪贴板
do_copy() {
  require_exe clip.exe || return 1
  local rc=0
  clip.exe || rc=$?
  if ((rc != 0)); then
    log_err "clip.exe 执行失败（退出码 $rc）"
    return 1
  fi
  return 0
}

# env: wsl-ubuntu-26.04
# fn: 粘贴模式——powershell.exe Get-Clipboard 输出剪贴板内容到 stdout
do_paste() {
  require_exe powershell.exe || return 1
  local rc=0
  powershell.exe -NoProfile -NonInteractive -Command \
    '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-Clipboard' \
    || rc=$?
  if ((rc != 0)); then
    log_err "powershell.exe 执行失败（退出码 $rc）"
    return 1
  fi
  return 0
}

# env: wsl-ubuntu-26.04
# fn: 参数解析、模式自动判定（stdin 是否终端）与分派
main() {
  local mode="auto"
  while (($#)); do
    case "$1" in
      -c | --copy)
        if [[ "$mode" == "paste" ]]; then
          log_err "--copy 与 --paste 互斥，不能同时使用"
          return 2
        fi
        mode="copy"
        shift
        ;;
      -p | --paste)
        if [[ "$mode" == "copy" ]]; then
          log_err "--copy 与 --paste 互斥，不能同时使用"
          return 2
        fi
        mode="paste"
        shift
        ;;
      -h | --help)
        usage
        return 0
        ;;
      *)
        log_err "未知选项或参数: $1"
        usage >&2
        return 2
        ;;
    esac
  done
  if [[ "$mode" == "auto" ]]; then
    if [[ -t 0 ]]; then
      mode="paste"
    else
      mode="copy"
    fi
  fi
  if [[ "$mode" == "copy" ]]; then
    do_copy
    return $?
  fi
  do_paste
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
