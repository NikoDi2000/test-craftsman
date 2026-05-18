# Layer 13 深度报告：契约测试与测试可观测性

> **前置知识**：本报告与 [Layer 5 - 形式验证](./layer-05-formal-verification.md) 紧密关联——契约测试本质上是轻量级的形式验证（验证实现符合契约）。[Layer 6 - 预言选择](./layer-06-oracle-selection.md) 中的"部分预言"概念适用于契约测试——契约只验证接口结构，不验证业务逻辑。测试可观测性与 [Layer 7 - 认知循环](./layer-07-cognitive-loop.md) 中的 OODA 循环互补——可观测性加速了 Observe 和 Orient 阶段。

---

## 一、消费者驱动契约测试理论

### 1.1 Martin Fowler 2006 的奠基性论述

Martin Fowler 在 2006 年的文章《Consumer-Driven Contracts》中提出了消费者驱动契约测试（Consumer-Driven Contract Testing, CDCT）的核心思想：

> **"The consumer tells the provider what it expects, and the provider verifies that it meets those expectations."**

**传统集成测试的问题**：

```
消费者 A ←→ 提供者
消费者 B ←→ 提供者
消费者 C ←→ 提供者

问题：
1. 提供者修改 API → 所有消费者都可能受影响
2. 集成测试需要所有服务同时运行 → 成本高
3. 提供者不知道哪些消费者依赖哪些字段 → 不敢删字段
```

**消费者驱动契约的解决方案**：

```
消费者 A 定义契约 → 提供者验证契约
消费者 B 定义契约 → 提供者验证契约
消费者 C 定义契约 → 提供者验证契约

优势：
1. 提供者只需验证消费者声明的契约 → 安全重构
2. 不需要所有服务同时运行 → 独立验证
3. 提供者知道哪些字段被使用 → 安全删除
```

### 1.2 契约的本质

契约不是 API 规范，而是**消费者对提供者的期望**：

| 概念 | 定义 | 示例 |
|------|------|------|
| **API 规范** | 提供者声明的完整 API 能力 | OpenAPI spec（所有端点、所有字段） |
| **契约** | 消费者实际使用的 API 子集 | 消费者 A 只用 GET /users/{id} 的 name 和 email 字段 |

**关键洞察**：

> API 规范告诉你"提供者能做什么"。契约告诉你"消费者需要什么"。两者之间的差距就是重构的安全空间。

```
API 规范（提供者视角）：
  GET /users/{id} → {id, name, email, phone, address, created_at, updated_at, role, ...}

契约 A（消费者 A 视角）：
  GET /users/{id} → {id, name, email}  ← 只用这三个字段

契约 B（消费者 B 视角）：
  GET /users/{id} → {id, role}  ← 只用这两个字段

安全重构空间：
  提供者可以安全删除 phone, address, created_at, updated_at
  因为没有消费者依赖这些字段
```

### 1.3 理论优势

| 优势 | 说明 |
|------|------|
| **独立验证** | 消费者和提供者可以独立测试，不需要端到端环境 |
| **安全重构** | 提供者只要满足所有契约，就可以自由修改实现 |
| **变更感知** | 提供者修改 API 时，立即知道哪些消费者受影响 |
| **文档即测试** | 契约既是文档也是测试，不会过时 |
| **降低成本** | 不需要维护完整的集成测试环境 |

---

## 二、Pact 框架工作原理

### 2.1 两阶段模型

Pact 的工作分为两个阶段：

```
阶段一：消费者端（生成契约）
  1. 消费者编写契约测试
  2. 测试运行时，Pact 捕获 HTTP 交互
  3. 生成契约文件（JSON 格式）

阶段二：提供者端（验证契约）
  1. 提供者从 Broker 获取契约
  2. 重放消费者捕获的请求
  3. 验证提供者的响应是否满足契约
```

### 2.2 消费者端契约测试

