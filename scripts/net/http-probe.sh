#!/usr/bin/env bash
# script-name: http-probe
# description: URL 健康检查——curl 记录状态码与耗时，受控并发，汇总表格输出
# usage: http-probe.sh [--concurrency <n>] [--timeout <秒>] [--fail-only] \
# usage:   [-f <文件>] <url>...
# option: -c, --concurrency <n>    并发上限（默认 4，须为正整数）
# option: -t, --timeout <秒>       单请求超时秒数（默认 10，传 curl --max-time）
# option: -f, --file <文件>        URL 列表文件（每行一个；空行与 # 注释忽略）
# option:     --fail-only          仅输出异常条目（表头与汇总行仍输出）
# option: -h, --help               显示帮助
# example: http-probe.sh http://127.0.0.1:8080/health
# example: http-probe.sh -f urls.txt --concurrency 8 --fail-only
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: curl, coreutils
# category: net

set -u -o pipefail

# 探测结果临时目录（全局：EXIT trap 在函数作用域外触发时仍可见）
RESULTS_DIR=""

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 打印用法到 stderr
usage() {
  cat << 'EOF'
用法: http-probe.sh [--concurrency <n>] [--timeout <秒>] [--fail-only]
                    [-f <文件>] <url>...
对每个 URL 用 curl 探测一次: 记录 HTTP 状态码与总耗时, 受控并发执行
(同时运行的请求数不超过并发上限), 最后输出汇总表格与统计行.

判定: HTTP 状态码 1xx-3xx = 正常; >=400 / 000 / curl 失败(ERR) = 异常.
回环目标(localhost/127.0.0.1/::1)恒绕过代理; 其他目标遵循代理环境变量.

退出码: 0=全部正常 1=存在异常 2=用法错误

选项:
  -c, --concurrency <n>   并发上限（默认 4）
  -t, --timeout <秒>      单请求超时秒数（默认 10, 传给 curl --max-time）
  -f, --file <文件>       从文件读取 URL（每行一个; 空行与 # 注释忽略）
      --fail-only         仅输出异常条目（表头与汇总行仍输出）
  -h, --help              显示本帮助
EOF
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 正整数校验（10# 强制十进制，规避前导零按八进制解析）
is_positive_int() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  ((1 <= 10#$1))
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 从列表文件追加 URL 到 nameref 数组（trim 后跳过空行与 # 注释行）
collect_urls_from_file() {
  local -n list_ref="$1"
  local file="$2" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    list_ref+=("$line")
  done < "$file"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 单 URL 探测（后台子进程执行）；结果三列 TSV 写入 $2（状态码/耗时/备注）
_probe_one() {
  local url="$1" result_file="$2" timeout="$3"
  local res rc
  res="$(curl -sS --noproxy 'localhost,127.0.0.1,::1,[::1]' \
    -o /dev/null --max-time "$timeout" \
    -w '%{http_code}\t%{time_total}' "$url" 2>&1)"
  rc=$?
  if ((rc == 0)); then
    printf '%s\t-\n' "$res" > "$result_file"
  else
    printf 'ERR(%s)\t-\t%s\n' "$rc" "$res" > "$result_file"
  fi
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 入口——参数解析、受控并发探测与汇总表格输出
main() {
  local concurrency=4 timeout=10 fail_only=0 list_file=""
  local -a urls=()
  while (($#)); do
    case "$1" in
      -c | --concurrency)
        if (($# < 2)); then
          echo "错误: $1 缺少参数值" >&2
          return 2
        fi
        concurrency="$2"
        shift 2
        ;;
      -t | --timeout)
        if (($# < 2)); then
          echo "错误: $1 缺少参数值" >&2
          return 2
        fi
        timeout="$2"
        shift 2
        ;;
      -f | --file)
        if (($# < 2)); then
          echo "错误: $1 缺少参数值" >&2
          return 2
        fi
        list_file="$2"
        shift 2
        ;;
      --fail-only)
        fail_only=1
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
        if [[ -z "$1" ]]; then
          echo "错误: URL 不能为空" >&2
          return 2
        fi
        urls+=("$1")
        shift
        ;;
    esac
  done

  if [[ -n "$list_file" ]]; then
    if [[ ! -r "$list_file" ]]; then
      echo "错误: 无法读取 URL 列表文件: $list_file" >&2
      return 2
    fi
    collect_urls_from_file urls "$list_file"
  fi
  if ((${#urls[@]} == 0)); then
    echo "错误: 未提供任何 URL" >&2
    usage >&2
    return 2
  fi
  if ! is_positive_int "$concurrency"; then
    echo "错误: --concurrency 须为正整数: $concurrency" >&2
    return 2
  fi
  if ! is_positive_int "$timeout"; then
    echo "错误: --timeout 须为正整数秒: $timeout" >&2
    return 2
  fi
  if ! command -v curl > /dev/null 2>&1; then
    echo "错误: curl 不可用（依赖: curl）" >&2
    return 2
  fi

  RESULTS_DIR="$(mktemp -d)" || {
    echo "错误: 创建临时目录失败" >&2
    return 1
  }
  trap 'rm -rf "$RESULTS_DIR"' EXIT

  # 受控并发: 每启动一个任务, 运行数达到上限即 wait -n 等一个完成
  local i
  for i in "${!urls[@]}"; do
    _probe_one "${urls[$i]}" "$RESULTS_DIR/$i" "$timeout" &
    while (($(jobs -rp | wc -l) >= concurrency)); do
      wait -n || true
    done
  done
  wait

  local ok=0 bad=0
  local status time_s note url suffix show
  printf '%-9s %-10s %s\n' '状态' '耗时(s)' 'URL'
  for i in "${!urls[@]}"; do
    status="" time_s="" note="" suffix="" show=0
    url="${urls[$i]}"
    IFS=$'\t' read -r status time_s note < "$RESULTS_DIR/$i"
    if [[ "$status" == ERR* || "$status" == "000" ]]; then
      show=1
    elif [[ ! "$status" =~ ^[0-9]+$ ]] || ((10#$status >= 400)); then
      show=1
    fi
    if ((show)); then
      bad=$((bad + 1))
    else
      ok=$((ok + 1))
    fi
    # 正常行仅在非 --fail-only 时输出; 异常行恒输出
    if ((show || !fail_only)); then
      if [[ "$status" == ERR* && -n "$note" ]]; then
        suffix="  ($note)"
      fi
      printf '%-9s %-10s %s%s\n' "$status" "$time_s" "$url" "$suffix"
    fi
  done
  echo "汇总: 共 ${#urls[@]} 个 URL, 正常 $ok, 异常 $bad"
  ((bad > 0)) && return 1
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
