# Layer 11 深度报告：异步与并发测试

> **前置知识**：本报告是 [Layer 1 - 可测试性设计](./layer-01-testability.md) 中"确定性"维度的深度展开——异步和并发是破坏测试确定性的主要来源。并发测试中的竞态条件检测与 [Layer 4 - 变异测试](./layer-04-mutation-testing.md) 的思路一致——通过注入并发干扰来验证测试的敏感性。[Layer 9 - 测试隔离](./layer-09-test-isolation.md) 中的并行测试隔离是本报告的基础。

---

## 一、FastAPI 的 async/sync 混合模型对测试的影响

### 1.1 FastAPI 的路由调度机制

FastAPI 支持同时定义 `async def` 和普通 `def` 路由，但它们的执行方式完全不同：

```python
# async 路由：直接在事件循环中执行
@app.get("/async-endpoint")
async def async_handler():
    await asyncio.sleep(0.1)
    return {"type": "async"}

# sync 路由：在线程池中执行（避免阻塞事件循环）
@app.get("/sync-endpoint")
def sync_handler():
    time.sleep(0.1)
    return {"type": "sync"}
```

**FastAPI 的调度逻辑**（简化）：

```
请求到达
  │
  ├─ 路由是 async def？
  │    └─ 直接 await 调用（在事件循环中）
  │
  └─ 路由是普通 def？
       └─ 提交到线程池（run_in_executor）
           └─ 等待结果
```

### 1.2 混合模型对测试的影响

| 影响维度 | async 路由 | sync 路由 |
|---------|-----------|----------|
| **TestClient 行为** | 同步调用（隐式事件循环） | 同步调用（线程池） |
| **数据库 Session** | 需要 async session | 使用 sync session |
| **并发行为** | 协程并发 | 线程并发 |
| **异常传播** | 直接传播 | 通过 Future 传播 |

### 1.3 测试中的关键陷阱

**陷阱一：在 async 路由中使用同步数据库驱动**

```python
# ❌ 错误：async 路由中使用同步 DB 驱动会阻塞事件循环
@app.get("/users/{id}")
async def get_user(id: int, db: Session = Depends(get_db)):
    user = db.query(User).get(id)  # 同步调用，阻塞事件循环！
    return user

# ✅ 正确：使用 async session
@app.get("/users/{id}")
async def get_user(id: int, db: AsyncSession = Depends(get_async_db)):
    result = await db.execute(select(User).where(User.id == id))
    return result.scalar_one()
```

**陷阱二：TestClient 隐藏了并发问题**

```python
# TestClient 是同步的，每次只处理一个请求
# 它无法暴露并发问题！
def test_concurrent_requests(client):
    # 这两个请求是顺序执行的，不是并发的
    r1 = client.get("/api/v1/users/1")
    r2 = client.get("/api/v1/users/1")
    # 即使有竞态条件，这个测试也不会发现
```

---

## 二、asyncio 事件循环在测试中的管理

### 2.1 pytest-asyncio 的 loop_scope

pytest-asyncio 提供了 `loop_scope` 配置来控制事件循环的生命周期：

```ini
# pytest.ini 或 pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
# loop_scope 可选值：
# "function" - 每个测试函数一个新循环（默认）
# "class" - 每个测试类一个循环
# "module" - 每个模块一个循环
# "package" - 每个包一个循环
# "session" - 整个测试会话一个循环
```

### 2.2 不同 loop_scope 的隔离性

| loop_scope | 隔离性 | 速度 | 风险 |
|-----------|--------|------|------|
| **function** | 最强 | 最慢 | 无 |
| **class** | 强 | 中 | 同一类中测试共享异步状态 |
| **module** | 中 | 快 | 同一模块中测试共享异步状态 |
| **session** | 弱 | 最快 | 全局异步状态泄漏 |

### 2.3 async 测试的正确写法

```python
import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest.fixture
async def async_client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

@pytest.mark.asyncio
async def test_async_endpoint(async_client):
    response = await async_client.get("/api/v1/users")
    assert response.status_code == 200

@pytest.mark.asyncio
async def test_concurrent_async_requests(async_client):
    tasks = [
        async_client.get("/api/v1/users"),
        async_client.get("/api/v1/users"),
        async_client.get("/api/v1/users"),
    ]
    responses = await asyncio.gather(*tasks)
    assert all(r.status_code == 200 for r in responses)
```

