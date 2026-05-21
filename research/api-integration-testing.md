# API 集成测试研究索引

本文件是 API 集成测试相关研究的导航入口。深度内容已分散到 Layer 8-13 报告中，本文件仅保留索引和快速参考。

## 研究报告索引

| Layer | 主题 | 核心洞察 |
|-------|------|---------|
| [Layer 8](./layer-08-test-layering-theory.md) | 测试分层理论 | 金字塔→蜂巢→钻石模型演进；FastAPI 应采用"厚中间"策略 |
| [Layer 9](./layer-09-test-isolation.md) | 测试隔离理论 | 强/弱隔离分类；Django TestCase 源码级分析；测试污染9种类型 |
| [Layer 10](./layer-10-http-semantic-testing.md) | HTTP 语义测试 | RFC 9110 方法/状态码/头部语义；Richardson 模型 L0-L3 测试策略 |
| [Layer 11](./layer-11-async-concurrent-testing.md) | 异步并发测试 | async/sync 混合模型陷阱；竞态条件测试；BackgroundTasks 测试策略 |
| [Layer 12](./layer-12-api-security-testing.md) | API 安全测试 | OWASP API Top 10 2023；BOLA/注入/认证绕过测试；SAST/DAST/IAST 分层 |
| [Layer 13](./layer-13-contract-testing-and-observability.md) | 契约测试与可观测性 | Pact 两阶段模型；Schemathesis Schema 验证；OpenTelemetry 测试应用 |

## 通用测试理论（Layer 1-7）

| Layer | 主题 | 与 API 集成测试的关联 |
|-------|------|---------------------|
| [Layer 1](./layer-01-testability.md) | 可测试性设计 | 可控性×可观测性→测试设计六步法的基础 |
| [Layer 2](./layer-02-input-space.md) | 输入空间建模 | 等价类划分→HTTP 参数边界测试 |
| [Layer 3](./layer-03-path-coverage.md) | 路径覆盖 | 状态码路径覆盖 |
| [Layer 4](./layer-04-mutation-testing.md) | 变异测试 | 安全变异（移除权限检查） |
| [Layer 5](./layer-05-formal-verification.md) | 形式验证 | 契约测试≈轻量级形式验证 |
| [Layer 6](./layer-06-oracle-selection.md) | 预言选择 | RFC 规范=最精确的测试预言 |
| [Layer 7](./layer-07-cognitive-loop.md) | 认知循环 | 可观测性加速 OODA 循环 |

## Skill 参考

- `api-integration-testing/SKILL.md`：核心技能定义
- `api-integration-testing/references/01-测试数据库配置.md`：数据库策略
- `api-integration-testing/references/02-认证授权测试.md`：认证测试模式
- `api-integration-testing/references/03-FastAPI技术栈适配.md`：FastAPI 特定场景