```python
from pact import Consumer, Provider, Like, EachLike

pact = Consumer("UserService").has_pact_with(Provider("OrderService"))

def test_get_user_orders():
    (
        pact
        .upon_receiving("a request for user orders")
        .with_request("GET", "/api/v1/users/1/orders")
        .will_respond_with(200, body={
            "orders": EachLike({
                "id": Like(1),
                "total": Like(99.99),
                "status": Like("completed")
            }),
            "total_count": Like(5)
        })
    )

    with pact:
        response = requests.get("http://localhost:1234/api/v1/users/1/orders")
        assert response.status_code == 200
        assert len(response.json()["orders"]) > 0
```

### 2.3 匹配规则

Pact 提供了多种匹配规则来处理动态数据：

| 匹配器 | 含义 | 示例 |
|--------|------|------|
| `Like(value)` | 类型匹配，值不重要 | `Like(1)` → 任何整数 |
| `Term(regex, value)` | 正则匹配 | `Term(r"\d{4}", "2024")` → 任何四位数字 |
| `EachLike(value)` | 数组中每个元素匹配 | `EachLike(Like(1))` → 整数数组 |
| `Like({key: Like(val)})` | 对象结构匹配 | 嵌套结构 |

```python
from pact import Like, Term, EachLike

def test_create_order_contract():
    (
        pact
        .upon_receiving("a request to create an order")
        .with_request("POST", "/api/v1/orders", body={
            "user_id": Like(1),
            "items": EachLike({
                "product_id": Like(1),
                "quantity": Like(2)
            })
        })
        .will_respond_with(201, body={
            "id": Term(r"\d+", "123"),  # 任何数字字符串
            "status": Like("pending"),
            "created_at": Term(
                r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}",
                "2024-01-01T00:00:00"
            )
        })
    )
```

### 2.4 Pact Broker

Pact Broker 是契约的共享中心：

```
消费者 CI → 生成契约 → 推送到 Broker
提供者 CI → 从 Broker 拉取契约 → 验证 → 推送验证结果
消费者 CI → 检查验证结果 → 决定是否部署
```

### 2.5 Provider States

Provider States 让提供者在验证不同契约时设置不同的初始状态：

```python
# 消费者端：声明需要的 Provider State
(
    pact
    .upon_receiving("a request for user orders when user has 3 orders")
    .given("user 1 has 3 orders")  # Provider State
    .with_request("GET", "/api/v1/users/1/orders")
    .will_respond_with(200, body={
        "orders": EachLike({...}, min=3),
        "total_count": Like(3)
    })
)

# 提供者端：实现 Provider State 设置
@app.post("/_pact/provider_states")
async def setup_provider_state(request: dict):
    state = request.get("state")
    if state == "user 1 has 3 orders":
        db.add(Order(user_id=1, total=10))
        db.add(Order(user_id=1, total=20))
        db.add(Order(user_id=1, total=30))
        db.commit()
    return {"result": "ok"}
```

---

## 三、OpenAPI Schema 验证测试

### 3.1 Schemathesis

Schemathesis 是基于 OpenAPI Schema 的自动测试工具，它从 Schema 中自动生成测试用例：

```bash
# 基本用法
schemathesis run http://localhost:8000/openapi.json

# 只测试特定端点
schemathesis run http://localhost:8000/openapi.json \
  --endpoint="/api/v1/users" \
  --method=POST

# 使用 Hypothesis 策略
schemathesis run http://localhost:8000/openapi.json \
  --hypothesis-max-examples=1000
```

### 3.2 三种测试策略

**策略一：Schema 一致性测试**

验证 API 的实际行为是否与 OpenAPI Schema 一致：

```python
import schemathesis
from hypothesis import settings

schema = schemathesis.from_path("openapi.json")

@schema.parametrize()
@settings(max_examples=50)
def test_api_schema_compliance(case):
    """测试 API 是否符合 OpenAPI Schema"""
    response = case.call()
    case.validate_response(response)
```

