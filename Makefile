SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help lint test test-changed test-one bench-tests check-rules docs env-check doctor check

help: ## 显示可用目标
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
		| awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

lint: ## pre-commit 全量检查（跳过 bats-changed 测试钩子，测试由 test/test-changed 承担）
	SKIP=bats-changed pre-commit run --all-files

test: ## bats 单元测试（全量，Stage 1）
	@bats $$(bash -c 'source scripts/lib/test_files.sh && collect_bats_files')

test-changed: ## 只运行与变更文件对应的 bats 用例（回退规则见 helper usage）
	scripts/dev/test-changed.sh --run

test-one: ## 运行单个测试文件（make test-one F=test/lib/env.bats）
	@if [ -z "$(F)" ]; then \
		echo "用法: make test-one F=<bats 文件>" >&2; exit 2; fi
	@if [ ! -f "$(F)" ]; then \
		echo "错误: 文件不存在: $(F)" >&2; exit 2; fi
	bats "$(F)"

bench-tests: ## 测试基准计时（ARGS 透传，如 ARGS="--save bench.md"）
	scripts/dev/bench-tests.sh $(ARGS)

check-rules: ## rules_check_test 规范用例回归
	rules_check_test/run_checks.sh

docs: ## 重新生成 docs/SCRIPTS.md
	scripts/dev/gen-docs.sh

env-check: ## bash 环境识别与 .bash-version 区间判定
	scripts/lib/env.sh

doctor: ## 打印工具链实测版本
	@printf 'bash: '; bash --version | head -1
	@printf 'shfmt: '; command -v shfmt >/dev/null \
		&& shfmt --version || echo MISSING
	@printf 'shellcheck: '; command -v shellcheck >/dev/null \
		&& shellcheck --version | grep -m1 '^version: ' || echo MISSING
	@printf 'bats: '; command -v bats >/dev/null \
		&& bats --version || echo MISSING
	@printf 'pre-commit: '; command -v pre-commit >/dev/null \
		&& pre-commit --version || echo MISSING

check: lint check-rules test ## 全量检查（lint + rules + test）
