#!/usr/bin/env bash
# script-name: wsl-export
# description: 包装 wsl.exe --export 导出 WSL 发行版 tar——列表/空间/非空校验并追加记录（默认 dry-run）
# usage: wsl-export.sh [--list | <发行版> --dest <目录> | <发行版> <目标tar>] [--apply]
# option: --list           仅列出已注册发行版（解码 wsl -l -v 的 UTF-16LE 输出）
# option: --dest <dir>     导出目录（与第二个位置参数二选一，文件名自动 <发行版>-<时间戳>.tar）
# option: --manifest <f>   记录清单路径（默认 <导出目录>/wsl-export.log，成功后追加一行）
# option: --min-free <GB>  目标盘最小剩余空间（GiB，默认 10，0 表示不校验）
# option: --apply          执行导出（缺省为 dry-run，仅打印计划）
# option: -n, --dry-run    仅打印计划，不执行导出（与缺省一致）
# option: -h, --help       显示帮助
# example: wsl-export.sh --list
# example: wsl-export.sh Ubuntu --dest D:/wsl-backup --apply
# env: git-bash
# deps: wsl.exe, iconv, coreutils
# category: wsl

set -u -o pipefail

_WSE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_WSE_ROOT/scripts/lib/common.sh"

# shellcheck source=../lib/env.sh
source "$_WSE_ROOT/scripts/lib/env.sh"

# env: git-bash
# fn: 打印用法到 stdout（错误分支重定向到 stderr）
usage() {
  cat << 'EOF'
用法: wsl-export.sh [--list | <发行版> --dest <目录> | <发行版> <目标tar>]
                    [--manifest <文件>] [--min-free <GB>] [--apply] [-h]

在 Windows 侧（git-bash）运行，包装 wsl.exe --export 导出指定发行版:
解析 wsl -l -v 列发行版 → 校验目标盘剩余空间 → 导出 → 校验 tar 非空
→ 追加一行记录到清单文件。默认 dry-run 仅打印计划，--apply 才执行。

模式:
  --list                    仅列出已注册发行版（名称/状态/版本）
  <发行版> --dest <目录>    导出到 <目录>/<发行版>-<时间戳>.tar
  <发行版> <目标tar>        导出到指定文件（两个位置参数）

选项:
  --dest <dir>      导出目录（与第二个位置参数二选一）
  --manifest <f>    记录清单路径（默认 <导出目录>/wsl-export.log）
  --min-free <GB>   目标盘最小剩余空间（GiB，默认 10，0 表示不校验）
  --apply           执行导出（缺省为 dry-run）
  -n, --dry-run     仅打印计划，不执行（与缺省一致）
  -h, --help        显示本帮助

注意:
  - 必须在 Windows 侧 git-bash 运行；路径写 D:/dir 或 /d/dir（正斜杠）
  - 导出要求发行版处于 Stopped 状态（否则提示先 wsl --terminate）
  - 无法预知导出体积，空间校验按 --min-free 阈值执行
  - 记录行格式: <ISO时间>\t<发行版>\t<tar路径>\t<字节数>
  - wsl.exe 输出为 UTF-16LE（含 BOM/CRLF），脚本内已解码处理

退出码: 0=成功/dry-run/列表 1=执行失败 2=用法错误
EOF
}

# env: git-bash
# fn: 将 wsl.exe 的 UTF-16LE 输出（BOM/CRLF）解码为 UTF-8 纯文本（stdin→stdout）
_wsl_decode() {
  {
    if command -v iconv > /dev/null 2>&1; then
      iconv -f UTF-16LE -t UTF-8 2> /dev/null
    else
      tr -d '\0'
    fi
  } | sed $'s/\xef\xbb\xbf//' | sed $'s/\xff\xfe//' | tr -d '\r'
}

# env: git-bash
# fn: 调用 wsl.exe -l -v 并解析为 TSV（名称<TAB>状态<TAB>版本）；失败或空输出返回 1
_wsl_list_entries() {
  local errf rc raw line msg found="0"
  local line_re='^\*?[[:space:]]*(.+[^[:space:]])'
  line_re+='[[:space:]]{2,}([A-Za-z]+)'
  line_re+='[[:space:]]+([0-9]+)[[:space:]]*$'
  errf="$(mktemp)" || return 1
  raw="$(wsl.exe -l -v 2> "$errf" | _wsl_decode)"
  rc=$?
  if ((rc != 0)); then
    msg="$(_wsl_decode < "$errf")"
    msg="${msg//$'\r'/}"
    msg="${msg//$'\n'/ }"
    rm -f "$errf"
    log_err "wsl.exe -l -v 失败（退出码 $rc）: ${msg:-（无 stderr 输出）}"
    return 1
  fi
  rm -f "$errf"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ $line_re ]]; then
      printf '%s\t%s\t%s\n' \
        "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
      found="1"
    fi
  done <<< "$raw"
  if [[ "$found" != "1" ]]; then
    log_err "未能从 wsl -l -v 输出解析出任何发行版（格式可能已变化）"
    return 1
  fi
  return 0
}