### 2.4 事件循环与数据库 Session 的协调

```python
@pytest.fixture
async def async_db_session():
    engine = create_async_engine("sqlite+aiosqlite:///./test.db")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async_session = async_sessionmaker(engine, expire_on_commit=False)
    async with async_session() as session:
        yield session
        await session.rollback()

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()
```

---

## 三、数据库连接池在并发测试下的行为

### 3.1 连接池耗尽

当并发测试数量超过连接池大小时，测试会挂起：

```python
# 默认连接池大小：5
engine = create_async_engine(
    "postgresql+asyncpg://...",
    pool_size=5,
    max_overflow=0
)

# 如果同时运行 10 个测试，每个都需要一个连接
# → 5 个测试获得连接
# → 5 个测试等待连接
# → 如果等待的测试持有事件循环 → 死锁！
```

**解决方案**：

```python
# 方案一：增大连接池
engine = create_async_engine(
    "postgresql+asyncpg://...",
    pool_size=20,
    max_overflow=10
)

# 方案二：使用 NullPool（每次创建新连接）
from sqlalchemy.pool import NullPool

engine = create_async_engine(
    "postgresql+asyncpg://...",
    poolclass=NullPool
)

# 方案三：限制并发测试数量
# pytest -n 4  # 最多 4 个 worker
```

### 3.2 SQLite 并发写入锁

SQLite 只允许一个写入者。并发写入测试会遇到 `database is locked` 错误：

```python
# ❌ 并发写入 SQLite 会失败
@pytest.mark.asyncio
async def test_concurrent_writes(async_client):
    tasks = [
        async_client.post("/api/v1/users", json={"name": f"User {i}"})
        for i in range(10)
    ]
    responses = await asyncio.gather(*tasks)
    # OperationalError: database is locked

# ✅ 解决方案一：使用 WAL 模式
engine = create_async_engine(
    "sqlite+aiosqlite:///./test.db",
    connect_args={"check_same_thread": False},
)
# 在初始化时执行：
# PRAGMA journal_mode=WAL;
# PRAGMA busy_timeout=5000;

# ✅ 解决方案二：使用真实数据库（PostgreSQL）进行并发测试
# SQLite 用于非并发测试，PostgreSQL 用于并发测试
```

### 3.3 连接池配置的测试建议

| 测试场景 | 推荐配置 | 原因 |
|---------|---------|------|
| **单元测试** | SQLite + NullPool | 无并发，无需连接池 |
| **集成测试** | SQLite + pool_size=5 | 少量并发 |
| **并发测试** | PostgreSQL + pool_size=20 | SQLite 不支持并发写入 |
| **压力测试** | PostgreSQL + pool_size=50+ | 需要大量并发连接 |

---

## 四、竞态条件测试方法

### 4.1 并发请求测试

```python
import asyncio
import pytest
from httpx import AsyncClient, ASGITransport

@pytest.mark.asyncio
async def test_race_condition_on_balance_update():
    """测试并发余额更新是否导致数据不一致"""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 初始余额 1000
        await client.post("/api/v1/accounts", json={"balance": 1000})

        # 同时发起 10 个扣款请求，每个扣 200
        tasks = [
            client.post("/api/v1/accounts/1/debit", json={"amount": 200})
            for _ in range(10)
        ]
        responses = await asyncio.gather(*tasks)

        # 检查最终余额
        response = await client.get("/api/v1/accounts/1")
        final_balance = response.json()["balance"]

        # 如果没有并发控制，余额可能是负数
        # 正确行为：只允许 5 次扣款（1000 / 200 = 5）
        assert final_balance >= 0, f"Balance went negative: {final_balance}"
```

### 4.2 Hypothesis Stateful Testing

Hypothesis 的 `RuleBasedStateMachine` 可以系统性地探索并发状态空间：