**策略二：模糊测试**

使用随机/边界值输入测试 API 的鲁棒性：

```python
from hypothesis import strategies as st, given

@schema.parametrize(endpoint="/api/v1/users", method="POST")
@settings(max_examples=200)
def test_user_creation_fuzz(case):
    """模糊测试用户创建端点"""
    response = case.call()
    # 不应该返回 500
    assert response.status_code != 500
    # 如果返回 4xx，错误消息应有意义
    if 400 <= response.status_code < 500:
        body = response.json()
        assert "detail" in body
```

**策略三：属性测试**

验证 API 的不变量：

```python
@given(user_id=st.integers(min_value=1, max_value=10000))
def test_get_user_idempotent(user_id, client):
    """GET /users/{id} 是幂等的"""
    r1 = client.get(f"/api/v1/users/{user_id}")
    r2 = client.get(f"/api/v1/users/{user_id}")
    assert r1.status_code == r2.status_code
    if r1.status_code == 200:
        assert r1.json() == r2.json()
```

### 3.3 与 PBT（Property-Based Testing）的关系

| 维度 | Schema 验证 | PBT |
|------|-----------|-----|
| **输入来源** | OpenAPI Schema 定义 | Hypothesis 策略 |
| **测试重点** | API 是否符合规范 | API 是否满足不变量 |
| **发现 bug 类型** | Schema 不一致、缺失验证 | 逻辑错误、边界条件 |
| **互补性** | 高 | 高 |

---

## 四、Breaking Changes 检测策略

### 4.1 变更分类

| 变更类型 | 示例 | 影响 | 检测方法 |
|---------|------|------|---------|
| **Breaking：删除端点** | DELETE /api/v1/old | 消费者 404 | oasdiff |
| **Breaking：删除字段** | 删除响应中的 email | 消费者解析失败 | 契约测试 |
| **Breaking：修改字段类型** | id: int → str | 消费者类型错误 | Schema diff |
| **Breaking：添加必填字段** | 请求中新增 required field | 消费者 422 | Schema diff |
| **Non-breaking：添加可选字段** | 响应中新增 optional field | 无影响 | 无需检测 |
| **Non-breaking：添加端点** | 新增 GET /api/v1/new | 无影响 | 无需检测 |

### 4.2 oasdiff

oasdiff 是 OpenAPI Breaking Changes 检测工具：

```bash
# 比较两个版本的 OpenAPI Schema
oasdiff breaking old_schema.json new_schema.json

# 输出示例：
# BREAKING CHANGE: api-deleted - Deleted endpoint: GET /api/v1/old
# BREAKING CHANGE: response-property-removed - Removed property: email from response of GET /api/v1/users/{id}
# BREAKING CHANGE: request-property-added-required - Added required property: phone to request of POST /api/v1/users
```

### 4.3 CI/CD 集成

```yaml
# GitHub Actions: Breaking Changes 检测
name: API Compatibility Check

on: [pull_request]

jobs:
  breaking-changes:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install oasdiff
        run: |
          curl -s https://raw.githubusercontent.com/Tufin/oasdiff/main/install.sh | sh

      - name: Check Breaking Changes
        run: |
          # 获取 main 分支的 Schema
          git show main:openapi.json > old_schema.json
          # 当前分支的 Schema
          cp openapi.json new_schema.json
          # 检测 Breaking Changes
          oasdiff breaking old_schema.json new_schema.json --fail-on WARN
```

### 4.4 缓解策略

| 策略 | 说明 | 示例 |
|------|------|------|
| **版本化** | 新版本使用新端点 | `/api/v2/users` |
| **Sunset Header** | 通知废弃时间 | `Sunset: Sat, 01 Jan 2025 00:00:00 GMT` |
| **渐进式迁移** | 旧端点继续支持一段时间 | 同时支持 v1 和 v2 |
| **Feature Flag** | 通过配置控制行为 | `?include_email=true` |
| **向后兼容的修改** | 添加而非删除 | 新增可选字段而非删除旧字段 |

