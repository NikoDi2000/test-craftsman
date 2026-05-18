# 安装指南

本指南帮助你在 OpenCode 中安装质量工程师体系的所有 Skill 和 Agent。

## 前提

- 已安装 [OpenCode](https://opencode.ai)
- 已有一个项目目录

## 快速安装

### 1. 复制本仓库到项目根目录

```bash
# 将 test-craftsman 仓库克隆到项目根目录
git clone https://github.com/NikoDi2000/test-craftsman.git
```

或者只复制你需要的部分（见下方"按需安装"）。

### 2. 安装 Agent

将 `agents/` 目录下的 Agent 定义复制到 `.opencode/agents/`：

```bash
mkdir -p .opencode/agents

cp test-craftsman/agents/测试设计师.md .opencode/agents/
cp test-craftsman/agents/实现者.md .opencode/agents/
cp test-craftsman/agents/测试审计员.md .opencode/agents/
cp test-craftsman/agents/集成测试工程师.md .opencode/agents/
```

### 3. 安装 Skill

将需要的 Skill 目录复制到 `.opencode/skills/`：

```bash
mkdir -p .opencode/skills

# 对抗性 TDD（必须）
cp -r test-craftsman/adversarial-tdd .opencode/skills/

# 属性驱动测试（推荐）
cp -r test-craftsman/property-based-testing .opencode/skills/

# API 集成测试（FastAPI 项目必须）
cp -r test-craftsman/api-integration-testing .opencode/skills/
```

### 4. 安装全局规则

```bash
mkdir -p .opencode/rules

# ATDD 全局规则
cp test-craftsman/adversarial-tdd/assets/全局规则模板.md .opencode/rules/测试有效性规则.md

# API 集成测试全局规则
cp test-craftsman/api-integration-testing/assets/全局规则模板.md .opencode/rules/API集成测试规则.md
```

### 5. 配置 opencode.json

在项目根目录创建或编辑 `opencode.json`：

```json
{
  "agent": {
    "build": {
      "permission": {
        "task": {
          "测试设计师": "allow",
          "实现者": "allow",
          "测试审计员": "allow",
          "集成测试工程师": "allow"
        }
      }
    }
  }
}
```

### 6. 配置全局身份

将 `AGENTS.md` 的内容复制到项目根目录的 `.AGENTS.md`：

```bash
cp test-craftsman/AGENTS.md .AGENTS.md
```

### 7. 重启 OpenCode

```bash
opencode
```

## 按需安装

如果你只需要部分功能，可以按以下组合安装：

### 只用对抗性 TDD

```bash
mkdir -p .opencode/agents .opencode/skills .opencode/rules

cp test-craftsman/agents/测试设计师.md .opencode/agents/
cp test-craftsman/agents/实现者.md .opencode/agents/
cp test-craftsman/agents/测试审计员.md .opencode/agents/

cp -r test-craftsman/adversarial-tdd .opencode/skills/

cp test-craftsman/adversarial-tdd/assets/全局规则模板.md .opencode/rules/测试有效性规则.md
```

需要的 Agent：测试设计师 + 实现者 + 测试审计员

### 只用属性驱动测试

```bash
mkdir -p .opencode/agents .opencode/skills

cp test-craftsman/agents/测试设计师.md .opencode/agents/

cp -r test-craftsman/property-based-testing .opencode/skills/
```

需要的 Agent：测试设计师

### 只用 API 集成测试

```bash
mkdir -p .opencode/agents .opencode/skills .opencode/rules

cp test-craftsman/agents/测试设计师.md .opencode/agents/
cp test-craftsman/agents/集成测试工程师.md .opencode/agents/
cp test-craftsman/agents/测试审计员.md .opencode/agents/

cp -r test-craftsman/api-integration-testing .opencode/skills/

cp test-craftsman/api-integration-testing/assets/全局规则模板.md .opencode/rules/API集成测试规则.md
```

需要的 Agent：测试设计师 + 集成测试工程师 + 测试审计员

## 安装后验证

启动 OpenCode 后，尝试以下命令验证安装：

### 验证 ATDD

```
请用对抗性TDD帮我实现一个用户注册功能
```

预期行为：OpenCode 应调度测试设计师 → 实现者 → 测试审计员 三 Agent 对抗流程。

### 验证属性驱动测试

```
请用属性驱动测试验证我的排序函数
```

预期行为：OpenCode 应使用测试设计师，通过三个问题发现属性并生成 PBT 测试。

### 验证 API 集成测试

```
请为我的 FastAPI 用户端点写集成测试
```

预期行为：OpenCode 应调度测试设计师 → 集成测试工程师 → 测试审计员 流程。

## 项目结构参考

安装完成后的项目结构：

```
你的项目/
├── opencode.json                          # OpenCode 主配置
├── .AGENTS.md                             # 全局 Agent 身份
├── .opencode/
│   ├── agents/                            # Agent 定义
│   │   ├── 测试设计师.md
│   │   ├── 实现者.md
│   │   ├── 测试审计员.md
│   │   └── 集成测试工程师.md
│   ├── skills/                            # Skill 定义
│   │   ├── adversarial-tdd/
│   │   │   ├── SKILL.md
│   │   │   ├── references/
│   │   │   └── assets/
│   │   ├── property-based-testing/
│   │   │   ├── SKILL.md
│   │   │   ├── references/
│   │   │   └── assets/
│   │   └── api-integration-testing/
│   │       ├── SKILL.md
│   │       ├── references/
│   │       └── assets/
│   └── rules/                             # 全局规则
│       ├── 测试有效性规则.md
│       └── API集成测试规则.md
└── test-craftsman/                        # 源仓库（可删除）
    ├── AGENTS.md
    ├── agents/
    ├── adversarial-tdd/
    ├── api-integration-testing/
    ├── property-based-testing/
    └── research/
```

## Agent 与 Skill 的协作关系

| Skill | 使用的 Agent | 工作模式 |
|-------|-------------|---------|
| adversarial-tdd | 测试设计师 + 实现者 + 测试审计员 | 三 Agent 对抗 |
| api-integration-testing | 测试设计师 + 集成测试工程师 + 测试审计员 | 设计→验证→审查 |
| property-based-testing | 测试设计师 | 属性发现 + 生成测试 |

## 故障排查

| 问题 | 原因 | 解决 |
|------|------|------|
| Agent 未触发 | opencode.json 中未授权 | 检查 `agent.build.permission.task` 配置 |
| Skill 未加载 | SKILL.md 不在正确位置 | 确认 `.opencode/skills/*/SKILL.md` 存在 |
| 测试设计师看到了实现 | Agent 权限配置错误 | 检查 `.opencode/agents/测试设计师.md` 的 `permission.edit` 是否限制在测试目录 |
| 测试直接通过 | 已有实现或测试设计有误 | 确认测试在实现前确实失败（红灯） |
| 审计员未执行 | 工作流中审计阶段被跳过 | 检查 SKILL.md 中的工作流定义 |
| 规则未生效 | 规则文件不在正确位置 | 确认 `.opencode/rules/` 和 `.AGENTS.md` 存在 |

## 技术栈适配

每个 Skill 都有技术栈特定的参考文档：

| 技术栈 | ATDD 参考 | PBT 参考 | API 集成测试参考 |
|--------|----------|---------|----------------|
| Flutter/Dart | `adversarial-tdd/references/06-Flutter技术栈适配.md` | `property-based-testing/references/02-技术栈适配.md` | — |
| FastAPI/Python | `adversarial-tdd/references/07-FastAPI技术栈适配.md` | `property-based-testing/references/02-技术栈适配.md` | `api-integration-testing/references/03-FastAPI技术栈适配.md` |
| Unity/C# | `adversarial-tdd/references/08-Unity技术栈适配.md` | `property-based-testing/references/02-技术栈适配.md` | — |
