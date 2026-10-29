#!/usr/bin/env bash
# script-name: dedup
# description: 递归目录按内容找重复文件（先大小分桶再 sha256），默认仅列出
# usage: dedup.sh [--delete] <目录>
# option: -d, --delete    逐组交互确认删除（每组保留第 1 个文件）
# option: -h, --help      显示帮助
# example: dedup.sh ~/downloads
# example: dedup.sh --delete ~/downloads
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: coreutils, findutils, sha256sum
# category: files

set -u -o pipefail

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 打印用法到 stderr
usage() {
  cat << 'EOF'
用法: dedup.sh [--delete] <目录>
递归查找目录中内容重复的文件（先按大小分桶，再对同大小者做 sha256）。
默认仅列出重复组；空文件与符号链接始终跳过。

选项:
  -d, --delete   逐组交互确认删除（保留该组第 1 个文件）:
                 y=删除该组重复  n=跳过  a=本组起全部删除  q=退出
  -h, --help     显示本帮助

限制: 文件名含换行符的路径无法正确处理（sha256sum 输出解析限制）。
EOF
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 第一遍扫描——按文件大小分桶（size → 换行分隔的路径列表）
scan_by_size() {
  # shellcheck disable=SC2178  # nameref 指向关联数组，shellcheck 误报
  local -n buckets="$1"
  local dir="$2" rec size path
  while IFS= read -r -d '' rec; do
    size="${rec%%$'\t'*}"
    path="${rec#*$'\t'}"
    buckets["$size"]="${buckets["$size"]:-}$path"$'\n'
  done < <(find "$dir" -type f -size +0c -printf '%s\t%p\0')
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 第二遍——仅对大小 >=2 的桶求 sha256（hash → 换行分隔的路径列表）
hash_buckets() {
  # shellcheck disable=SC2178  # nameref 指向关联数组，shellcheck 误报
  local -n buckets="$1"
  # shellcheck disable=SC2178  # nameref 指向关联数组，shellcheck 误报
  local -n groups="$2"
  local size paths path h
  for size in "${!buckets[@]}"; do
    paths="${buckets["$size"]}"
    if (($(printf '%s' "$paths" | wc -l) < 2)); then
      continue
    fi
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      if ! h="$(sha256sum -- "$path")"; then
        echo "警告: 无法读取（已跳过）: $path" >&2
        continue
      fi
      h="${h%% *}"
      groups["$h"]="${groups["$h"]:-}$path"$'\n'
    done <<< "$paths"
  done
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 入口——参数解析、两遍扫描、列组与 --delete 交互删除
main() {
  local delete="false" arg dir
  local -a args=()
  for arg in "$@"; do
    case "$arg" in
      -d | --delete) delete="true" ;;
      -h | --help)
        usage
        return 0
        ;;
      -*)
        echo "错误: 未知选项: $arg" >&2
        usage >&2
        return 2
        ;;
      *) args+=("$arg") ;;
    esac
  done
  if ((${#args[@]} != 1)); then
    usage >&2
    return 2
  fi
  dir="${args[0]}"
  if [[ ! -d "$dir" ]]; then
    echo "错误: 目录不存在或不是目录: $dir" >&2
    return 1
  fi

  # shellcheck disable=SC2034  # 数组经名字传给辅助函数（nameref）
  local -A bysize=() byhash=()
  scan_by_size bysize "$dir"
  hash_buckets bysize byhash

  local h line
  local -a keys=() sorted=()
  for h in "${!byhash[@]}"; do
    if (($(printf '%s' "${byhash[$h]}" | wc -l) >= 2)); then
      keys+=("$h")
    fi
  done
  if ((${#keys[@]} == 0)); then
    echo "未发现重复文件"
    return 0
  fi
  mapfile -t sorted < <(printf '%s\n' "${keys[@]}" | sort)

  local idx=0 deleted=0 all="false" ans i
  for h in "${sorted[@]}"; do
    ((idx += 1))
    local -a files=()
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      files+=("$line")
    done < <(printf '%s' "${byhash[$h]}" | sort)
    echo "重复组 $idx: ${#files[@]} 个文件 (sha256=${h:0:12}…)"
    for line in "${files[@]}"; do
      echo "  $line"
    done
    if [[ "$delete" == "true" ]]; then
      if [[ "$all" != "true" ]]; then
        printf '删除该组重复文件（保留第 1 个）? [y/n/a/q] ' >&2
        IFS= read -r ans || ans="q"
        case "$ans" in
          y | Y) ;;
          a | A) all="true" ;;
          n | N) continue ;;
          *)
            echo "已取消（未删除任何文件）" >&2
            break
            ;;
        esac
      fi
      for ((i = 1; i < ${#files[@]}; i++)); do
        if rm -f -- "${files[$i]}"; then
          echo "已删除: ${files[$i]}"
          deleted=$((deleted + 1))
        else
          echo "错误: 删除失败: ${files[$i]}" >&2
        fi
      done
    fi
  done

  echo "共 $idx 组重复文件"
  if [[ "$delete" == "true" ]]; then
    echo "共删除 $deleted 个文件"
  fi
  return 0
}

main "$@"