```python
from hypothesis import settings
from hypothesis.stateful import RuleBasedStateMachine, rule, invariant

class AccountStateMachine(RuleBasedStateMachine):
    def __init__(self):
        super().__init__()
        self.balance = 1000
        self.client = TestClient(app)

    @rule(amount=integers(min_value=1, max_value=500))
    def debit(self, amount):
        response = self.client.post("/api/v1/accounts/1/debit", json={"amount": amount})
        if response.status_code == 200:
            self.balance -= amount

    @rule(amount=integers(min_value=1, max_value=500))
    def credit(self, amount):
        response = self.client.post("/api/v1/accounts/1/credit", json={"amount": amount})
        if response.status_code == 200:
            self.balance += amount

    @invariant()
    def balance_never_negative(self):
        response = self.client.get("/api/v1/accounts/1")
        actual_balance = response.json()["balance"]
        assert actual_balance >= 0, f"Balance is negative: {actual_balance}"

TestAccountStateMachine = AccountStateMachine.TestCase
```

### 4.3 变异假设验证

通过注入延迟来暴露竞态条件：

```python
@pytest.mark.asyncio
async def test_race_with_injected_delay():
    """在关键操作之间注入延迟，暴露竞态条件"""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 创建两个请求，在读取和写入之间注入延迟
        # 这模拟了"读取-修改-写入"不是原子操作的情况
        async def delayed_debit():
            # 读取余额
            r1 = await client.get("/api/v1/accounts/1")
            balance = r1.json()["balance"]
            # 模拟延迟（竞态窗口）
            await asyncio.sleep(0.01)
            # 写入新余额
            return await client.post(
                "/api/v1/accounts/1/debit",
                json={"amount": 200}
            )

        tasks = [delayed_debit() for _ in range(5)]
        responses = await asyncio.gather(*tasks)

        # 验证最终状态一致性
        r = await client.get("/api/v1/accounts/1")
        final_balance = r.json()["balance"]
        assert final_balance >= 0
```

---

## 五、BackgroundTasks 的测试策略

### 5.1 FastAPI BackgroundTasks 的工作原理

```python
from fastapi import BackgroundTasks

@app.post("/api/v1/emails")
async def send_email(
    request: EmailRequest,
    background_tasks: BackgroundTasks
):
    background_tasks.add_task(send_email_async, request.to, request.subject, request.body)
    return {"status": "queued"}
```

**BackgroundTasks 的执行时机**：

```
请求处理完成 → 发送响应 → 执行 BackgroundTasks
```

### 5.2 时序问题

BackgroundTasks 在响应发送后才执行，这导致测试中的时序问题：

```python
# ❌ 错误的测试方式
def test_email_sent(client):
    response = client.post("/api/v1/emails", json={
        "to": "alice@example.com",
        "subject": "Hello",
        "body": "World"
    })
    assert response.status_code == 200

    # 立即检查邮件是否发送
    assert len(email_service.sent_emails) == 1  # ❌ 可能还是 0！
    # 因为 BackgroundTasks 可能还没执行
```

**解决方案一：等待后台任务完成**

```python
def test_email_sent_with_wait(client):
    response = client.post("/api/v1/emails", json={
        "to": "alice@example.com",
        "subject": "Hello",
        "body": "World"
    })
    assert response.status_code == 200

    import time
    time.sleep(0.5)  # 等待后台任务完成
    assert len(email_service.sent_emails) == 1
```

**解决方案二：直接测试后台任务函数**

```python
@pytest.mark.asyncio
async def test_send_email_async_function():
    """直接测试后台任务函数，不通过 BackgroundTasks"""
    await send_email_async("alice@example.com", "Hello", "World")
    assert len(email_service.sent_emails) == 1
    assert email_service.sent_emails[0]["to"] == "alice@example.com"
```

**解决方案三：使用 TestClient 的上下文管理器**

```python
def test_background_task_with_context_manager():
    with TestClient(app) as client:
        response = client.post("/api/v1/emails", json={
            "to": "alice@example.com",
            "subject": "Hello",
            "body": "World"
        })
    # 上下文管理器退出时，会等待所有后台任务完成
    assert len(email_service.sent_emails) == 1
```

### 5.3 后台任务失败不可见

BackgroundTasks 的失败不会影响 HTTP 响应：

```python
async def failing_task():
    raise RuntimeError("Something went wrong")

@app.post("/api/v1/trigger")
async def trigger(background_tasks: BackgroundTasks):
    background_tasks.add_task(failing_task)
    return {"status": "queued"}  # 总是返回 200

# 测试中，后台任务的异常会被吞掉
def test_background_task_failure(client):
    response = client.post("/api/v1/trigger")
    assert response.status_code == 200  # ✅ 通过，但后台任务失败了
```

