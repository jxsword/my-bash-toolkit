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
  local file="$1" status=0 tag
  if ! head -n 1 "$file" | grep -q '^#!/usr/bin/env bash$'; then
    echo "$file:1: 缺少 shebang（应为 #!/usr/bin/env bash）"
    status=1
  fi
  # 头部 tag：shebang 后、首个空行前的注释块中查找
  for tag in $_REQUIRED_TAGS; do
    if ! head -n 30 "$file" \
      | sed -n '2,/^[[:space:]]*$/p' \
      | grep -Eq "^#[[:space:]]*${tag}:"; then
      echo "$file:1: 缺少头部必需 tag '$tag'（规格见 docs/bash_env_and_doc_spec.md §4）"
      status=1
    fi
  done
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
        printf "%s:%d: 函数缺 # env: 标注（规格见 docs/bash_env_and_doc_spec.md §5）\n",
          file, FNR
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
