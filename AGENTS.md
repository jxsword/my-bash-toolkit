未显式要求读取当前工作区的 tmp/ 目录下内容时，默认禁止读取。

## Shell 脚本开发约束

- 新会话启动/开发前先读 `docs/PROJECT_CONTEXT.md`（上下文总入口）；开发 shell 脚本另须读 `shell_rules.md`（编码规范）与 `docs/bash_env_and_doc_spec.md`（bash 版本锁定、环境标注、文档 tag 规格）。
- bash 特性使用范围以根目录 `.bash-version`（MIN-MAX，双向硬阻断）为准；脚本/函数的支持环境以函数级 `# env:` 标注为准，未标注的环境一律视为不支持、不测试。
- 新增/修改脚本一律走「脚本引入 SOP」：定分类（scripts/ 10 域，模糊时向用户确认）→ 规范改造（头部元数据 tag、函数级 # env: 标注、kebab-case、系统级脚本 --dry-run）→ bats 测试（沙箱默认，按环境 skip）→ `make docs` 更新 docs/SCRIPTS.md → pre-commit 通过后按 GitHub Flow 提交；完成后同步更新 `docs/PROJECT_CONTEXT.md`。
- `docs/SCRIPTS.md` 为生成物，禁止手改；脚本注释变更后运行 `make docs` 重新生成并随代码同一提交。
- 测试遵循三阶段顺序：本地 WSL（Stage 1）→ 人工确认 → GitHub Actions（Stage 2）→ Windows git bash（Stage 3）；不得跳步。
