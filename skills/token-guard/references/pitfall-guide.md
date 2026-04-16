# Token Guard 踩坑指南

以身试法，把该踩的坑都踩过了。以下每一章都来自真实的排查经历。

---

## 第1章：插件管理 — 你以为关着的灯其实一直亮着

### 踩坑场景

某团队安装了 18 个 Claude Code 插件，涵盖文档处理、前端设计、营销文案、PPT 生成等各种场景。团队觉得"装了不用也没关系，需要的时候能用就行"。

直到有人发现：每次对话的系统提示里都塞着 120+ 条技能描述。写一个简单的 Python 脚本，系统提示里照样带着 35 条营销技能（冷邮件、SEO 审计、广告创意...）的描述。

更糟的是，其中三个插件（`document-skills`、`example-skills`、`claude-api`）注册了完全相同的技能集，导致 pdf、docx、xlsx 等技能各出现了 3 次。

### 为什么会这样

Claude Code 的插件加载机制是**全量注入**：

1. 每个已启用插件的所有技能名称 + 描述，在每次 API 调用时都作为系统提示的一部分发送
2. Claude 读到这些描述后逐条判断是否与当前任务相关
3. 无论判断结果如何，描述本身已经消耗了输入 tokens

这意味着：
- 10 个插件各注册 5 个技能 = 50 条描述 ≈ 6,000-7,500 tokens 系统提示开销
- 这个开销在每一轮对话的每一次 API 调用中都会重复

此外，某些插件（如 superpowers）还带有 SessionStart hook，会在每次会话开始时注入额外内容到上下文中，进一步增加开销。

### 消耗影响

- 每个技能描述约 100-150 tokens
- 120 条技能描述 ≈ 15,000 tokens/轮 的系统提示开销
- 其中三重复制造成约 10,000 tokens/轮 的纯浪费
- 在 Opus 上，这些额外 tokens 的成本是在 Sonnet 上的 5 倍

### 规范做法

**原则：全局精简，按需加载**

1. **全局只启用核心插件**（5-8 个日常必需的），其余设为 `false`
2. **按项目启用专用插件**：在项目目录创建 `.claude/settings.json`，覆盖全局设置
   ```json
   {
     "enabledPlugins": {
       "marketing-skills@marketingskills": true
     }
   }
   ```
3. **定期检查重复**：如果两个插件的技能列表高度重叠，只保留一个
4. **禁用 ≠ 卸载**：`false` 只是不加载，随时可以改回 `true`

---

## 第2章：模型选择 — 用火箭送外卖

### 踩坑场景

某团队将默认模型设为 `opus[1m]`（最强模型 + 最大上下文窗口），理由是"要最好的效果"。团队的日常工作包括写代码、修 bug、改配置文件、写文档，偶尔做架构设计。

一个月后发现 token 消耗远超预期。分析原因：90% 的任务用 Sonnet 就能很好完成，但每一次调用都在为 Opus 的价格买单。

### 为什么会这样

不同模型的能力差距在日常编码任务上并不明显，但成本差距是固定的：

| 模型 | 输入成本倍数 | 输出成本倍数 | 强项 |
|------|------------|------------|------|
| Opus | 5x | 5x | 复杂推理、架构设计、深度分析 |
| Sonnet | 1x（基准） | 1x | 编码、调试、日常开发 |
| Haiku | ~0.27x | ~0.27x | 轻量任务、子 agent、批处理 |

`[1m]` 后缀表示 1M token 上下文窗口。更大的上下文意味着系统提示中所有内容（规则、技能描述、Memory）都能被塞进去，这本身就放大了前面提到的插件膨胀问题。

### 消耗影响

假设每轮对话的总 token 消耗相同：
- Opus 用户：每 20 轮对话的系统提示成本 ≈ Sonnet 用户的 5 倍
- 如果日均 5 个会话，月成本差距可达 4-5 倍

### 规范做法

**原则：按任务选模型，而不是固定一个**

1. **默认设为 Sonnet**：满足 90% 的日常编码需求
2. **临时切换**：需要深度推理时用 `/model opus`，用完切回
3. **子 agent 用 Haiku**：如果你的规则文件要求自动派遣子 agent，指定子 agent 使用 haiku 可以大幅降低成本
4. **避免 `[1m]` 后缀**：除非你确实在处理超长文件，否则标准上下文窗口已经足够

---

## 第3章：规则文件与系统提示 — 写给 Claude 的话越多，每句都要付费

