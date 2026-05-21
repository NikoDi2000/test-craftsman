---
name: using-test-craftsman
description: 当用户开始任何涉及测试的任务时触发。介绍 test-craftsman 质量工程师体系的 Skill 和 Agent 如何协作，帮助主 Agent 选择正确的 Skill 和 Agent 组合。
---

# 使用 test-craftsman

## 体系概览

test-craftsman 是一套质量工程师体系，由 **4 个 Skill** 和 **4 个 Agent** 组成。Skill 定义"做什么"，Agent 定义"谁来做"。

```
┌─────────────────────────────────────────────────┐
│                   主 Agent                       │
│            （协调者，决定用哪个 Skill）             │
└──────────┬──────────┬──────────┬────────────────┘
           │          │          │
     ┌─────▼────┐ ┌──▼─────┐ ┌──▼──────────────┐
     │ ATDD     │ │  PBT   │ │ API 集成测试     │
     │ 三Agent对抗│ │ 单Agent │ │ 三Agent流水线    │
     └─────┬────┘ └──┬─────┘ └──┬──────────────┘
           │         │          │
    ┌──────┼─────┐   │   ┌──────┼──────────┐
    │      │     │   │   │      │          │
  设计师 实现者 审计员 设计师 设计师 工程师  审计员
```

## Skill 选择

| 用户意图 | 触发信号 | 推荐 Skill |
|---------|---------|-----------|
| 写测试、实现功能、修 bug、重构 | "TDD"、"测试"、"单测"、"覆盖率" | `adversarial-tdd` |
| 序列化、数据验证、算法、不变性 | "属性测试"、"PBT"、"Hypothesis" | `property-based-testing` |
| API 端点测试、HTTP 测试、认证测试 | "集成测试"、"TestClient"、"端点测试" | `api-integration-testing` |
| 不确定 | 先问用户要哪种测试 | — |

### 组合使用

| 场景 | 组合 | 原因 |
|------|------|------|
| FastAPI 后端新功能 | ATDD + API 集成测试 | ATDD 覆盖单元层，API 集成测试覆盖链路层 |
| 数据验证逻辑 | ATDD + PBT | ATDD 覆盖已知场景，PBT 覆盖未知边界 |
| 完整后端质量保障 | ATDD + PBT + API 集成测试 | 三层互补 |

## Agent 团队

| Agent | 身份 | temperature | 文件权限 | 核心能力 |
|-------|------|-------------|---------|---------|
| `@测试设计师` | 破坏者 | 0.2 | 只能编辑测试文件 | 风险分析、场景设计、变异假设 |
| `@实现者` | 建设者 | 0.3 | 禁止编辑测试文件 | 最小实现、红绿循环 |
| `@测试审计员` | 审查者 | 0.1 | 完全禁止编辑 | 变异测试、覆盖检查、缺口发现 |
| `@集成测试工程师` | 链路验证者 | 0.2 | 只能编辑测试文件 | HTTP 语义、认证、安全、DB 验证 |

权限隔离是核心设计——测试设计师只能写测试，实现者只能写代码，审计员只能读。详见 `references/01-Agent权限隔离.md`。

## 工作流

三种 Skill 对应三种工作流，详见 `references/02-工作流详解.md`：

| Skill | 模型 | Agent 顺序 | 核心特征 |
|-------|------|-----------|---------|
| `adversarial-tdd` | 对抗 | 设计师 → 实现者 → 审计员 | 上下文隔离，红绿循环 |
| `property-based-testing` | 单 Agent | 设计师 | 三问题发现属性 |
| `api-integration-testing` | 流水线 | 设计师 → 工程师 → 审计员 | 六步法，安全测试 |

## 交接信号

Agent 之间通过标准化信号交接，详见 `references/03-交接信号.md`：

| 信号 | 发送者 | 含义 |
|------|--------|------|
| `TESTS_READY` | 测试设计师 | 测试已写好并确认失败 |
| `GREEN_CONFIRMED` | 实现者 | 实现后测试全部通过 |
| `TESTS_ALREADY_PASSING` | 实现者 | 测试无需实现就通过 |
| `INTEGRATION_TESTS_READY` | 集成测试工程师 | 集成测试已通过 |
| `APPROVE` / `REJECT` | 测试审计员 | 测试有效 / 发现缺口 |

## Agent 模式切换

同一个 Agent 在不同 Skill 下切换工作模式，详见 `references/04-Agent模式切换.md`：

- **@测试设计师**：ATDD 模式（风险矩阵）/ API 集成模式（六步法）/ PBT 模式（三问题）
- **@测试审计员**：ATDD 审计（变异测试）/ API 集成审计（HTTP 语义+安全）

## 跨 Skill 协作

详见 `references/05-跨Skill协作.md`：

- **ATDD + API 集成测试**：ATDD 先行覆盖单元层，API 集成测试后行覆盖链路层
- **ATDD + PBT**：ATDD 覆盖已知场景，PBT 发现未知边界

## 技术栈适配

| 技术栈 | ATDD 参考 | API 集成测试参考 | PBT 参考 |
|--------|----------|-----------------|---------|
| FastAPI | `adversarial-tdd/references/07-FastAPI技术栈适配.md` | `api-integration-testing/references/03-FastAPI技术栈适配.md` | `property-based-testing/references/02-技术栈适配.md` |
| Flutter | `adversarial-tdd/references/06-Flutter技术栈适配.md` | — | `property-based-testing/references/02-技术栈适配.md` |
| Unity | `adversarial-tdd/references/08-Unity技术栈适配.md` | — | `property-based-testing/references/02-技术栈适配.md` |