# env: git-bash
# fn: 从 TSV 发行版清单中查找指定名称，输出 "状态<TAB>版本"；未找到返回 1
_find_entry() {
  local entries="$1" name="$2" n s v
  while IFS=$'\t' read -r n s v; do
    [[ "$n" == "$name" ]] || continue
    printf '%s\t%s\n' "$s" "$v"
    return 0
  done <<< "$entries"
  return 1
}

# env: git-bash
# fn: 目标目录最近存在祖先的可用空间（KB，df -P）；无法获取时输出空
_free_kb() {
  local dir="$1" parent
  while [[ ! -e "$dir" ]]; do
    parent="$(dirname -- "$dir")"
    [[ "$parent" == "$dir" ]] && break
    dir="$parent"
  done
  df -P "$dir" 2> /dev/null | awk 'NR == 2 { print $4 }'
}

# env: git-bash
# fn: 执行 wsl.exe --export；失败时解码 stderr 输出错误并返回 1
_run_wsl_export() {
  local distro="$1" target="$2" errf rc msg
  errf="$(mktemp)" || return 1
  wsl.exe --export "$distro" "$target" 2> "$errf"
  rc=$?
  msg="$(_wsl_decode < "$errf")"
  rm -f "$errf"
  if ((rc != 0)); then
    msg="${msg//$'\r'/}"
    msg="${msg//$'\n'/ }"
    log_err "wsl.exe --export 失败（退出码 $rc）: ${msg:-（无 stderr 输出）}"
    return 1
  fi
  return 0
}

# env: git-bash
# fn: 非 git-bash（msys）平台运行时输出告警（不阻断）
_warn_platform() {
  local platform
  platform="$(env_detect_platform)"
  if [[ "$platform" != "msys" ]]; then
    log_warn "当前平台为 $platform——本脚本设计在 Windows 侧（git-bash）运行"
  fi
}

# env: git-bash
# fn: --list 模式——解析并列出发行版（名称/状态/版本对齐输出）
cmd_list() {
  local entries n s v
  entries="$(_wsl_list_entries)" || return 1
  echo "已注册发行版（wsl -l -v 解析）:"
  while IFS=$'\t' read -r n s v; do
    [[ -n "$n" ]] || continue
    printf '  %-28s %-12s %s\n' "$n" "$s" "$v"
  done <<< "$entries"
  return 0
}

# env: git-bash
# fn: 导出模式——dry-run 打印计划或 --apply 执行导出、非空校验与记录追加
cmd_export() {
  local apply="$1" dest="$2" manifest="$3" min_free="$4"
  local distro="${5:-}" target="${6:-}"
  local entries="" state="" version="" entry=""
  local ts fname avail min_kb ts_iso bytes space_ok="false" space_note

  entries="$(_wsl_list_entries)" || return 1
  entry="$(_find_entry "$entries" "$distro")" || entry=""
  if [[ -n "$entry" ]]; then
    state="${entry%%$'\t'*}"
    version="${entry#*$'\t'}"
  fi

  if [[ -z "$target" ]]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    fname="${distro//\//-}"
    fname="${fname//\\/-}"
    target="${dest%/}/${fname}-${ts}.tar"
  else
    dest="$(dirname -- "$target")"
  fi
  if [[ -z "$manifest" ]]; then
    manifest="${dest%/}/wsl-export.log"
  fi
  min_kb=$((min_free * 1024 * 1024))
  avail="$(_free_kb "$dest")"
  if [[ -z "$avail" ]]; then
    space_note="未知（df 失败）"
  elif ((avail >= min_kb)); then
    space_ok="true"
    space_note="${avail} KB（要求 ≥ ${min_kb} KB）"
  else
    space_note="${avail} KB，不足（要求 ≥ ${min_kb} KB）"
  fi

  if [[ "$apply" != "true" ]]; then
    echo "[dry-run] 导出计划:"
    if [[ -n "$state" ]]; then
      echo "[dry-run]   发行版: $distro（$state, WSL$version）"
      if [[ "$state" != "Stopped" ]]; then
        echo "[dry-run]   提示: 状态 $state 非 Stopped，--apply 将拒绝"
        echo "[dry-run]   （可先执行 wsl --terminate $distro）"
      fi
    else
      echo "[dry-run]   发行版: $distro（未在 wsl -l -v 中找到，--apply 将拒绝）"
    fi
    echo "[dry-run]   目标文件: $target"
    echo "[dry-run]   目标目录: $dest（不存在将创建）"
    echo "[dry-run]   剩余空间: $space_note"
    echo "[dry-run]   执行: wsl.exe --export $distro $target"
    echo "[dry-run]   导出后: 校验 tar 非空，追加记录到 $manifest"
    echo "确认无误后加 --apply 执行"
    if [[ "$space_ok" != "true" ]]; then
      log_warn "目标盘剩余空间不足或未知（$space_note），--apply 将拒绝"
    fi
    return 0
  fi

  if [[ -z "$state" ]]; then
    log_err "未在 wsl -l -v 中找到发行版: $distro（先运行 --list 确认名称）"
    return 1
  fi
  if [[ "$state" != "Stopped" ]]; then
    log_err "发行版 $distro 状态为 $state，导出要求 Stopped"
    echo "提示: 先执行 wsl --terminate $distro 再试" >&2
    return 1
  fi
  if [[ -e "$target" ]]; then
    log_err "目标文件已存在，拒绝覆盖: $target"
    return 1
  fi
  if [[ -e "$dest" && ! -d "$dest" ]]; then
    log_err "导出目录已存在且不是目录: $dest"
    return 1
  fi
  if [[ -z "$avail" ]]; then
    log_err "无法获取目标盘剩余空间（df 失败），拒绝导出"
    return 1
  fi
  if ((avail < min_kb)); then
    log_err "目标盘剩余空间不足: ${avail} KB < 要求 ${min_kb} KB"
    return 1
  fi
  if ! mkdir -p -- "$dest"; then
    log_err "无法创建导出目录: $dest"
    return 1
  fi
  if ! _run_wsl_export "$distro" "$target"; then
    if [[ -e "$target" ]]; then
      rm -f -- "$target"
      log_warn "已清理导出失败残留文件: $target"
    fi
    return 1
  fi
  if [[ ! -s "$target" ]]; then
    log_err "导出的 tar 文件为空或缺失，可能导出异常: $target"
    rm -f -- "$target"
    return 1
  fi
  if ! bytes="$(wc -c < "$target")"; then
    log_err "无法读取导出文件大小: $target"
    return 1
  fi
  if ! mkdir -p -- "$(dirname -- "$manifest")"; then
    log_err "无法创建记录清单目录: $(dirname -- "$manifest")"
    return 1
  fi
  ts_iso="$(date +%Y-%m-%dT%H:%M:%S)"
  if ! printf '%s\t%s\t%s\t%s\n' "$ts_iso" "$distro" "$target" "$bytes" \
    >> "$manifest"; then
    log_err "记录追加失败: $manifest（导出文件本身已生成）"
    return 1
  fi
  log_info "导出完成: $target（$bytes 字节）"
  log_info "已追加记录: $manifest"
  return 0
}

