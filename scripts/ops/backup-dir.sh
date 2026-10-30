#!/usr/bin/env bash
# script-name: backup-dir
# description: 目录 tar 快照备份——配套 restore.sh 与 --keep 滚动保留，默认 dry-run
# usage: backup-dir.sh [选项] <目录>
# option: --dest <dir>     备份根目录（默认 ~/backups，不存在则创建）
# option: --keep <n>       滚动保留最新 n 份 <目录名>-*.tar.gz（缺省不清理）
# option: --apply          执行备份（缺省为 dry-run，仅打印计划）
# option: -n, --dry-run    仅打印计划，不写任何文件（与缺省行为一致）
# option: -h, --help       显示帮助
# example: backup-dir.sh ~/proj
# example: backup-dir.sh --dest ~/backups --keep 5 --apply ~/proj
# env: ubuntu-26.04, wsl-ubuntu-26.04
# deps: tar, coreutils, findutils
# category: ops

set -u -o pipefail

_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "$_ROOT/scripts/lib/common.sh"

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 打印用法到 stdout（错误分支重定向到 stderr）
usage() {
  cat << 'EOF'
用法: backup-dir.sh [选项] <目录>
对指定目录做 tar 快照（-P 保留绝对路径），并生成配套 restore.sh
（tar xzf -P 恢复到原路径，语义对齐 test/helpers/backup_restore.bash）。
默认 dry-run 仅打印计划，加 --apply 才执行。

选项:
  --dest <dir>     备份根目录（默认 ~/backups，不存在则创建）
  --keep <n>       滚动保留最新 n 份 <目录名>-*.tar.gz（缺省不清理）
  --apply          执行备份（缺省为 dry-run）
  -n, --dry-run    仅打印计划，不写任何文件（与缺省一致）
  -h, --help       显示本帮助

快照命名: <目录名>-<YYYYMMDD-HHMMSS>.tar.gz；
同名快照已存在时拒绝覆盖。建议备份根不要位于源目录内部；
拒绝备份根目录 /。
EOF
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 生成配套 restore.sh（tar xzf -P 恢复到原绝对路径）并加执行位
_write_restore_script() {
  local tarball="$1" restore="$2" qpath
  qpath="$(printf '%q' "$tarball")"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# 由 backup-dir.sh 自动生成——恢复本快照到原路径\n'
    printf '# 语义对齐 test/helpers/backup_restore.bash（-P 保留绝对路径）\n'
    printf 'set -euo pipefail\n'
    printf 'tar xzf %s -P\n' "$qpath"
    printf 'echo 已恢复: %s\n' "$qpath"
  } > "$restore"
  chmod +x "$restore"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 滚动清理——保留 dest 下 <base>-*.tar.gz 最新 keep 份及其恢复脚本
_prune_old() {
  local dest="$1" base="$2" keep="$3"
  local -a snaps=()
  local i f
  mapfile -d '' snaps < <(
    find "$dest" -maxdepth 1 -name "${base}-*.tar.gz" -print0 | sort -z
  )
  if ((${#snaps[@]} <= keep)); then
    return 0
  fi
  for ((i = 0; i < ${#snaps[@]} - keep; i++)); do
    f="${snaps[$i]}"
    rm -f -- "$f" "${f}.restore.sh"
    log_info "已清理旧快照: $f"
  done
}

# env: ubuntu-26.04, wsl-ubuntu-26.04
# fn: 入口——参数解析、源与备份根校验、dry-run 打印计划或执行快照
main() {
  local dest="" keep="" apply="false" src ts base tarball restore
  local -a args=()

  while (($# > 0)); do
    case "$1" in
      --dest)
        if (($# < 2)); then
          log_err "选项 --dest 缺少参数"
          return 2
        fi
        dest="$2"
        shift 2
        ;;
      --keep)
        if (($# < 2)) || ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
          log_err "选项 --keep 需要正整数参数"
          return 2
        fi
        keep="$2"
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
        args+=("$1")
        shift
        ;;
    esac
  done

  if ((${#args[@]} != 1)); then
    usage >&2
    return 2
  fi
  src="${args[0]}"
  while [[ "$src" == */ && "$src" != "/" ]]; do
    src="${src%/}"
  done
  if [[ -z "$src" || "$src" == "/" ]]; then
    log_err "拒绝备份根目录 /"
    return 1
  fi
  if [[ ! -d "$src" ]]; then
    log_err "源目录不存在或不是目录: $src"
    return 1
  fi
  if [[ -z "$dest" ]]; then
    dest="$HOME/backups"
  fi
  base="$(basename -- "$src")"
  ts="$(date +%Y%m%d-%H%M%S)"
  tarball="$dest/${base}-${ts}.tar.gz"
  restore="${tarball}.restore.sh"

  if [[ "$apply" != "true" ]]; then
    echo "[dry-run] 快照计划:"
    echo "[dry-run]   源目录: $src"
    echo "[dry-run]   备份根: $dest（不存在将创建）"
    echo "[dry-run]   快照文件: $tarball"
    echo "[dry-run]   执行: tar czf $tarball -P -- $src"
    echo "[dry-run]   生成恢复脚本: $restore"
    echo "[dry-run]   恢复语义: tar xzf 快照 -P（还原到原绝对路径）"
    if [[ -n "$keep" ]]; then
      echo "[dry-run]   滚动保留: 仅保留最新 $keep 份 ${base}-*.tar.gz"
    else
      echo "[dry-run]   滚动保留: 未指定 --keep，不清理旧快照"
    fi
    echo "确认无误后加 --apply 执行"
    return 0
  fi

  if [[ -e "$tarball" ]]; then
    log_err "快照文件已存在，拒绝覆盖: $tarball"
    return 1
  fi
  if [[ -e "$dest" && ! -d "$dest" ]]; then
    log_err "备份根已存在且不是目录: $dest"
    return 1
  fi
  if [[ "$dest" == "$src" || "$dest" == "$src"/* ]]; then
    log_warn "备份根位于源目录内部，快照可能包含备份根自身"
  fi
  if ! mkdir -p "$dest"; then
    log_err "无法创建备份根目录: $dest"
    return 1
  fi
  if ! tar czf "$tarball" -P -- "$src"; then
    log_err "tar 打包失败: $src -> $tarball"
    rm -f -- "$tarball"
    return 1
  fi
  if [[ ! -s "$tarball" ]]; then
    log_err "快照文件为空，打包可能异常: $tarball"
    rm -f -- "$tarball"
    return 1
  fi
  _write_restore_script "$tarball" "$restore"
  if [[ -n "$keep" ]]; then
    _prune_old "$dest" "$base" "$keep"
  fi
  log_info "快照完成: $tarball"
  log_info "恢复方法: bash $restore"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