---

## 五、契约测试与集成测试的关系

### 5.1 互补而非替代

```
契约测试 ≠ 替代集成测试
契约测试 = 补充集成测试

契约测试回答："消费者和提供者是否遵守了约定的接口？"
集成测试回答："消费者和提供者一起工作时是否正确？"
```

| 维度 | 契约测试 | 集成测试 |
|------|---------|---------|
| **范围** | 接口契约 | 完整交互 |
| **速度** | 快（无网络） | 慢（需要真实服务） |
| **覆盖** | 接口一致性 | 端到端正确性 |
| **发现** | Breaking Changes | 运行时集成问题 |
| **不能发现** | 性能问题、序列化差异 | — |
| **成本** | 低 | 高 |

### 5.2 测试金字塔中的位置

```
        /\
       /  \        ← E2E 测试（少量）
      / E2E \
     /--------\
    /          \   ← 集成测试（适量）
   / Integration \
  /----+---------\
 /     |          \ ← 契约测试（适量，替代部分集成测试）
/ Contract + Unit  \
--------------------
```

### 5.3 何时用契约测试 vs 集成测试

| 场景 | 推荐 | 原因 |
|------|------|------|
| **团队间服务交互** | 契约测试 | 无法控制对方团队，需要明确契约 |
| **同一团队内服务** | 集成测试 | 可以直接协调，集成测试更直接 |
| **第三方 API** | 契约测试 | 无法运行第三方的集成测试 |
| **关键业务流程** | 两者都用 | 契约测试保接口，集成测试保流程 |
| **新服务快速迭代** | 契约测试 | 快速反馈，不需要完整环境 |

---

## 六、FastAPI 的 OpenAPI 自动生成与契约测试的结合

### 6.1 FastAPI 自动生成 OpenAPI Schema

FastAPI 自动从路由定义生成 OpenAPI Schema：

```python
from fastapi import FastAPI
from pydantic import BaseModel

class UserResponse(BaseModel):
    id: int
    name: str
    email: str

class UserCreate(BaseModel):
    name: str
    email: str

app = FastAPI()

@app.post("/api/v1/users", response_model=UserResponse, status_code=201)
async def create_user(user: UserCreate):
    ...

@app.get("/api/v1/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: int):
    ...
```

FastAPI 自动生成的 OpenAPI Schema 包含：
- 所有端点的路径和方法
- 请求体和响应体的 Schema
- 路径参数和查询参数
- 状态码和错误响应

### 6.2 利用自动生成的 Schema 进行契约验证

```python
import json
import pytest
from fastapi.testclient import TestClient

def test_openapi_schema_is_valid(client):
    """OpenAPI Schema 应该是有效的"""
    response = client.get("/openapi.json")
    assert response.status_code == 200
    schema = response.json()

    # 验证基本结构
    assert "openapi" in schema
    assert schema["openapi"].startswith("3.")
    assert "paths" in schema
    assert "components" in schema

def test_response_matches_openapi_schema(client, existing_user):
    """实际响应应匹配 OpenAPI Schema"""
    import jsonschema

    schema = client.get("/openapi.json").json()
    user_schema = schema["components"]["schemas"]["UserResponse"]

    response = client.get(f"/api/v1/users/{existing_user.id}")
    assert response.status_code == 200

    # 验证响应体符合 Schema
    jsonschema.validate(response.json(), user_schema)
```

### 6.3 Schema 驱动的契约测试

```python
import schemathesis

schema = schemathesis.from_pytest_fixture("openapi_schema")

@pytest.fixture
def openapi_schema(client):
    return client.get("/openapi.json").json()

@schema.parametrize()
def test_contract_compliance(case, client):
    """基于 OpenAPI Schema 的契约测试"""
    response = case.call_on(client)
    case.validate_response(response)
```