### 踩坑场景

某团队在 `~/.claude/rules/` 下积累了 15 个规则文件，总计约 19KB。内容涵盖编码风格、安全检查、测试要求、Agent 调度策略、Git 工作流等。

其中最大的问题不是规则太多，而是规则中包含了"强制自动触发"的指令：

> "No user prompt needed: Complex feature requests - Use **planner** agent"
> "Code just written/modified - Use **code-reviewer** agent"

这意味着 Claude 在每个编码任务中都会自动派遣 3-5 个子 agent（planner + tdd-guide + code-reviewer + security-reviewer）。每个子 agent 是独立的对话链，各自重新加载完整的系统提示。

### 为什么会这样

规则文件（`~/.claude/rules/` 和 `CLAUDE.md`）的内容在每次 API 调用时作为系统提示的一部分发送。这与插件技能描述叠加在一起。

规则文件的两种成本：
1. **直接成本**：规则文本本身消耗输入 tokens（约 4 tokens/英文单词，中文更高）
2. **间接成本**：规则中的"强制行为"触发额外的工具调用和子 agent，每个都是独立的 API 调用链

一条"必须自动调用 code-reviewer agent"的规则，看似只有十几个字，但它触发的子 agent 可能消耗数千甚至数万 tokens。

### 消耗影响

- 15 个规则文件（19KB）≈ 6,000 tokens/轮 系统提示开销
- 强制 Agent 调度：每个子 agent 独立加载完整系统提示（包括所有规则和技能描述），相当于重开一个完整对话
- 一个简单功能实现触发 4 个子 agent = 主对话成本 × 5

### 规范做法

**原则：规则精简，用"建议"代替"必须"**

1. **控制总体积**：规则文件总大小建议控制在 10-15KB 以内
2. **用"Consider"代替"Must"**：将"必须自动触发 planner agent"改为"复杂任务时建议使用 planner agent"
3. **不常用的大规则转为 skill**：比如 skill-vetter（4.7KB）只在安装新 skill 时需要，不应该每次都加载
4. **合并相关规则**：把 `coding-style.md` + `patterns.md` 合并，减少文件数和冗余
5. **定期审查**：每月检查一次，删除过时或不再需要的规则

---

## 第4章：Thinking 预算 — 默认的天花板可能太高了

### 踩坑场景

某团队使用 Opus 模型，Extended Thinking 预算保持默认的 31,999 tokens。团队没有意识到这个配置的存在，因为"thinking 看不见，不知道在花钱"。

实际上，大部分日常任务（写代码、改 bug、编辑文件）的 thinking 消耗在 2,000-5,000 tokens 之间。只有复杂的架构设计或多步推理才会用到 10,000+ tokens。

### 为什么会这样

Extended Thinking 是 Claude 在生成回复前的内部推理过程。它使用 **output token** 计价，而 output 的单价远高于 input：

- 在 Opus 上，output 价格是 input 的 5 倍
- Thinking tokens 按 output 价格计费

31,999 的预算意味着每一轮对话中，Claude 最多可以花费 32K output tokens 来"思考"，即使最终只输出几百字的回复。

需要注意：这是**上限**，不是每轮固定消耗。Claude 会根据任务复杂度动态使用。但上限太高意味着遇到复杂任务时没有"刹车"。

### 消耗影响

- 默认 32K 预算 vs 20K 预算：复杂任务时最多多消耗 12K output tokens
- 在 Opus 上，12K output tokens 的成本 ≈ 在 Sonnet 上的 5 倍
- 日常任务不受影响（因为实际用量远低于上限）

### 规范做法

**原则：设一个合理的上限，按需临时调高**

1. **推荐默认值：20,000**：覆盖 95%+ 的任务，复杂推理仍有足够空间
2. **设置方式**：
   - 持久化：`setx MAX_THINKING_TOKENS 20000`（Windows）或写入 shell profile
   - 临时：`export MAX_THINKING_TOKENS=20000`
3. **如果发现回复质量下降**：说明某些任务确实需要更多 thinking 空间，可以临时调高
4. **在会话中切换**：用 `Alt+T`（Windows/Linux）或 `Option+T`（macOS）开关 thinking

---

## 第5章：安全与环境变量 — Key 放错口袋

### 踩坑场景

某团队排查 token 消耗时发现：

