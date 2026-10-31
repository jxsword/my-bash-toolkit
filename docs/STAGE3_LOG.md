# STAGE3_LOG —— git bash 人工验收日志

> 用途：记录 Windows git bash 侧（Stage 3）的周期性人工验收结果。
> **本日志不作为跳过测试的依据**——每条记录只证明对应 commit hash 在当时环境的结果；代码、依赖（python/bats/工具链）或环境配置（如 Defender 排除）变更后，必须重新验收并追加新行，禁止引用旧行跳过测试。
> 记录格式：日期 ｜ commit ｜ 范围 ｜ 结果 ｜ 备注

| 日期 | commit | 范围 | 结果 | 备注 |
|---|---|---|---|---|
| 2026-10-30 | 01110b2 | 全量（run_tests.sh） | ✅ 通过（bash 5.2.37） | 首次完整验收：13 执行 + 13 skip 全绿（补记） |
| 2026-10-30 | c3ee436 | 全量（run_tests.sh，JSONQ_PYTHON=scoop python） | ❌ 2 例编码失败（jsonq） | 17 脚本入库后复验；其余全绿（补记） |
| （待复验） | ceee5ef | 全量（JSONQ_PYTHON=scoop python） | 待复验 | jsonq 编码修复 + timeout 加固后需重新验收 |