---

## 七、契约测试在 CI/CD 中的集成

### 7.1 完整流水线

```
消费者 CI 流水线：
  1. 运行消费者契约测试
  2. 生成契约文件
  3. 推送契约到 Pact Broker
  4. 检查提供者验证结果
  5. 如果提供者验证通过 → 可以部署

提供者 CI 流水线：
  1. 从 Pact Broker 拉取所有消费者契约
  2. 运行提供者验证
  3. 推送验证结果到 Pact Broker
  4. 如果所有契约验证通过 → 可以部署
```

### 7.2 GitHub Actions 示例

```yaml
# 消费者端 CI
name: Consumer CI

on: [push]

jobs:
  contract-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Consumer Tests
        run: |
          pip install pact-python pytest
          pytest tests/contract/ --pact-broker-url=${{ secrets.PACT_BROKER_URL }}
          # 自动发布契约到 Broker

      - name: Check Provider Verification
        run: |
          pact-broker can-i-deploy \
            --pacticipant=UserService \
            --version=${{ github.sha }} \
            --to=production \
            --broker-url=${{ secrets.PACT_BROKER_URL }}

# 提供者端 CI
name: Provider CI

on: [push]

jobs:
  verify-contracts:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_DB: test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
    steps:
      - uses: actions/checkout@v4
      - name: Verify Consumer Contracts
        run: |
          pip install pact-python pytest
          pytest tests/contract/provider/ \
            --pact-broker-url=${{ secrets.PACT_BROKER_URL }} \
            --provider-version=${{ github.sha }} \
            --provider-tags=${{ github.ref_name }}
          # 自动推送验证结果到 Broker
```

---

## 八、OpenTelemetry 在测试中的应用

### 8.1 三种模式

OpenTelemetry（OTel）在测试中的应用有三种模式：

| 模式 | 说明 | 用途 |
|------|------|------|
| **采集模式** | 在测试中采集遥测数据 | 调试测试失败、理解测试行为 |
| **验证模式** | 验证遥测数据的正确性 | 确保可观测性本身是正确的 |
| **断言模式** | 基于遥测数据进行断言 | 替代传统断言，验证分布式行为 |

### 8.2 采集模式

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

@pytest.fixture
def tracer_provider():
    exporter = InMemorySpanExporter()
    provider = TracerProvider()
    provider.add_span_processor(SimpleSpanProcessor(exporter))
    trace.set_tracer_provider(provider)
    yield provider
    provider.shutdown()

@pytest.fixture
def span_exporter(tracer_provider):
    return tracer_provider.get_span_processor().exporter

def test_user_creation_emits_telemetry(client, span_exporter):
    """测试用户创建是否发出正确的遥测数据"""
    response = client.post("/api/v1/users", json={
        "name": "Alice",
        "email": "alice@example.com"
    })
    assert response.status_code == 201

    spans = span_exporter.get_finished_spans()
    user_spans = [s for s in spans if s.name == "create_user"]
    assert len(user_spans) == 1

    span = user_spans[0]
    assert span.attributes["user.name"] == "Alice"
    assert span.attributes["http.status_code"] == 201
```

### 8.3 验证模式

```python
def test_telemetry_correctness(client, span_exporter):
    """验证遥测数据本身的正确性"""
    client.get("/api/v1/users")

    spans = span_exporter.get_finished_spans()

    for span in spans:
        # 验证 span 名称格式
        assert span.name.startswith("GET") or span.name.startswith("POST")

        # 验证 HTTP 属性存在
        if "http.method" in span.attributes:
            assert span.attributes["http.method"] in ("GET", "POST", "PUT", "DELETE")
            assert "http.status_code" in span.attributes
            assert "http.url" in span.attributes

        # 验证 span 状态
        if span.status.is_ok:
            assert span.attributes.get("http.status_code", 600) < 400
