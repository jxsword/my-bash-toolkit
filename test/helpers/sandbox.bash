#!/usr/bin/env bash
# script-name: sandbox
# description: bats 测试助手——mktemp 沙箱与 HOME/XDG 隔离
# usage: （bats 助手，被 load；在 setup/teardown 中调用）
# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# deps: coreutils
# category: dev

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 创建沙箱临时目录并隔离 HOME/XDG_*
sandbox_setup() {
  SANDBOX_DIR="$(mktemp -d)"
  export SANDBOX_DIR
  HOME="$SANDBOX_DIR/home"
  export HOME
  mkdir -p "$HOME"
  XDG_CONFIG_HOME="$SANDBOX_DIR/config"
  export XDG_CONFIG_HOME
  XDG_CACHE_HOME="$SANDBOX_DIR/cache"
  export XDG_CACHE_HOME
}

# env: ubuntu-26.04, wsl-ubuntu-26.04, git-bash
# fn: 清理沙箱临时目录
sandbox_teardown() {
  if [[ -n "${SANDBOX_DIR:-}" && -d "$SANDBOX_DIR" ]]; then
    rm -rf "$SANDBOX_DIR"
  fi
}
