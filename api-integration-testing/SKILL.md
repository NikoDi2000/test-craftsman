---
name: api-integration-testing
description: API 集成测试。当用户要求写集成测试、API 测试、端点测试、HTTP 测试，或提到 TestClient、AsyncClient、dependency_overrides 时触发。覆盖 HTTP 请求-响应链路、认证授权、数据库集成、依赖注入测试、HTTP 语义验证、安全测试。支持 FastAPI/Python 项目。
---

# API 集成测试

## 概述

API 集成测试验证 FastAPI 后端的端到端行为：HTTP 请求-响应链路、依赖注入、数据库交互、认证授权流程。这是单元测试（PBT、ATDD）与 E2E 测试之间的关键层。

**与单元测试的区别**：

| 维度 | 单元测试 | API 集成测试 |
|------|----------|--------------|
| 范围 | 单个函数/类 | 完整请求链路 |
| 依赖 | Mock | 真实或受控模拟 |
| 速度 | 快 | 较慢 |
| 置信度 | 低 | 高 |

**理论定位**（基于测试分层理论研究）：

测试金字塔在微服务时代需要调整。Spotify 的测试蜂巢模型和 Martin Fowler 的 Testing Honeycomb 都指出：**集成测试应占最大比例**，因为 API 后端的核心价值在集成层。FastAPI 项目应采用"厚中间"的钻石模型。

## Agent 协作模型

本 Skill 使用共享 Agent 团队，定义在项目根目录 `agents/` 下：

| Agent | 角色 | 本 Skill 中的职责 | 定义文件 |
|-------|------|-------------------|----------|
| `@测试设计师` | 破坏者 | 集成测试场景设计、安全测试设计 | `agents/测试设计师.md` |
| `@集成测试工程师` | 链路验证者 | 编写和执行集成测试、验证 HTTP 链路 | `agents/集成测试工程师.md` |
| `@测试审计员` | 审查者 | 审查集成测试覆盖度、安全缺口 | `agents/测试审计员.md` |

### 工作流

```
@测试设计师 → 分析端点风险、设计测试场景
    ↓
@集成测试工程师 → 编写集成测试代码、运行验证
    ↓
@测试审计员 → 审查 HTTP 语义覆盖、安全覆盖、隔离性
    ↓
发现缺口 → 反馈给 @测试设计师 → 补充场景
```

## 何时触发

- 用户要求"写集成测试"
- 用户要求"测试 API 端点"
- 用户提到"TestClient"、"AsyncClient"
- 用户提到"dependency_overrides"
- 用户提到"API"、"HTTP"、"请求"
- 涉及认证/授权测试
- 涉及数据库集成测试
- 涉及 HTTP 语义验证（状态码、方法语义、缓存）
- 涉及 API 安全测试（注入、BOLA、速率限制）

## 测试设计六步法

写任何集成测试代码前，必须完成以下分析。这六步是 adversarial-tdd 风险矩阵在集成测试层面的特化——ATDD 的六步是通用测试设计，本六步是集成测试专用检查清单。

### 1. 可测试性评估

| 维度 | 评估 | 不满足时 |
|------|------|----------|
| 可控性 | 能否控制请求的每个参数？ | 先重构接口 |
| 可观测性 | 能否观测响应和数据库状态？ | 添加查询端点 |
| 确定性 | 相同输入是否产生相同输出？ | Mock 非确定性依赖 |

### 2. HTTP 语义分析

| 方法 | 安全性 | 幂等性 | 必须验证 |
|------|--------|--------|----------|
| GET | 安全 | 幂等 | 不产生副作用 |
| POST | 不安全 | 非幂等 | 重复创建返回 409 |
| PUT | 不安全 | 幂等 | 全量替换 |
| PATCH | 不安全 | 非幂等 | 部分更新 |
| DELETE | 不安全 | 幂等 | 删除已删除返回 204/404 |

### 3. 状态码覆盖

| 状态码 | 语义 | 必须测试的触发条件 |
|--------|------|-------------------|
| 200 | 成功 | 正常请求 |
| 201 | 创建成功 | POST 创建资源 |
| 204 | 无内容 | DELETE 成功 |
| 400 | 请求格式错误 | JSON 语法错误 |
| 401 | 未认证 | 无/无效 Token |
| 403 | 权限不足 | 有效 Token 但角色不匹配 |
| 404 | 资源不存在 | 不存在的 ID |
| 409 | 冲突 | 重复创建 |
| 422 | 验证错误 | Pydantic 验证失败 |
| 500 | 服务器错误 | 不应泄露内部信息 |

### 4. 认证场景矩阵

