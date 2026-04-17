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

## 第4章：Reasoning Depth — effort 取代了 Thinking 预算

> 本章在 v1.1.0 完整重写。Opus 4.7（2026-04）之后，原来的固定 thinking 预算机制已废弃，替换为 adaptive reasoning + effortLevel 五档。旧的 `MAX_THINKING_TOKENS` / `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` / `alwaysThinkingEnabled` 对 4.7+ 无效。

### 踩坑场景

某团队升级到 Opus 4.7 后，依然保留着 4.6 时代的配置：
- `.bashrc` 中 `export MAX_THINKING_TOKENS=20000`
- `~/.claude/rules/common/performance.md` 中一整节讲"如何通过 MAX_THINKING_TOKENS 控制 thinking 预算"
- `settings.json` 中 `alwaysThinkingEnabled: true`

团队以为自己在控制成本，实际上这些配置**在 4.7 上完全无效**。更糟的是：
1. 规则文件每次对话都自动加载，把过时的控制方式持续喂给 Claude
2. Claude 读到"设置 MAX_THINKING_TOKENS=20000"会自信地建议用户这么做，持续误导
3. 用户看不到 thinking 内容，以为"设了就起作用了"，不会去验证

直到用 `/token-guard` 审计（v1.1.0 的 `check_stale_rules` + `check_effort_level`）才暴露出来。

### 为什么会这样

**Opus 4.7 的推理机制是根本性变化**：

| 维度 | 4.6 及以前 | 4.7 及之后 |
|------|-----------|-----------|
| 思考控制 | 固定预算（`MAX_THINKING_TOKENS`） | **Adaptive reasoning**，模型自己决定 |
| 开关 | `alwaysThinkingEnabled` | `effortLevel` 五档 |
| 禁用 | `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` | **无法禁用**，永远 adaptive |
| 默认 | 31,999 token 上限 | 五档中的 xhigh |

官方原文：*"Opus 4.7 always uses adaptive reasoning. The fixed thinking budget mode and CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING do not apply to it."*

五档 effortLevel 的本质区别不是"思考预算多少"，而是"**模型何时选择深度思考**"：

| 档位 | 触发深度思考的场景 | 典型行为 |
|------|------------------|---------|
| low | 几乎不触发 | 简单回答、直接检索 |
| medium | 偶尔触发 | 遇到明显复杂问题才想 |
| high | 中等频率 | 多数编码任务，倾向"一次做对" |
| **xhigh** | 高频 | **编码+agentic 甜点位**，会主动反思中间结果、回溯失败的工具调用路径 |
| max | 极高频 | 几乎总是深度思考 |

### 消耗影响

- `MAX_THINKING_TOKENS=20000` 在 4.7 上：**成本影响 = 0**（纯误导）
- `alwaysThinkingEnabled=true/false` 在 4.7 上：**成本影响 = 0**
- 真正的成本杠杆是 effortLevel 档位 + model + [1m] 上下文
- 单次思考的 token 数由模型自己决定，从几百到几万不等

**关键基准（Hex CTO 公开数据）**：
> low-effort Opus 4.7 ≈ medium-effort Opus 4.6

这意味着 4.7 的"省钱档"已经比 4.6 的"常规档"更强——effort 降档的边际价值被 4.7 本身的升级稀释了。

### 规范做法

**原则：删除所有 4.6 时代的 thinking 控制代码，只通过 effortLevel 调节**

1. **settings.json 只配 effortLevel**
   ```json
   {
     "model": "opus[1m]",
     "effortLevel": "xhigh"
   }
   ```
   **删除**：`alwaysThinkingEnabled`、任何 `thinking` 相关字段

2. **清理 shell profile 和环境变量**
   ```bash
   # Windows
   setx MAX_THINKING_TOKENS ""
   setx CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING ""
   # macOS/Linux：从 .bashrc/.zshrc 删除对应 export 行
   ```

3. **清理规则文件中的旧指令**
   - 搜索 `~/.claude/rules/**/*.md` 是否还有 `MAX_THINKING_TOKENS`、`alwaysThinkingEnabled` 引用
   - 参考 `check_stale_rules()` 的扫描结果逐条清理
   - 记忆文件（MEMORY.md）里的旧配置注释也要更新

4. **effortLevel 选择决策树**
   - 不确定？→ 不设，使用 4.7 默认 xhigh
   - 架构/安全/复杂 debug？→ 临时 max（会话中 `/model`）
   - 成本敏感批处理？→ medium + 降级 model 到 sonnet
   - **永远不要**：opus + low/medium（档位倒置），haiku + xhigh/max（浪费）

