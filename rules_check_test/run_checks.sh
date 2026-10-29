#!/usr/bin/env bash
# script-name: run-checks
# description: rules_check_test 运行器——good/bad 用例实测检测输出并与 expected/ 归一化比对
# usage: run_checks.sh [--quiet] [--update-expected]
# option: --quiet    只输出失败项与汇总
# option: --update-expected    以实测输出重建 bad 用例 golden 文件（维护用）
# example: rules_check_test/run_checks.sh
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: shfmt, shellcheck, bash
# category: dev

set -u -o pipefail

_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_HOOKS_DIR="$(cd -- "${_ROOT}/../hooks" && pwd)"
_QUIET="false"
_UPDATE="false"

# 标记词表：shfmt:diff / shellcheck:SCxxxx / line-length:over-80
#          / metadata:missing-tag-<key> / metadata:shebang-missing
#          / metadata:missing-env-annotation

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 对单个文件运行四类检测并输出标记集合（每行一个）
collect_markers() {
  local file="$1" sc_out meta_out
  if ! shfmt -d -i 2 -ci -bn -sr "$file" > /dev/null 2>&1; then
    echo "shfmt:diff"
  fi
  sc_out="$(shellcheck --severity=style "$file" 2>&1 || true)"
  if [[ -n "$sc_out" ]]; then
    grep -o 'SC[0-9]\+' <<< "$sc_out" | sort -u | sed 's/^/shellcheck:/'
  fi
  if ! "$_HOOKS_DIR/line-length.sh" "$file" > /dev/null 2>&1; then
    echo "line-length:over-80"
  fi
  meta_out="$("$_HOOKS_DIR/check-metadata.sh" "$file" 2>&1 || true)"
  if [[ -n "$meta_out" ]]; then
    grep -o "tag '[a-z-]*'" <<< "$meta_out" \
      | sed "s/tag '/metadata:missing-tag-/; s/'\$//"
    grep -q 'shebang' <<< "$meta_out" && echo "metadata:shebang-missing"
    grep -q '函数缺 # env' <<< "$meta_out" \
      && echo "metadata:missing-env-annotation"
  fi
  return 0
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 读取 stdin，每行前加 4 空格缩进后输出
_indent4() {
  local line
  while IFS= read -r line; do
    printf '    %s\n' "$line"
  done
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: good 用例校验：不应产生任何检测标记
check_good_case() {
  local file="$1" name actual
  name="$(basename -- "$file" .sh)"
  actual="$(collect_markers "$file")"
  if [[ -n "$actual" ]]; then
    echo "FAIL $name（good 用例不应有检测标记）"
    if [[ "$_QUIET" == "false" ]]; then
      _indent4 <<< "$actual"
    fi
    return 1
  fi
  if [[ "$_QUIET" == "false" ]]; then
    echo "PASS $name"
  fi
  return 0
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: bad 用例校验：实测标记须与 expected/<name>.expected 完全一致
check_bad_case() {
  local file="$1" name expected actual tmp ok="true"
  name="$(basename -- "$file" .sh)"
  expected="${_ROOT}/expected/${name}.expected"
  actual="$(collect_markers "$file" | sort)"
  if [[ "$_UPDATE" == "true" ]]; then
    if [[ -n "$actual" ]]; then
      printf '%s\n' "$actual" > "$expected"
    else
      : > "$expected"
    fi
    echo "UPDATED $name"
    return 0
  fi
  if [[ ! -f "$expected" ]]; then
    echo "FAIL $name（缺 expected/${name}.expected，可 --update-expected 生成）"
    return 1
  fi
  tmp="$(mktemp)"
  if [[ -n "$actual" ]]; then
    printf '%s\n' "$actual" > "$tmp"
  else
    : > "$tmp"
  fi
  if ! diff -u "$expected" "$tmp" > /dev/null 2>&1; then
    echo "FAIL $name（实测标记与 golden 不一致）"
    if [[ "$_QUIET" == "false" ]]; then
      diff -u "$expected" "$tmp" | _indent4
    fi
    ok="false"
  elif [[ "$_QUIET" == "false" ]]; then
    echo "PASS $name"
  fi
  rm -f "$tmp"
  if [[ "$ok" == "true" ]]; then
    return 0
  fi
  return 1
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 遍历 good/bad 用例并汇总退出码
main() {
  local arg file pass=0 fail=0
  for arg in "$@"; do
    case "$arg" in
      --quiet) _QUIET="true" ;;
      --update-expected) _UPDATE="true" ;;
      *)
        echo "未知参数: $arg" >&2
        return 2
        ;;
    esac
  done
  for file in "$_ROOT"/good/*.sh; do
    [[ -e "$file" ]] || continue
    if check_good_case "$file"; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
    fi
  done
  for file in "$_ROOT"/bad/*.sh; do
    [[ -e "$file" ]] || continue
    if check_bad_case "$file"; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
    fi
  done
  if [[ "$_UPDATE" == "true" ]]; then
    echo "expected/ 已按实测输出重建"
    return 0
  fi
  if [[ "$_QUIET" == "false" ]]; then
    echo "rules_check_test: pass=$pass fail=$fail"
  fi
  if ((fail > 0)); then
    return 1
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