```

### 8.4 断言模式

```python
def test_trace_spans_form_correct_dag(client, span_exporter):
    """验证 trace 中的 span 形成正确的有向无环图"""
    client.get("/api/v1/users/1")

    spans = span_exporter.get_finished_spans()
    root_spans = [s for s in spans if s.parent is None]
    assert len(root_spans) == 1, "Should have exactly one root span"

    child_spans = [s for s in spans if s.parent is not None]
    for child in child_spans:
        assert child.parent.span_id == root_spans[0].context.span_id

def test_span_duration_within_sla(client, span_exporter):
    """验证 span 持续时间在 SLA 内"""
    client.get("/api/v1/users")

    spans = span_exporter.get_finished_spans()
    for span in spans:
        duration_ms = (span.end_time - span.start_time) / 1_000_000
        assert duration_ms < 500, f"Span {span.name} took {duration_ms}ms, exceeding SLA"
```

---

## 九、分布式追踪测试

### 9.1 Trace-based Testing

Trace-based Testing 是一种基于分布式追踪的测试方法，它通过验证 trace 的结构和属性来判断系统行为是否正确：

```
传统测试：验证输入 → 输出
Trace-based Testing：验证输入 → trace → 输出

优势：
1. 可以验证分布式系统的内部行为
2. 可以断言跨服务调用链
3. 可以验证异步处理是否正确
4. 可以检测性能回归
```

### 9.2 Tracetest

Tracetest 是一个基于 OpenTelemetry 的测试工具：

```yaml
# tracetest.yaml - 测试定义
type: Test
spec:
  name: "Create User API Test"
  trigger:
    type: http
    httpRequest:
      url: http://localhost:8000/api/v1/users
      method: POST
      headers:
        Content-Type: application/json
      body: '{"name": "Alice", "email": "alice@example.com"}'
  specs:
    - name: "HTTP status code is 201"
      selector: span[tracetest.span.type="http" name="POST /api/v1/users"]
      assertions:
        - attr:http.status_code = 201

    - name: "Database insert occurred"
      selector: span[tracetest.span.type="database" name="insert users"]
      assertions:
        - attr:db.operation = "INSERT"
        - attr:db.system = "postgresql"

    - name: "Email notification sent"
      selector: span[tracetest.span.type="messaging" name="send_email"]
      assertions:
        - attr:messaging.destination = "email-queue"
```

### 9.3 自定义 Trace-based Testing

```python
@pytest.mark.asyncio
async def test_order_creates_correct_trace(async_client, span_exporter):
    """验证下单流程产生正确的追踪链"""
    response = await async_client.post("/api/v1/orders", json={
        "user_id": 1,
        "items": [{"product_id": 1, "quantity": 2}]
    })
    assert response.status_code == 201

    spans = span_exporter.get_finished_spans()

    # 验证追踪链包含预期的 span
    span_names = [s.name for s in spans]
    assert "POST /api/v1/orders" in span_names
    assert "create_order" in span_names
    assert "reserve_inventory" in span_names
    assert "process_payment" in span_names

    # 验证因果关系
    order_span = next(s for s in spans if s.name == "create_order")
    inventory_span = next(s for s in spans if s.name == "reserve_inventory")
    assert inventory_span.parent.span_id == order_span.context.span_id
```

---

## 十、测试可观测性

### 10.1 日志关联

测试日志应与 trace ID 关联，便于调试：

```python
import logging
import structlog

def test_with_correlated_logs(client, caplog):
    """测试日志应包含 trace_id，便于关联"""
    with caplog.at_level(logging.INFO):
        response = client.get("/api/v1/users/1")

    # 检查日志中包含 trace_id
    for record in caplog.records:
        if hasattr(record, "trace_id"):
            assert record.trace_id is not None
            break
    else:
        pytest.fail("No log records contain trace_id")