**解决方案：捕获和记录后台任务异常**

```python
import logging

async def safe_task_wrapper(task_func, *args, **kwargs):
    try:
        await task_func(*args, **kwargs)
    except Exception as e:
        logging.error(f"Background task failed: {e}", exc_info=True)
        raise

# 测试时使用 mock 捕获异常
def test_background_task_failure_is_logged(client, caplog):
    response = client.post("/api/v1/trigger")
    assert response.status_code == 200
    # 检查日志
    assert any("Background task failed" in record.message for record in caplog.records)
```

### 5.4 资源泄漏

后台任务可能持有数据库连接等资源，如果任务失败，资源不会被释放：

```python
# ❌ 后台任务中的数据库连接泄漏
async def leaky_task(db_session):
    user = await db_session.execute(select(User))
    # 如果这里抛异常，db_session 不会关闭
    await do_something_risky(user)

# ✅ 使用 try/finally 确保资源释放
async def safe_task(db_session):
    try:
        user = await db_session.execute(select(User))
        await do_something_risky(user)
    finally:
        await db_session.close()
```

---

## 六、StreamingResponse 和 SSE 的测试

### 6.1 StreamingResponse 测试

```python
from fastapi.responses import StreamingResponse
import io

@app.get("/api/v1/export")
async def export_data():
    async def generate():
        yield "id,name\n"
        async for user in get_all_users():
            yield f"{user.id},{user.name}\n"

    return StreamingResponse(generate(), media_type="text/csv")

def test_streaming_response(client):
    response = client.get("/api/v1/export")
    assert response.status_code == 200
    assert "text/csv" in response.headers["Content-Type"]

    content = response.text
    lines = content.strip().split("\n")
    assert lines[0] == "id,name"
    assert len(lines) > 1
```

### 6.2 SSE（Server-Sent Events）测试

```python
from sse_starlette.sse import EventSourceResponse

@app.get("/api/v1/events")
async def events():
    async def event_generator():
        for i in range(5):
            yield {"data": json.dumps({"count": i}), "event": "update"}
            await asyncio.sleep(0.01)

    return EventSourceResponse(event_generator())

def test_sse(client):
    response = client.get("/api/v1/events")
    assert response.status_code == 200
    assert "text/event-stream" in response.headers["Content-Type"]

    # 解析 SSE 事件
    events = []
    for line in response.text.split("\n"):
        if line.startswith("data:"):
            data = json.loads(line[5:].strip())
            events.append(data)

    assert len(events) == 5
    assert events[0]["count"] == 0
    assert events[4]["count"] == 4
```

### 6.3 异步 SSE 测试

```python
@pytest.mark.asyncio
async def test_sse_async():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        async with client.stream("GET", "/api/v1/events") as response:
            assert response.status_code == 200

            events = []
            async for line in response.aiter_lines():
                if line.startswith("data:"):
                    data = json.loads(line[5:].strip())
                    events.append(data)
                    if len(events) >= 5:
                        break

            assert len(events) == 5
```

---

## 七、并发请求下的死锁检测

### 7.1 死锁的四种类型

| 类型 | 场景 | 检测方法 |
|------|------|---------|
| **数据库死锁** | 两个事务互相等待锁 | 超时检测 |
| **事件循环阻塞** | async 函数中调用同步阻塞代码 | 超时检测 |
| **连接池耗尽** | 所有连接被占用，等待连接的任务无法释放 | 超时检测 |
| **资源循环等待** | A 等 B 的资源，B 等 A 的资源 | 超时 + 日志 |

### 7.2 数据库死锁测试

```python
@pytest.mark.asyncio
async def test_database_deadlock_detection():
    """测试数据库死锁是否被正确检测和处理"""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 创建两个账户
        await client.post("/api/v1/accounts", json={"id": 1, "balance": 1000})
        await client.post("/api/v1/accounts", json={"id": 2, "balance": 1000})

        # 模拟死锁场景：
        # 事务 A：锁定账户 1 → 尝试锁定账户 2
        # 事务 B：锁定账户 2 → 尝试锁定账户 1
        async def transfer(from_id, to_id, amount):
            return await client.post(
                "/api/v1/transfer",
                json={"from": from_id, "to": to_id, "amount": amount}
            )

        # 并发执行两个方向相反的转账
        try:
            results = await asyncio.wait_for(
                asyncio.gather(
                    transfer(1, 2, 100),
                    transfer(2, 1, 100),
                    return_exceptions=True
                ),
                timeout=5.0
            )
            # 至少一个应该成功
            success_count = sum(
                1 for r in results
                if not isinstance(r, Exception) and r.status_code == 200
            )
            assert success_count >= 1
        except asyncio.TimeoutError:
            pytest.fail("Deadlock detected: transfer operations timed out")
```