5. **Never Pair 禁区**
   - `haiku × {xhigh, max}` — 小模型无法利用深度思考
   - `opus × low` — 用昂贵模型却限制它思考
   - `[1m] × max` on routine tasks — 思考 token 被全上下文复算

6. **Tripwire 原则，不是预测**
   - 默认 xhigh，观察到失败（浅薄分析、漏掉边界、结论矛盾）才升 max
   - **不要**预判"这任务复杂，先用 max"——官方明确说 EV 是负的

### 升级后必检清单

每次 Claude 主模型大版本升级（X.Y → X.Y+1），必须检查：

- [ ] `settings.json` 的 `effortLevel` / `alwaysThinkingEnabled` 字段是否需要更新
- [ ] shell 环境变量是否还有 `MAX_THINKING_TOKENS` 等过时预算控制
- [ ] `~/.claude/rules/**/*.md` 是否还有旧机制引用
- [ ] 模型版本号字符串（`Opus 4.5` / `Sonnet 4.6` 等）是否需要刷新
- [ ] 运行 `/token-guard` 的 `check_stale_rules` 自动验证上述清理彻底

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

**原则：建议代替必须，按任务选 model × effort 组合，精简输出**

1. **触发方式**：规则中用"Consider suggesting"代替"Must use"，让用户决定是否需要子 agent

2. **model × effort 分档表（Opus 4.7+）**：

   | 任务类型 | model | effort | 场景 |
   |---------|-------|--------|------|
   | 纯检索 | haiku | low | 搜文件、ls、git log |
   | 简单编辑 | haiku/sonnet | medium | 单文件改动、格式化 |
   | 常规编码 | sonnet | high | CRUD、配置、测试 |
   | 复杂编码 | opus | xhigh | 多文件、算法、agent 逻辑 |
   | 初审 review | sonnet | high | 小 diff、低风险改动 |
   | 深度 review | opus | max ⚠️ | 认证/支付/迁移/并发/安全 |
   | 架构/计划 | opus | max ⚠️ | 系统设计、trade-off 分析 |
   | 不确定 | opus | xhigh | 默认，失败再升档 |

   `⚠️` = 需在子 agent prompt 中明确说明"为什么 xhigh 不够"

3. **升级条件（双维度）**：

   **model 升级到 opus** 当：
   - 跨 3+ 文件联动修改
   - 涉及认证、支付、数据迁移、安全
   - 探索结果存在矛盾

   **effort 升级到 max**（在 opus 之上）当：
   - xhigh 跑出来的结果浅薄或漏掉明显边界
   - 多个子 agent 返回矛盾结论
   - 涉及形式化验证、密码学、合规
   - **不要**预判式升 max"以防万一"——tripwire，不是 prediction

4. **Never Pair 禁区**（v1.1.0 新增）：
   - `haiku × {xhigh, max}` — 小模型无法利用深度思考
   - `opus × low` — 档位倒置，应降 model 到 sonnet
   - `[1m] × max` 用于常规任务 — 思考 token 被全上下文复算

5. **成本对比直觉**：
   - model 降一档 ≈ effort 降一档的 **3-5 倍成本节省**
   - 想省钱优先考虑 `opus+xhigh → sonnet+xhigh`，而不是 `opus+xhigh → opus+high`

6. **输出规范**：子 agent 只返回文件路径、关键发现、置信度，不要大段粘贴代码或日志，减少回传到主对话的上下文膨胀

7. **并发预算**：最多 3 个 opus 子 agent 并发，或 5 个 sonnet 子 agent 并发。Multi-Perspective 5 视角并发请用 sonnet+xhigh，合成阶段才用 opus+max

---

## 第9章：模型版本升级引发的配置漂移（v1.1.0 占位）

> **本章为占位。** 每次 Claude 主模型大版本升级都会在用户侧留下一层"配置沉积"——过时的环境变量、规则文件里的陈旧指令、settings.json 中已废弃的字段。这些沉积会持续污染后续对话的上下文。
>
> v1.1.0 引入的 `check_stale_rules()` 检查已经开始自动化捕获这类问题。本章待累积 2+ 次真实大版本升级案例（目前只有 2026-04 的 4.6→4.7 一例）后补写完整。
>
> 如果你在升级过程中踩到了这类坑，欢迎 [提 issue](https://github.com/Rubbish0-A/token-guard/issues) 贡献案例。