1. `GEMINI_API_KEY` 环境变量里存储的是 Anthropic 的 API key（`cr_` 前缀）
2. `OPENAI_API_KEY` 环境变量里存储的是 Google 的 API key（`AIza` 前缀）
3. 一个 `.env` 文件中明文硬编码了 API key，且文件中注释写着"replace immediately"——但已经存在了数周

这意味着：
- 每次调用 Gemini API 的工具会把 Anthropic key 发送到 Google 的端点
- 每次调用 OpenAI API 的工具会把 Google key 发送到 OpenAI 的端点
- 虽然错误的 key 不会被对方认证成功，但 key 值本身已经被传输到了第三方服务器

### 为什么会这样

多个 AI 服务的 Key 管理容易混淆，尤其是：
- 复制粘贴时选错了 key
- 用 `setx` 设置环境变量时没有检查值是否正确
- `.env` 文件中的 key 在测试后忘记轮换

另一个常见问题是 `settings.local.json` 中的权限列表无限累积。每次自动批准的工具调用都会添加一条记录，时间长了可能达到 100+ 条，其中包含过期的一次性命令。

### 消耗影响

- Key 交叉污染本身不直接增加 token 消耗，但存在安全风险
- 如果 key 泄露被他人使用，会产生非预期的消耗
- 宽松的权限配置（特别是 `--dangerously-skip-permissions`）配合大量插件，可能导致无限制的自动执行链

### 规范做法

**原则：Key 正确存放，定期验证**

1. **设置后立即验证**：运行 token-guard 审计或手动检查每个环境变量的前缀是否匹配
   - Anthropic key 应以 `sk-ant-` 或 `cr_` 开头
   - OpenAI key 应以 `sk-` 开头
   - Google/Gemini key 应以 `AIza` 开头
2. **永远不要在 `.env` 中长期保存 key**：测试完立即用环境变量替代，`.env` 文件必须在 `.gitignore` 中
3. **定期清理 `settings.local.json`**：删除不再需要的一次性权限条目
4. **谨慎使用 `--dangerously-skip-permissions`**：它会绕过所有权限检查，配合大量插件时风险极高

---

## 第6章：日常维护 — 配置不是设了就忘的

### 踩坑场景

某团队在初始配置好 Claude Code 后再没有检查过配置状态。半年后：

- `settings.local.json` 累积了 165 条权限规则，其中包含过期的内联脚本
- 规则文件从 3 个增长到 15 个，有些是为临时需求添加后忘记删除的
- 安装的插件从 5 个增长到 18 个，多数是"试用一下"后没有禁用
- Memory 文件在某些项目下累积了数十个，增加了每次加载的开销

### 为什么会这样

Claude Code 的配置是累加的：
- 每次批准工具调用 → 添加权限条目
- 每次安装插件 → 增加技能描述
- 每次创建规则 → 增加系统提示体积
- 每次保存 Memory → 增加上下文开销

但没有内置的"自动清理"机制。这些配置只增不减，直到有人主动审查。

### 消耗影响

配置膨胀是渐进的，很难在某一天突然感知到。但累积效应显著：
- 初始状态（5 个插件、3 个规则文件）：系统提示约 8,000 tokens
- 半年后（18 个插件、15 个规则文件）：系统提示约 35,000 tokens
- 增长了约 4 倍，意味着每轮对话的基础成本增加了 4 倍

### 规范做法

**原则：定期体检，主动瘦身**

1. **每月运行一次 token-guard 审计**：就像代码需要定期 review，配置也需要定期检查
2. **季度清理 checklist**：
   - [ ] 检查 `settings.local.json`，删除不再需要的权限条目
   - [ ] 检查已启用的插件列表，禁用不再使用的
   - [ ] 检查规则文件，删除临时或过时的
   - [ ] 检查 Memory 文件，清理过时的记录
   - [ ] 检查环境变量，确认 key 前缀匹配正确
3. **新同事入职 checklist**：
   - [ ] 默认模型设为 Sonnet
   - [ ] 只启用团队推荐的核心插件（列出名单）
   - [ ] 设置 `MAX_THINKING_TOKENS=20000`
   - [ ] 不使用 `--dangerously-skip-permissions`
   - [ ] 运行 token-guard 确认初始状态健康

---

## 第7章：会话管理 — git commit 就是最好的跨会话记忆

### 踩坑场景

某团队习惯在一个终端里持续工作，一个会话做完功能 A 接着做功能 B，从不开新会话。某个项目的单个会话膨胀到 78MB（主会话 16MB + 4 个 aside_question agent 各 15MB），累积会话数据达到 113MB。

