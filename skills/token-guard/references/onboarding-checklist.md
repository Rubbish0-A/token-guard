# Claude Code New User Onboarding Checklist

新同事入职时的 Claude Code 配置清单。照做一遍，避免从第一天就开始浪费 tokens。

## 初始配置

- [ ] **模型选择**：`settings.json` 中 `model` 设为 `sonnet`（日常开发足够，需要深度推理时 `/model opus` 临时切换）
- [ ] **插件精简**：只启用团队推荐的核心插件，其他一律 `false`
- [ ] **Thinking 预算**：设置 `MAX_THINKING_TOKENS=20000`（Windows: `setx MAX_THINKING_TOKENS 20000`）
- [ ] **不用危险模式**：不要添加 `--dangerously-skip-permissions` 启动参数
- [ ] **环境变量检查**：确认 API Key 前缀与变量名匹配（Anthropic=`sk-ant-`/`cr_`，OpenAI=`sk-`，Gemini=`AIza`）
- [ ] **运行 token-guard**：输入 `/token-guard` 确认初始状态为 🟢 健康

## 日常习惯

- [ ] **一任务一会话**：做完一个功能就开新会话
- [ ] **commit message 写进度**：`feat: XX功能 - 已完成YY，下一步ZZ`
- [ ] **长会话用 `/compact`**：感觉对话变长了就压缩一次
- [ ] **关会话前 commit**：确认 git status 干净再关

## 每月检查

- [ ] 运行 `/token-guard` 审计
- [ ] 检查插件列表，禁用不再使用的
- [ ] 检查 `settings.local.json`，清理累积的权限条目

## 团队推荐核心插件

根据团队实际需要填写，建议控制在 5-8 个以内：

1. `commit-commands` — git 提交相关
2. `code-review` — 代码审查
3. `episodic-memory` — 跨会话记忆（按需）
4. `document-skills` — 文档处理（pdf/docx/xlsx）
5. _（根据团队需要补充）_