| 场景 | 预期状态码 | 验证点 |
|------|-----------|--------|
| 有效 Token | 200/201 | 返回正确数据 |
| 无 Token | 401 | WWW-Authenticate 头存在 |
| 过期 Token | 401 | "expired" 在错误信息中 |
| 伪造 Token | 401 | 签名验证失败 |
| 权限不足 | 403 | 正确拒绝 |
| 跨用户访问 | 403/404 | BOLA 防护 |

### 5. 安全测试清单

| 类别 | 必须测试 | 优先级 |
|------|---------|--------|
| BOLA | 跨用户数据访问 | P0 |
| 注入 | SQL/NoSQL/命令注入 | P0 |
| 认证绕过 | Token 篡改/伪造 | P0 |
| 速率限制 | 超限返回 429 | P1 |
| 数据暴露 | 密码不在响应中 | P0 |
| 配置安全 | 生产禁用 /docs | P1 |

### 6. 数据库状态验证

```python
# 关键场景必须验证数据库状态
def test_create_user(db_session):
    response = client.post("/users/", json={"name": "Alice"})
    assert response.status_code == 201

    user = db_session.query(User).filter_by(name="Alice").first()
    assert user is not None
    assert user.id is not None
```

## 核心工具链

### TestClient vs AsyncClient

| 场景 | 选择 | 原因 |
|------|------|------|
| 同步路由 + 同步 DB | TestClient | 简单易用 |
| async 路由 + async DB | AsyncClient | 支持 await |
| 涉及 lifespan 事件 | TestClient | 自动触发 |

```python
# TestClient（同步）
from fastapi.testclient import TestClient

client = TestClient(app)

def test_endpoint():
    response = client.get("/users/1")
    assert response.status_code == 200
```

```python
# AsyncClient（异步）
import pytest
from httpx import ASGITransport, AsyncClient

@pytest.mark.asyncio
async def test_endpoint_async():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.get("/users/1")
    assert response.status_code == 200
```

**禁止混用**：不要用 TestClient 测试 async 路由的并发行为，TestClient 内部是模拟的异步。

## 测试数据库策略

### 事务回滚（推荐）

每个测试在独立事务中运行，测试结束后回滚，确保隔离。

```python
# conftest.py
@pytest.fixture(scope="function")
def db_session():
    session = TestingSessionLocal()
    transaction = session.begin_nested()  # savepoint
    yield session
    session.rollback()
    transaction.close()
    session.close()

# 注入测试数据库
@pytest.fixture(scope="function")
def client(db_session):
    app.dependency_overrides[get_db] = lambda: db_session
    yield TestClient(app)
    app.dependency_overrides.clear()
```

### 自动清理（必须）

```python
@pytest.fixture(autouse=True)
def clean_overrides():
    yield
    app.dependency_overrides.clear()
```

### 禁止模式

- **禁止** Mock 数据库（应使用事务回滚的真实 DB）
- **禁止** 在测试中 commit
- **禁止** 跨测试共享数据库状态
- **禁止** 使用 `scope="module"` 的数据库 fixture

## 依赖注入测试

### dependency_overrides 核心用法

```python
# 覆盖认证依赖
async def mock_get_current_user():
    return User(id=1, username="testuser")

app.dependency_overrides[get_current_user] = mock_get_current_user
```

### 必须覆盖的依赖类型

| 依赖类型 | 覆盖策略 | 工具 |
|----------|----------|------|
| 数据库 Session | 事务回滚 | 真实 DB |
| 外部 HTTP | pytest-httpx | HTTPXMock |
| Redis 缓存 | fakeredis | 内存实现 |
| 认证服务 | dependency_overrides | 返回假用户 |
| 邮件服务 | dependency_overrides | 捕获内容 |

**禁止**用 `unittest.mock.patch` mock 路由函数——FastAPI 在导入时注册路由，patch 无效。

## 认证测试

### JWT Token 测试助手

```python
def create_test_token(data: dict, expires_delta: timedelta = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=30))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
```

### BOLA（IDOR）测试

```python
def test_user_cannot_access_other_user_data():
    user_token = create_test_token({"sub": "user1", "id": 1})
    response = client.get(
        "/users/2/profile",
        headers={"Authorization": f"Bearer {user_token}"}
    )
    assert response.status_code in [403, 404]
```

## HTTP 语义测试

### 方法语义验证