# env: git-bash
# fn: 入口——参数解析、平台提示与 wsl.exe 预检、列表或导出分派
main() {
  local list_mode="false" apply="false" dest="" manifest="" min_free="10"
  local -a pos=()

  while (($# > 0)); do
    case "$1" in
      --list)
        list_mode="true"
        shift
        ;;
      --dest)
        if (($# < 2)); then
          log_err "选项 --dest 缺少参数"
          return 2
        fi
        dest="$2"
        shift 2
        ;;
      --manifest)
        if (($# < 2)); then
          log_err "选项 --manifest 缺少参数"
          return 2
        fi
        manifest="$2"
        shift 2
        ;;
      --min-free)
        if (($# < 2)) || ! [[ "$2" =~ ^[0-9]+$ ]]; then
          log_err "选项 --min-free 需要非负整数参数（GB）"
          return 2
        fi
        min_free="$2"
        shift 2
        ;;
      --apply)
        apply="true"
        shift
        ;;
      -n | --dry-run)
        shift
        ;;
      -h | --help)
        usage
        return 0
        ;;
      -*)
        log_err "未知选项: $1"
        usage >&2
        return 2
        ;;
      *)
        pos+=("$1")
        shift
        ;;
    esac
  done

  if [[ "$list_mode" == "true" ]]; then
    if ((${#pos[@]} > 0)); then
      log_err "--list 不接受位置参数"
      return 2
    fi
    _warn_platform
    if ! command -v wsl.exe > /dev/null 2>&1; then
      log_err "未找到 wsl.exe——请在 Windows 侧 git-bash 运行（或检查 PATH）"
      return 1
    fi
    cmd_list
    return $?
  fi

  case ${#pos[@]} in
    0)
      usage >&2
      return 2
      ;;
    1)
      if [[ -z "$dest" ]]; then
        log_err "缺少导出目标: 用 <发行版> <目标tar> 或 <发行版> --dest <目录>"
        return 2
      fi
      ;;
    2)
      if [[ -n "$dest" ]]; then
        log_err "--dest 与第二个位置参数（目标文件）不能同时使用"
        return 2
      fi
      ;;
    *)
      log_err "位置参数过多（最多 2 个: <发行版> [<目标tar>]）"
      return 2
      ;;
  esac

  _warn_platform
  if ! command -v wsl.exe > /dev/null 2>&1; then
    log_err "未找到 wsl.exe——请在 Windows 侧 git-bash 运行（或检查 PATH）"
    return 1
  fi
  cmd_export "$apply" "$dest" "$manifest" "$min_free" "${pos[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