### 7.3 事件循环阻塞检测

```python
@pytest.mark.asyncio
async def test_no_blocking_in_async_handlers():
    """确保 async 处理器中没有同步阻塞调用"""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        start = asyncio.get_event_loop().time()

        # 发送多个请求
        tasks = [client.get("/api/v1/users") for _ in range(10)]
        responses = await asyncio.gather(*tasks)

        elapsed = asyncio.get_event_loop().time() - start

        # 如果 async 处理器中有阻塞调用，10 个请求会串行执行
        # 每个耗时 0.1s → 总耗时约 1s
        # 如果没有阻塞，10 个请求并发执行 → 总耗时约 0.1s
        assert elapsed < 0.5, f"Requests took {elapsed}s, possible blocking in async handler"
```

### 7.4 连接池耗尽检测

```python
@pytest.mark.asyncio
async def test_connection_pool_exhaustion():
    """测试连接池耗尽时的行为"""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 发起超过连接池大小的请求
        pool_size = 5
        num_requests = pool_size + 5

        async def slow_request():
            return await client.get("/api/v1/slow-endpoint")

        try:
            results = await asyncio.wait_for(
                asyncio.gather(*[slow_request() for _ in range(num_requests)]),
                timeout=10.0
            )
            # 所有请求应该最终完成（连接池会排队等待）
            assert all(r.status_code == 200 for r in results)
        except asyncio.TimeoutError:
            pytest.fail("Connection pool exhaustion: requests timed out")
```

### 7.5 死锁检测的最佳实践

| 实践 | 说明 |
|------|------|
| **所有并发测试设置超时** | `asyncio.wait_for(..., timeout=N)` |
| **使用连接池监控** | 记录 `pool.status()` 在测试前后 |
| **注入延迟暴露竞态** | 在关键路径上 `await asyncio.sleep(0)` |
| **使用 WAL 模式** | SQLite 的 WAL 模式减少锁冲突 |
| **分离并发测试** | 用 `@pytest.mark.concurrent` 标记，单独运行 |

```python
# conftest.py
import pytest

def pytest_configure(config):
    config.addinivalue_line(
        "markers", "concurrent: mark test as concurrent (requires real DB)"
    )

# 运行时可以选择跳过并发测试
# pytest -m "not concurrent"  # 跳过并发测试
# pytest -m "concurrent"      # 只运行并发测试
```

---

## 八、总结：异步与并发测试的核心原则

| # | 原则 | 说明 |
|---|------|------|
| 1 | **TestClient 无法暴露并发问题** | 使用 httpx.AsyncClient 进行并发测试 |
| 2 | **async/sync 混合需要谨慎** | async 路由中不要使用同步阻塞调用 |
| 3 | **事件循环生命周期影响隔离性** | function scope 提供最强隔离 |
| 4 | **连接池配置必须匹配并发量** | 并发测试需要足够的连接池大小 |
| 5 | **SQLite 不适合并发写入测试** | 使用 PostgreSQL 或 WAL 模式 |
| 6 | **竞态条件需要系统性测试** | 并发请求 + Hypothesis Stateful Testing + 延迟注入 |
| 7 | **BackgroundTasks 有三大陷阱** | 时序问题、失败不可见、资源泄漏 |
| 8 | **所有并发测试必须设置超时** | 避免死锁导致测试永远挂起 |
| 9 | **SSE/Streaming 需要异步测试** | 使用 `client.stream()` 逐行读取 |
| 10 | **分离并发测试标记** | `@pytest.mark.concurrent` 独立运行 |

---

*上一章：[Layer 10 - HTTP 语义测试](./layer-10-http-semantic-testing.md)*
*下一章：[Layer 12 - API 安全测试](./layer-12-api-security-testing.md)*