```python
def test_get_is_safe():
    """GET 不得产生副作用"""
    count_before = client.get("/items/").json()["total"]
    client.get("/items/1")
    count_after = client.get("/items/").json()["total"]
    assert count_before == count_after

def test_delete_is_idempotent():
    """DELETE 幂等性：删除已删除资源返回 204 或 404"""
    client.delete("/items/1")
    response = client.delete("/items/1")
    assert response.status_code in (200, 204, 404)

def test_post_creates_with_location():
    """POST 创建应返回 201 + Location"""
    response = client.post("/items/", json={"name": "New"})
    assert response.status_code == 201
    assert "Location" in response.headers
```

### 缓存行为验证

```python
def test_etag_conditional_get():
    """ETag + If-None-Match → 304"""
    response = client.get("/items/1")
    etag = response.headers["ETag"]

    response = client.get("/items/1", headers={"If-None-Match": etag})
    assert response.status_code == 304
```

## 安全测试

### 注入攻击

```python
def test_sql_injection_in_path():
    response = client.get("/users/1 OR 1=1")
    assert response.status_code in [404, 422]

def test_sql_injection_in_login():
    response = client.post("/token", data={
        "username": "admin'--",
        "password": "anything"
    })
    assert response.status_code == 401
```

### 敏感数据暴露

```python
def test_password_not_in_response():
    response = client.post("/users/", json={
        "name": "Alice", "email": "a@b.com", "password": "Secret123!"
    })
    assert "password" not in response.json()
    assert "password_hash" not in response.json()

def test_error_no_db_leak():
    response = client.post("/users/", json={"email": "duplicate@b.com"})
    detail = response.json().get("detail", "")
    assert "SELECT" not in detail
    assert "INSERT" not in detail
```

## 异步测试

### 事件循环配置

```ini
[tool.pytest.ini_options]
asyncio_mode = "auto"
asyncio_default_fixture_loop_scope = "function"
```

### 并发测试

```python
@pytest.mark.asyncio
async def test_concurrent_update():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        tasks = [
            ac.post("/accounts/1/debit", json={"amount": 50}),
            ac.post("/accounts/1/debit", json={"amount": 30}),
        ]
        responses = await asyncio.gather(*tasks)

        response = await ac.get("/accounts/1")
        assert response.json()["balance"] == expected_balance
```

### BackgroundTasks 测试

```python
def test_background_task_failure_does_not_affect_response():
    with patch("app.tasks.send_email", side_effect=Exception("SMTP error")):
        response = client.post("/send-email", json={"to": "user@example.com"})
        assert response.status_code == 202
```

## 断言策略

### 必须验证

1. HTTP 状态码
2. 响应体关键字段
3. 数据库状态（关键场景）
4. 错误消息格式

### 禁止断言

- 内部实现细节（私有方法调用次数）
- 外部服务行为（应 Mock）
- 精确的时间戳/ID（应检查存在性）

## 测试分层定位

```
单元测试 (ATDD/PBT)          →  纯逻辑、业务规则
API 集成测试 (本 Skill)       →  HTTP 链路、认证、DB、安全
契约测试 (Schemathesis/Pact)  →  Schema 一致性、Breaking Changes
E2E 测试 (未来)               →  完整用户流程
```

## 禁止模式

- 测试间共享状态（数据库、中间件）
- 忘记清除 `dependency_overrides`
- 测试真实外部服务（未 Mock HTTP）
- 断言实现细节
- 在集成测试中 Mock 数据库
- 使用 `scope="module"` 的 fixture
- 用 `patch` mock 路由函数
- 混用 TestClient 和 AsyncClient 测试并发

## 与其他 Skill 配合

| 场景 | 先用 | 再用 |
|------|------|------|
| 新功能开发 | adversarial-tdd（设计测试） | API 集成测试（验证链路） |
| 回归验证 | API 集成测试（快速反馈） | adversarial-tdd（详细审查） |
| 发现 bug | API 集成测试（定位链路） | adversarial-tdd（设计边界用例） |
| 数据边界 | property-based-testing（属性发现） | API 集成测试（端点验证） |
| Schema 变更 | Schemathesis（契约验证） | API 集成测试（行为验证） |

## 参考资料

- 研究报告：`../research/api-integration-testing.md`
- 测试分层理论：`../research/layer-08-test-layering-theory.md`
- 测试隔离理论：`../research/layer-09-test-isolation.md`
- HTTP 语义测试：`../research/layer-10-http-semantic-testing.md`
- 异步并发测试：`../research/layer-11-async-concurrent-testing.md`
- API 安全测试：`../research/layer-12-api-security-testing.md`
- 契约测试与可观测性：`../research/layer-13-contract-testing-and-observability.md`
- 测试数据库配置：`references/01-测试数据库配置.md`
- 认证授权测试：`references/02-认证授权测试.md`
- FastAPI 技术栈适配：`references/03-FastAPI技术栈适配.md`
