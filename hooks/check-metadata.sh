#!/usr/bin/env bash
# script-name: check-metadata
# description: pre-commit 本地 hook——校验 shebang、头部必需 tag 与函数级 # env: 标注
# usage: check-metadata.sh <file.sh>...
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: awk
# category: dev

set -u -o pipefail

readonly _REQUIRED_TAGS="script-name description usage env category"

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 校验单个文件的头部 tag 与函数标注；违规输出 file:line 并返回非零
check_file() {
  local file="$1" status=0 tag block blockprog
  local is_bats="false"
  [[ "$file" == *.bats ]] && is_bats="true"
  if ! head -n 1 "$file" | grep -Eq '^#!/usr/bin/env (bash|bats)$'; then
    echo "$file:1: 缺少 shebang（应为 #!/usr/bin/env bash 或 bats）"
    status=1
  fi
  # 头部 tag：shebang（若有）之后、首个空行之前的注释块中查找
  local start=1
  if head -n 1 "$file" | grep -q '^#!'; then
    start=2
  fi
  blockprog='NR<s {next} /^[[:space:]]*$/ {exit} {print}'
  block="$(awk -v s="$start" "$blockprog" "$file")"
  for tag in $_REQUIRED_TAGS; do
    if ! grep -Eq "^#[[:space:]]*${tag}:" <<< "$block"; then
      echo "$file:1: 缺少头部必需 tag '$tag'"
      echo "      （规格见 docs/bash_env_and_doc_spec.md §4）"
      status=1
    fi
  done
  # 函数级 env 标注：bats DSL 文件（setup/@test 由框架管理）豁免
  if [[ "$is_bats" == "true" ]]; then
    return "$status"
  fi
  # 函数级 env 标注：定义行前 3 行内须有 "# env:"
  local fnre
  fnre="^[[:space:]]*(function[[:space:]]+)?"
  fnre="${fnre}[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[(][)]"
  if ! awk -v file="$file" -v fnre="$fnre" '
    BEGIN { bad = 0; buf1 = ""; buf2 = ""; buf3 = "" }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ {
      if ($0 ~ /^[[:space:]]*$/) { buf1 = ""; buf2 = ""; buf3 = "" }
      else { buf3 = buf2; buf2 = buf1; buf1 = $0 }
      next
    }
    $0 ~ fnre {
      if (index(buf1 buf2 buf3, "# env:") == 0) {
        printf "%s:%d: 函数缺 # env: 标注\n", file, FNR
        printf "      （规格见 docs/bash_env_and_doc_spec.md §5）\n"
        bad = 1
      }
      buf3 = buf2; buf2 = buf1; buf1 = $0
      next
    }
    { buf3 = buf2; buf2 = buf1; buf1 = $0 }
    END { exit bad ? 1 : 0 }
  ' "$file"; then
    status=1
  fi
  return "$status"
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 逐文件校验，汇总退出码
main() {
  local file status=0
  for file in "$@"; do
    check_file "$file" || status=1
  done
  return "$status"
}

main "$@"