团队不敢关会话，因为"怕 Claude 忘记之前做了什么"。

### 为什么会这样

Claude Code 的会话是有状态的——对话越长，每轮发送的上下文越大，token 消耗递增。同时，某些插件（如 episodic-memory）会在后台自动派遣 aside_question agent 做记忆搜索，这些 agent 的会话数据可以膨胀到 15MB+ 单个。

但"怕忘记"其实是个伪问题。新会话开始时，Claude 可以通过以下途径了解项目状态：
- **代码本身**：直接读文件就是最新状态
- **git log**：提交历史记录了你做了什么、为什么做
- **git status / git diff**：当前未提交的变更
- **Memory 文件**：你主动保存的关键决策
- **CLAUDE.md**：项目约定和上下文

这些信息比一个臃肿的长会话上下文更可靠、更精确。

### 消耗影响

- 会话从 5MB 增长到 50MB：每轮 API 调用的上下文传输量增长了 10 倍
- aside_question agent 膨胀：4 个 × 15MB = 60MB，占总数据量的 55%+
- 长会话中后期的上下文压缩会丢失早期信息，反而不如开新会话可靠

### 规范做法

**原则：一个任务一个会话，git commit 是你的跨会话记忆**

1. **commit message 写清进度**：不只是 `feat: add auth`，而是 `feat: add auth - JWT 验证完成，下一步做 refresh token`
2. **未完成的任务在 commit 中标注**：`feat: 用户列表页 - TODO: 分页和搜索过滤`
3. **长会话及时 `/compact`**：感觉对话变长了就压缩一次
4. **关会话前的习惯**：commit → 确认 git status 干净 → 关。下次新会话看 git log 就能接上
5. **定期清理旧会话数据**：`~/.claude/projects/` 下的旧会话 .jsonl 文件可以安全删除

---

## 第8章：子 Agent 失控 — "自动触发"四个字价值万金

### 踩坑场景

某团队在规则文件中写了这样的指令：

> "No user prompt needed: Complex feature requests - Use **planner** agent"
> "Code just written/modified - Use **code-reviewer** agent"

结果一个简单的功能实现，Claude 自动派遣了 planner → tdd-guide → code-reviewer → security-reviewer 共 4 个子 agent。每个子 agent 独立加载完整系统提示（30K+ tokens）。一个项目累积了 39 个子 agent 会话。

更隐蔽的是，所有子 agent 都继承了主对话的 opus 模型。一个只需要 grep 几个文件的 Explore agent，也在用 opus 的价格跑。

### 为什么会这样

三个因素叠加：

1. **规则写了"自动触发"**：Claude 严格执行指令，只要规则说"No user prompt needed"，它就真的不问就派
2. **子 agent 继承主模型**：Claude Code 没有内置的模型降级机制，不指定 model 参数就继承父级
3. **每个子 agent 独立加载系统提示**：包括所有规则文件、插件技能描述、Memory——跟主对话一样的完整开销

一条 10 个字的规则"必须自动调用 code-reviewer"，实际触发的成本链：
```
10 个字的规则
  → 派遣子 agent
    → 加载 30K tokens 系统提示
      → 子 agent 执行 10-20 轮对话
        → 每轮继续携带 30K 系统提示
= 一条规则导致数万到数十万 tokens 消耗
```

### 消耗影响

- 每个子 agent 的系统提示开销 ≈ 主对话的 100%
- 一个任务触发 4 个子 agent = 主对话成本 × 5
- 所有子 agent 用 opus = 本可以用 haiku 完成的工作付了 19 倍的价格
- 39 个子 agent × 30K tokens 系统提示 = 约 120 万 tokens 仅用于系统提示

### 规范做法

**原则：建议代替必须，按任务选模型，精简输出**

1. **触发方式**：规则中用"Consider suggesting"代替"Must use"，让用户决定是否需要子 agent
2. **模型分档**：
   - 纯检索（搜文件、读代码、git log）→ haiku
   - 常规编码（CRUD、配置、测试）→ sonnet
   - 复杂编码和深度推理 → opus
   - 不确定时 → opus（兜底）
3. **升级条件**：以下情况无论初始分档都用 opus：
   - 跨 3+ 文件联动修改
   - 涉及认证、支付、数据迁移、安全
   - 探索结果存在矛盾
4. **输出规范**：子 agent 只返回文件路径、关键发现、置信度，不要大段粘贴代码或日志，减少回传到主对话的上下文膨胀