```

### 10.2 覆盖率对齐

测试覆盖率应与代码变更对齐：

```python
# 覆盖率报告应包含以下维度
# 1. 行覆盖率：哪些行被执行了
# 2. 分支覆盖率：哪些分支被执行了
# 3. 函数覆盖率：哪些函数被调用了
# 4. 变更覆盖率：变更的代码是否被测试覆盖

# pytest-cov 配置
# pytest --cov=app --cov-report=term-missing --cov-branch
```

**覆盖率对齐矩阵**：

| 覆盖率类型 | 目标 | 工具 | 意义 |
|-----------|------|------|------|
| **行覆盖率** | >80% | pytest-cov | 基本覆盖 |
| **分支覆盖率** | >70% | pytest-cov --cov-branch | 逻辑覆盖 |
| **变更覆盖率** | >90% | diff-cover | 新代码覆盖 |
| **API 覆盖率** | 100% | 自定义 | 每个端点至少一个测试 |

### 10.3 趋势分析

测试可观测性应包含趋势分析：

```
跟踪的指标：
1. 测试通过率趋势（是否在下降？）
2. 测试执行时间趋势（是否在变慢？）
3. Flaky Test 比例趋势（是否在增加？）
4. 覆盖率趋势（是否在下降？）
5. 变异得分趋势（是否在下降？）
6. Bug 逃逸率趋势（测试通过但生产出 bug？）
```

### 10.4 成熟度模型

测试可观测性的成熟度分为五个级别：

| 级别 | 名称 | 特征 | 工具 |
|------|------|------|------|
| **L1** | 基础 | 测试通过/失败 + 覆盖率 | pytest + pytest-cov |
| **L2** | 增强 | Flaky Test 检测 + 趋势 | pytest-rerunfailures + CI 报告 |
| **L3** | 关联 | 测试 ↔ 代码变更关联 | diff-cover + Codecov |
| **L4** | 追踪 | 测试 ↔ 分布式追踪关联 | OpenTelemetry + Tracetest |
| **L5** | 预测 | 基于历史数据预测测试风险 | ML 模型 + 自定义分析 |

**成熟度递进路径**：

```
L1: 基础
  "测试通过了吗？覆盖率多少？"
  ↓
L2: 增强
  "哪些测试是 Flaky？执行时间趋势如何？"
  ↓
L3: 关联
  "这次变更影响了哪些测试？哪些变更没有测试覆盖？"
  ↓
L4: 追踪
  "这个测试覆盖了哪些服务？追踪链是否正确？"
  ↓
L5: 预测
  "这次变更的测试风险有多高？哪些测试最可能失败？"
```

---

## 十一、总结：契约测试与测试可观测性的核心原则

| # | 原则 | 说明 |
|---|------|------|
| 1 | **契约是消费者的期望，不是提供者的规范** | 契约定义"消费者需要什么"，而非"提供者能做什么" |
| 2 | **Pact 的两阶段模型是核心** | 消费者生成契约，提供者验证契约 |
| 3 | **OpenAPI Schema 是天然的契约来源** | FastAPI 自动生成，Schemathesis 自动验证 |
| 4 | **Breaking Changes 必须自动检测** | oasdiff + CI/CD = 不可能意外破坏兼容性 |
| 5 | **契约测试与集成测试互补** | 契约测试保接口一致性，集成测试保端到端正确性 |
| 6 | **FastAPI 的 Schema 自动生成降低契约维护成本** | 代码即契约，无需手动维护 |
| 7 | **契约测试必须集成到 CI/CD** | can-i-deploy 门控确保安全部署 |
| 8 | **OpenTelemetry 有三种测试模式** | 采集、验证、断言——递进使用 |
| 9 | **Trace-based Testing 验证分布式行为** | 基于追踪链断言，而非仅输入输出 |
| 10 | **测试可观测性是持续改进的基础** | 从 L1 到 L5 逐步提升，数据驱动决策 |

---

*上一章：[Layer 12 - API 安全测试](./layer-12-api-security-testing.md)*
*本系列完。*
