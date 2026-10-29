SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help lint test check-rules docs env-check doctor check

help: ## 显示可用目标
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
		| awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

lint: ## pre-commit 全量检查（提交门禁）
	pre-commit run --all-files

test: ## bats 单元测试（Stage 1）
	bats test/

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
