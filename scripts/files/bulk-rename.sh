#!/usr/bin/env bash
# script-name: bulk-rename
# description: 目录内文件批量重命名（前缀/后缀/序号/regex），默认 dry-run 打印计划
# usage: bulk-rename.sh [选项] <目录>
# option: -p, --prefix <str>    新文件名前缀
# option: -s, --suffix <str>    新文件名后缀（插入扩展名之前）
# option: --start <n>           序号模式：主干替换为序号（按名称排序，从 n 起编号）
# option: -r, --regex <expr>    sed 风格替换 s/old/new/[g]，作用于原文件名主干
# option: --apply               执行重命名（缺省为 dry-run，仅打印 mv 计划）
# option: -h, --help            显示帮助
# example: bulk-rename.sh -p trip- --start 1 ~/photos
# example: bulk-rename.sh -r 's/IMG_//g' -s -bak ~/pics --apply
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: coreutils, findutils, sed
# category: files

set -u -o pipefail

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 打印用法到 stderr
usage() {
  cat << 'EOF'
用法: bulk-rename.sh [选项] <目录>
对目录（不含子目录）中的普通文件批量重命名。默认 dry-run 仅打印 mv 计划，
加 --apply 才执行。目标已存在的条目拒绝（不覆盖），批内目标冲突同样拒绝。

规则选项（至少一个）:
  -p, --prefix <str>   新文件名前缀
  -s, --suffix <str>   新文件名后缀（插入扩展名之前）
  --start <n>          序号模式：主干替换为序号（按名称排序，从 n 起编号），
                       最终名为 前缀+序号+后缀+扩展名
  -r, --regex <expr>   sed 风格替换 s/old/new/[g]，作用于原文件名主干；
                       new 中不能含 /

其他:
  --apply     执行重命名（缺省为 dry-run）
  -h, --help  显示本帮助

限制: 文件名含换行符无法正确处理；以 . 开头的文件视为无扩展名；
      --start 与 --regex 不能同时使用（两者都改动主干，语义冲突）。
EOF
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 入口——参数解析、规则校验、生成计划、dry-run 打印或执行
main() {
  local prefix="" suffix="" regex="" start="" apply="false" dir
  local re_shape='^s/.*/.*/[a-zA-Z]*$'
  local -a args=() plan_from=() plan_to=() names=()
  local -A planned=()

  while (($# > 0)); do
    case "$1" in
      -p | --prefix | -s | --suffix | -r | --regex)
        if (($# < 2)); then
          echo "错误: $1 缺少参数" >&2
          return 2
        fi
        case "$1" in
          -p | --prefix) prefix="$2" ;;
          -s | --suffix) suffix="$2" ;;
          *) regex="$2" ;;
        esac
        shift 2
        ;;
      --start)
        if (($# < 2)) || ! [[ "$2" =~ ^[0-9]+$ ]]; then
          echo "错误: --start 需要非负整数参数" >&2
          return 2
        fi
        start="$2"
        shift 2
        ;;
      --apply)
        apply="true"
        shift
        ;;
      -h | --help)
        usage
        return 0
        ;;
      -*)
        echo "错误: 未知选项: $1" >&2
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
  if [[ -z "$prefix" && -z "$suffix" && -z "$regex" && -z "$start" ]]; then
    echo "错误: 未指定任何重命名规则（--prefix/--suffix/--start/--regex 至少一个）" >&2
    return 2
  fi
  if [[ -n "$regex" && -n "$start" ]]; then
    echo "错误: --start 与 --regex 不能同时使用" >&2
    return 2
  fi
  if [[ -n "$regex" ]]; then
    if [[ ! "$regex" =~ $re_shape ]] \
      || ! printf '' | sed -e "$regex" > /dev/null 2>&1; then
      echo "错误: --regex 表达式非法（须为 s/old/new/[g]，new 中不能含 /）: $regex" >&2
      return 2
    fi
  fi
  dir="${args[0]}"
  if [[ ! -d "$dir" ]]; then
    echo "错误: 目录不存在或不是目录: $dir" >&2
    return 1
  fi

  mapfile -t -d '' names < <(
    find "$dir" -maxdepth 1 -type f -printf '%f\0' | sort -z
  )
  if ((${#names[@]} == 0)); then
    echo "目录中没有可重命名的普通文件: $dir"
    return 0
  fi

  local name stem ext new new_stem idx=0 skipped=0 planned_cnt=0
  for name in "${names[@]}"; do
    stem="$name"
    ext=""
    if [[ "$name" == *.* && "$name" != .* ]]; then
      ext=".${name##*.}"
      stem="${name%.*}"
    fi
    if [[ -n "$start" ]]; then
      new_stem="${prefix}$((start + idx))${suffix}"
    elif [[ -n "$regex" ]]; then
      new_stem="${prefix}$(printf '%s' "$stem" | sed -e "$regex")${suffix}"
    else
      new_stem="${prefix}${stem}${suffix}"
    fi
    ((idx += 1))
    new="${new_stem}${ext}"
    if [[ "$new" == "$name" ]]; then
      continue
    fi
    if [[ -e "$dir/$new" || -L "$dir/$new" || -n "${planned["$new"]:-}" ]]; then
      echo "跳过: 目标已存在: '$name' -> '$new'" >&2
      ((skipped += 1))
      continue
    fi
    planned["$new"]="1"
    plan_from+=("$name")
    plan_to+=("$new")
    ((planned_cnt += 1))
  done

  if ((planned_cnt == 0)); then
    echo "没有需要重命名的文件"
    return 0
  fi

  local i done_cnt=0 failed=0
  if [[ "$apply" != "true" ]]; then
    echo "[dry-run] 将执行以下重命名（共 $planned_cnt 条）:"
    for ((i = 0; i < planned_cnt; i++)); do
      echo "  mv '${plan_from[$i]}' -> '${plan_to[$i]}'"
    done
    if ((skipped > 0)); then
      echo "另有 $skipped 条因目标已存在被跳过"
    fi
    echo "确认无误后加 --apply 执行"
    return 0
  fi

  for ((i = 0; i < planned_cnt; i++)); do
    if mv -- "$dir/${plan_from[$i]}" "$dir/${plan_to[$i]}"; then
      echo "已重命名: '${plan_from[$i]}' -> '${plan_to[$i]}'"
      ((done_cnt += 1))
    else
      echo "错误: 重命名失败: '${plan_from[$i]}'" >&2
      ((failed += 1))
    fi
  done
  echo "完成 $done_cnt 条，失败 $failed 条，跳过 $skipped 条"
  if ((failed > 0)); then
    return 1
  fi
  return 0
}

main "$@"
