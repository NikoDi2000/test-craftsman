# Layer 12 深度报告：API 安全测试

> **前置知识**：本报告与 [Layer 6 - 预言选择](./layer-06-oracle-selection.md) 紧密关联——安全测试的核心挑战是"如何知道系统是安全的"，这正是预言问题的安全特化。[Layer 2 - 输入空间建模](./layer-02-input-space.md) 中的等价类划分和边界值分析直接适用于注入攻击测试——恶意输入就是输入空间的特殊边界。[Layer 4 - 变异测试](./layer-04-mutation-testing.md) 中的变异算子可以特化为安全变异（如移除权限检查）。

---

## 一、OWASP API Security Top 10 (2023) 完整列表和测试方法

### 1.1 OWASP API Security Top 10 (2023) 概览

OWASP 在 2023 年更新了 API 安全 Top 10，反映了 API 攻击面的最新变化：

| 编号 | 风险 | 2019 版变化 | 核心问题 |
|------|------|-----------|---------|
| **API1:2023** | Broken Object Level Authorization (BOLA) | 保留 #1 | 用户可访问其他用户的数据 |
| **API2:2023** | Broken Authentication | 从 #2 降至 #2 | 认证机制缺陷 |
| **API3:2023** | Broken Object Property Level Authorization | 新增 | 可访问/修改不应访问的属性 |
| **API4:2023** | Unrestricted Resource Consumption | 从 #4 升级 | 缺少速率限制和资源控制 |
| **API5:2023** | Broken Function Level Authorization (BFLA) | 保留 | 普通用户可执行管理操作 |
| **API6:2023** | Unrestricted Access to Sensitive Business Flows | 新增 | 业务流程可被自动化滥用 |
| **API7:2023** | Server Side Request Forgery (SSRF) | 新增 | 服务器发起非预期请求 |
| **API8:2023** | Security Misconfiguration | 保留 | 默认配置不安全 |
| **API9:2023** | Improper Inventory Management | 从 #9 更新 | API 版本和端点管理不当 |
| **API10:2023** | Unsafe Consumption of APIs | 新增 | 盲目信任第三方 API |

### 1.2 每项风险的测试方法

```python
import pytest
from fastapi.testclient import TestClient

# API1:2023 - BOLA 测试
def test_bola_user_cannot_access_other_user_data(client, user_a_token, user_b_id):
    """用户 A 不能访问用户 B 的数据"""
    response = client.get(
        f"/api/v1/users/{user_b_id}",
        headers={"Authorization": f"Bearer {user_a_token}"}
    )
    assert response.status_code in (403, 404)

# API2:2023 - Broken Authentication 测试
def test_expired_token_rejected(client, expired_token):
    """过期的 token 应被拒绝"""
    response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {expired_token}"}
    )
    assert response.status_code == 401

# API5:2023 - BFLA 测试
def test_bfla_regular_user_cannot_access_admin(client, regular_user_token):
    """普通用户不能访问管理端点"""
    response = client.get(
        "/api/v1/admin/users",
        headers={"Authorization": f"Bearer {regular_user_token}"}
    )
    assert response.status_code == 403
```

---

## 二、注入攻击测试

### 2.1 SQL 注入

**FastAPI 的天然防护**：

FastAPI 使用 Pydantic 进行输入验证，参数化查询是默认行为，这天然防止了大部分 SQL 注入：

```python
# FastAPI 的安全默认行为
@app.get("/api/v1/users/{user_id}")
async def get_user(user_id: int):  # Pydantic 强制类型转换
    # user_id 只能是 int，无法注入 SQL
    return await db.execute(select(User).where(User.id == user_id))
```

**绕过场景**：

```python
# ❌ 危险：使用原始 SQL 字符串拼接
@app.get("/api/v1/search")
async def search(q: str):
    query = f"SELECT * FROM items WHERE name LIKE '%{q}%'"
    return await db.execute(text(query))

# 测试 SQL 注入
def test_sql_injection_in_raw_query(client):
    response = client.get("/api/v1/search?q='; DROP TABLE items; --")
    assert response.status_code in (400, 422)
    # 验证表仍然存在
    response2 = client.get("/api/v1/items")
    assert response2.status_code == 200
```

**SQL 注入测试矩阵**：

| 注入向量 | 测试输入 | 预期行为 |
|---------|---------|---------|
| 经典注入 | `' OR '1'='1` | 400/422 或无结果 |
| 联合注入 | `' UNION SELECT * FROM users --` | 400/422 |
| 堆叠注入 | `'; DROP TABLE users; --` | 400/422 |
| 盲注 | `' AND SLEEP(5) --` | 无延迟 |
| 编码绕过 | `%27%20OR%20%271%27%3D%271` | 400/422 |

### 2.2 NoSQL 注入

```python
# MongoDB 注入测试
def test_nosql_injection(client):
    response = client.post("/api/v1/search", json={
        "query": {"$gt": ""}  # MongoDB 操作符注入
    })
    assert response.status_code in (400, 422)
    # 不应返回所有数据
```

### 2.3 命令注入

```python
# 命令注入测试
def test_command_injection(client):
    response = client.get("/api/v1/ping?host=127.0.0.1;cat%20/etc/passwd")
    assert response.status_code in (400, 422)
    assert "root:" not in response.text  # 不应泄露 /etc/passwd

def test_command_injection_via_filename(client):
    response = client.post("/api/v1/files", json={
        "filename": "test.txt; rm -rf /"
    })
    assert response.status_code in (400, 422)
```

---

## 三、认证绕过测试

### 3.1 Token 场景矩阵

| 场景 | Token 状态 | 预期状态码 | 测试 |
|------|-----------|-----------|------|
| 无 Token | 缺失 | 401 | `client.get("/api/v1/users/me")` |
| 无效 Token | 格式错误 | 401 | `Bearer not-a-jwt` |
| 过期 Token | 过期 | 401 | `Bearer expired.jwt.token` |
| 篡改签名 | 签名不匹配 | 401 | 修改 payload 后重新编码 |
| 错误受众 | audience 不匹配 | 401 | 为其他服务签发的 token |
| 有效 Token | 正常 | 200 | 正确的 token |

```python
def test_auth_token_matrix(client, valid_token, expired_token, tampered_token, wrong_audience_token):
    protected_endpoint = "/api/v1/users/me"

    # 无 Token
    assert client.get(protected_endpoint).status_code == 401

    # 无效格式
    assert client.get(protected_endpoint, headers={
        "Authorization": "Bearer not-a-jwt"
    }).status_code == 401

    # 过期 Token
    assert client.get(protected_endpoint, headers={
        "Authorization": f"Bearer {expired_token}"
    }).status_code == 401

    # 篡改签名
    assert client.get(protected_endpoint, headers={
        "Authorization": f"Bearer {tampered_token}"
    }).status_code == 401

    # 错误受众
    assert client.get(protected_endpoint, headers={
        "Authorization": f"Bearer {wrong_audience_token}"
    }).status_code == 401

    # 有效 Token
    assert client.get(protected_endpoint, headers={
        "Authorization": f"Bearer {valid_token}"
    }).status_code == 200
```

### 3.2 算法混淆攻击（JWT）

算法混淆攻击（CVE-2016-10555 类）利用 JWT 库对 `alg: none` 的支持：

```python
def test_jwt_algorithm_confusion(client):
    """测试 JWT 算法混淆攻击"""
    import base64
    import json

    # 构造 alg: none 的 JWT
    header = base64.urlsafe_b64encode(
        json.dumps({"alg": "none", "typ": "JWT"}).encode()
    ).rstrip(b"=").decode()
    payload = base64.urlsafe_b64encode(
        json.dumps({"sub": "admin", "role": "admin"}).encode()
    ).rstrip(b"=").decode()

    none_token = f"{header}.{payload}."

    response = client.get("/api/v1/admin/users", headers={
        "Authorization": f"Bearer {none_token}"
    })
    assert response.status_code == 401  # 应拒绝 alg=none

def test_jwt_rs256_to_hs256_confusion(client, public_key):
    """测试 RS256 → HS256 算法混淆"""
    # 攻击者用公钥作为 HMAC 密钥签发 token
    import jwt
    payload = {"sub": "admin", "role": "admin"}
    forged_token = jwt.encode(payload, public_key, algorithm="HS256")

    response = client.get("/api/v1/admin/users", headers={
        "Authorization": f"Bearer {forged_token}"
    })
    assert response.status_code == 401  # 应拒绝 HS256 签名
```

### 3.3 角色伪造

```python
def test_role_forgery_in_token(client, regular_user_token):
    """普通用户的 token 不能伪造 admin 角色"""
    # 即使修改 token 中的 role 字段，签名验证会失败
    response = client.get("/api/v1/admin/users", headers={
        "Authorization": f"Bearer {regular_user_token}"
    })
    assert response.status_code == 403

def test_role_forgery_via_request_body(client, admin_token):
    """不能通过请求体伪造角色"""
    response = client.post("/api/v1/users", json={
        "name": "Hacker",
        "email": "hacker@evil.com",
        "role": "admin"  # 尝试在请求体中设置角色
    }, headers={"Authorization": f"Bearer {admin_token}"})
    # 即使创建成功，role 也不应来自请求体
    created_user = response.json()
    if response.status_code == 201:
        assert created_user.get("role") != "admin"
```

---

## 四、BOLA（Broken Object Level Authorization）测试

### 4.1 IDOR（Insecure Direct Object Reference）

IDOR 是 BOLA 最常见的形式——通过修改 ID 访问其他用户的资源：

```python
def test_idor_user_cannot_read_other_user(client, user_a_token, user_b_token):
    """用户 A 不能读取用户 B 的数据"""
    # 用户 B 创建一个私密笔记
    note_response = client.post("/api/v1/notes", json={
        "title": "Secret Note",
        "content": "This is B's secret"
    }, headers={"Authorization": f"Bearer {user_b_token}"})
    note_id = note_response.json()["id"]

    # 用户 A 尝试读取
    response = client.get(
        f"/api/v1/notes/{note_id}",
        headers={"Authorization": f"Bearer {user_a_token}"}
    )
    assert response.status_code in (403, 404)

def test_idor_user_cannot_modify_other_user(client, user_a_token, user_b_token):
    """用户 A 不能修改用户 B 的数据"""
    note_response = client.post("/api/v1/notes", json={
        "title": "B's Note",
        "content": "Original content"
    }, headers={"Authorization": f"Bearer {user_b_token}"})
    note_id = note_response.json()["id"]

    response = client.put(
        f"/api/v1/notes/{note_id}",
        json={"title": "Hacked!", "content": "Modified by A"},
        headers={"Authorization": f"Bearer {user_a_token}"}
    )
    assert response.status_code in (403, 404)

    # 验证原始数据未被修改
    original = client.get(
        f"/api/v1/notes/{note_id}",
        headers={"Authorization": f"Bearer {user_b_token}"}
    )
    assert original.json()["title"] == "B's Note"
```

### 4.2 ID 枚举防护测试

```python
def test_id_enumeration_returns_same_error_for_403_and_404(
    client, user_a_token, user_b_token
):
    """403 和 404 应返回相同的错误格式，防止 ID 枚举"""
    # 不存在的资源
    r1 = client.get("/api/v1/notes/99999", headers={
        "Authorization": f"Bearer {user_a_token}"
    })

    # 存在但无权访问的资源
    note = client.post("/api/v1/notes", json={"title": "T"}, headers={
        "Authorization": f"Bearer {user_b_token}"
    })
    r2 = client.get(f"/api/v1/notes/{note.json()['id']}", headers={
        "Authorization": f"Bearer {user_a_token}"
    })

    # 两种情况应返回相同的状态码（404 或 403）
    # 如果返回不同的状态码，攻击者可以枚举存在的 ID
    if r1.status_code == 404 and r2.status_code == 403:
        # 信息泄漏！攻击者知道 ID 存在
        pytest.fail("ID enumeration possible: 404 vs 403 reveals resource existence")
```

### 4.3 BOLA 的系统性测试策略

```python
@pytest.fixture
def bola_test_matrix(client, admin_token, user_a_token, user_b_token):
    """BOLA 系统性测试矩阵"""
    resources = {}
    for token_name, token in [
        ("admin", admin_token),
        ("user_a", user_a_token),
        ("user_b", user_b_token),
    ]:
        response = client.post("/api/v1/notes", json={
            "title": f"{token_name}'s note",
            "content": "secret"
        }, headers={"Authorization": f"Bearer {token}"})
        resources[token_name] = {
            "token": token,
            "note_id": response.json()["id"]
        }
    return resources

def test_bola_cross_access_matrix(bola_test_matrix, client):
    """系统性测试所有用户对所有资源的访问"""
    for accessor_name, accessor in bola_test_matrix.items():
        for owner_name, owner in bola_test_matrix.items():
            response = client.get(
                f"/api/v1/notes/{owner['note_id']}",
                headers={"Authorization": f"Bearer {accessor['token']}"}
            )
            if accessor_name == owner_name:
                assert response.status_code == 200, \
                    f"{accessor_name} should access own note"
            elif accessor_name == "admin":
                assert response.status_code == 200, \
                    f"admin should access {owner_name}'s note"
            else:
                assert response.status_code in (403, 404), \
                    f"{accessor_name} should NOT access {owner_name}'s note"
```

---

## 五、速率限制测试

### 5.1 基本速率限制测试

```python
import time

def test_rate_limiting_on_login(client):
    """登录端点应有速率限制"""
    for i in range(5):
        response = client.post("/api/v1/auth/login", json={
            "email": "test@example.com",
            "password": "wrong_password"
        })
        if i < 4:
            assert response.status_code == 401
        else:
            # 第 5 次应该被限流
            assert response.status_code == 429

def test_rate_limit_returns_retry_after(client):
    """429 响应应包含 Retry-After 头"""
    for _ in range(10):
        client.post("/api/v1/auth/login", json={
            "email": "test@example.com",
            "password": "wrong"
        })

    response = client.post("/api/v1/auth/login", json={
        "email": "test@example.com",
        "password": "wrong"
    })
    if response.status_code == 429:
        assert "Retry-After" in response.headers
        retry_after = int(response.headers["Retry-After"])
        assert retry_after > 0
```

### 5.2 按用户限制测试

```python
def test_rate_limit_per_user_not_per_ip(client, user_a_token, user_b_token):
    """速率限制应按用户而非 IP 计算"""
    # 用户 A 耗尽配额
    for _ in range(100):
        client.get("/api/v1/notes", headers={
            "Authorization": f"Bearer {user_a_token}"
        })

    # 用户 A 被限流
    r_a = client.get("/api/v1/notes", headers={
        "Authorization": f"Bearer {user_a_token}"
    })

    # 用户 B 不应受影响
    r_b = client.get("/api/v1/notes", headers={
        "Authorization": f"Bearer {user_b_token}"
    })

    if r_a.status_code == 429:
        assert r_b.status_code != 429, "Rate limit should be per-user, not per-IP"
```

### 5.3 速率限制绕过测试

```python
def test_rate_limit_bypass_via_header(client):
    """不能通过 X-Forwarded-For 头绕过速率限制"""
    for i in range(10):
        client.post("/api/v1/auth/login", json={
            "email": "test@example.com",
            "password": "wrong"
        })

    # 尝试通过伪造 IP 绕过
    response = client.post("/api/v1/auth/login", json={
        "email": "test@example.com",
        "password": "wrong"
    }, headers={"X-Forwarded-For": "1.2.3.4"})

    # 如果应用信任 X-Forwarded-For，这可能绕过限制
    # 正确行为：不应信任客户端发送的 X-Forwarded-For
    assert response.status_code == 429, "Rate limit bypassed via X-Forwarded-For"
```

---

## 六、敏感数据暴露测试

### 6.1 响应体中的敏感数据

```python
def test_password_not_in_response(client):
    """密码不应出现在响应中"""
    response = client.post("/api/v1/users", json={
        "name": "Alice",
        "email": "alice@example.com",
        "password": "Secret123!"
    })
    body = response.json()
    assert "password" not in body
    assert "password_hash" not in body
    assert "Secret123!" not in str(body)

def test_sensitive_fields_not_in_list_response(client, admin_token):
    """列表响应不应包含敏感字段"""
    response = client.get("/api/v1/users", headers={
        "Authorization": f"Bearer {admin_token}"
    })
    for user in response.json():
        assert "password" not in user
        assert "password_hash" not in user
        assert "ssn" not in user
        assert "credit_card" not in user
```

### 6.2 错误消息中的敏感数据

```python
def test_error_messages_do_not_leak_internal_info(client):
    """错误消息不应泄露内部信息"""
    response = client.get("/api/v1/users/invalid_id")
    body = response.json()

    error_text = str(body).lower()
    assert "traceback" not in error_text
    assert "sqlalchemy" not in error_text
    assert "select * from" not in error_text
    assert "stack trace" not in error_text
    assert "internal server error" not in error_text or response.status_code == 500

def test_500_error_does_not_expose_stacktrace(client, monkeypatch):
    """500 错误不应暴露堆栈跟踪"""
    # 制造一个内部错误
    def broken_handler():
        raise RuntimeError("Database connection failed: postgresql://admin:pass@db")

    monkeypatch.setattr("app.handlers.get_user", broken_handler)

    response = client.get("/api/v1/users/1")
    if response.status_code == 500:
        assert "postgresql://" not in response.text
        assert "admin:pass" not in response.text
```

### 6.3 日志中的敏感数据

```python
def test_passwords_not_logged(client, caplog):
    """密码不应出现在日志中"""
    import logging
    with caplog.at_level(logging.DEBUG):
        client.post("/api/v1/auth/login", json={
            "email": "alice@example.com",
            "password": "Secret123!"
        })

    for record in caplog.records:
        assert "Secret123!" not in record.message
        assert "password" not in record.message.lower() or "password" in record.message.lower() and "hash" in record.message.lower()
```

### 6.4 HTTP 头中的敏感数据

```python
def test_no_sensitive_headers_in_response(client):
    """响应头不应泄露敏感信息"""
    response = client.get("/api/v1/users")

    assert "X-Powered-By" not in response.headers  # 不泄露技术栈
    assert "Server" not in response.headers or \
           "debug" not in response.headers.get("Server", "").lower()

    # 不应暴露内部头
    for header, value in response.headers.items():
        assert "internal" not in header.lower()
        assert "debug" not in header.lower()
```

### 6.5 API 文档中的敏感数据

```python
def test_openapi_schema_no_production_urls(client):
    """OpenAPI 文档不应包含生产环境 URL"""
    response = client.get("/openapi.json")
    schema = response.json()

    schema_text = json.dumps(schema)
    assert "production" not in schema_text.lower()
    assert "prod-api" not in schema_text.lower()
    assert "internal" not in schema_text.lower()

def test_docs_disabled_in_production(client, production_settings):
    """生产环境应禁用 API 文档"""
    response = client.get("/docs")
    assert response.status_code == 404

    response = client.get("/openapi.json")
    assert response.status_code == 404
```

---

## 七、安全测试自动化策略

### 7.1 SAST/DAST/IAST 分层

| 层次 | 工具类型 | 检测时机 | 覆盖范围 |
|------|---------|---------|---------|
| **SAST**（静态应用安全测试） | Bandit, Semgrep | 代码提交时 | 代码模式、已知漏洞模式 |
| **DAST**（动态应用安全测试） | ZAP, Nuclei | 运行时 | 运行时漏洞、配置问题 |
| **IAST**（交互式应用安全测试） | 自定义 pytest | 测试执行时 | 实际数据流、运行时行为 |

### 7.2 SAST 集成

```bash
# Bandit - Python 安全扫描
bandit -r app/ -f json -o bandit-report.json

# Semgrep - 自定义规则
semgrep --config p/owasp-top-ten --config p/python app/
```

### 7.3 DAST 集成

```bash
# ZAP - 自动化 DAST 扫描
docker run -t owasp/zap2docker-stable zap-api-scan.py \
  -t http://host.docker.internal:8000/openapi.json \
  -f openapi \
  -r zap-report.html
```

### 7.4 pytest marker 集成

```python
# conftest.py
import pytest

def pytest_configure(config):
    config.addinivalue_line("markers", "security: security test")
    config.addinivalue_line("markers", "security.injection: injection attack test")
    config.addinivalue_line("markers", "security.auth: authentication/authorization test")
    config.addinivalue_line("markers", "security.bola: BOLA/IDOR test")
    config.addinivalue_line("markers", "security.ratelimit: rate limiting test")
    config.addinivalue_line("markers", "security.data_exposure: sensitive data exposure test")

# 测试文件
@pytest.mark.security
@pytest.mark.security.injection
def test_sql_injection():
    ...

@pytest.mark.security
@pytest.mark.security.bola
def test_idor():
    ...

# 运行所有安全测试
# pytest -m security

# 只运行注入测试
# pytest -m security.injection

# 跳过安全测试（CI 快速模式）
# pytest -m "not security"
```

### 7.5 CI/CD 集成

```yaml
# GitHub Actions 安全测试流水线
name: Security Tests

on: [push, pull_request]

jobs:
  sast:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Bandit Scan
        run: |
          pip install bandit
          bandit -r app/ -f json -o bandit-report.json
      - name: Semgrep Scan
        uses: returntocorp/semgrep-action@v1
        with:
          config: p/owasp-top-ten

  security-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Security Tests
        run: |
          pip install -e ".[dev]"
          pytest -m security --tb=short

  dast:
    runs-on: ubuntu-latest
    needs: [security-tests]
    if: github.ref == 'refs/heads/main'
    steps:
      - name: ZAP API Scan
        run: |
          docker run -t owasp/zap2docker-stable zap-api-scan.py \
            -t http://host.docker.internal:8000/openapi.json \
            -f openapi \
            -r zap-report.html
```

---

## 八、总结：API 安全测试的核心原则

| # | 原则 | 说明 |
|---|------|------|
| 1 | **BOLA 是 API 安全的头号威胁** | 每个资源访问都必须验证所有权 |
| 2 | **FastAPI 天然防护但非万能** | Pydantic 防注入，但业务逻辑漏洞需手动测试 |
| 3 | **认证测试需要完整矩阵** | 无/无效/过期/篡改/错误受众/有效——六种场景 |
| 4 | **JWT 算法混淆是真实攻击** | 拒绝 `alg: none`，强制 RS256/ES256 |
| 5 | **403 和 404 应统一处理** | 防止 ID 枚举攻击 |
| 6 | **速率限制必须按用户而非 IP** | 防止 X-Forwarded-For 绕过 |
| 7 | **敏感数据有五个泄漏面** | 响应体、错误消息、日志、Header、API 文档 |
| 8 | **安全测试需要分层自动化** | SAST + DAST + IAST + pytest marker |
| 9 | **安全测试应独立于功能测试** | `@pytest.mark.security` 独立运行和报告 |
| 10 | **安全测试是持续过程** | CI/CD 集成，每次提交都运行 |

---

*上一章：[Layer 11 - 异步与并发测试](./layer-11-async-concurrent-testing.md)*
*下一章：[Layer 13 - 契约测试与测试可观测性](./layer-13-contract-testing-and-observability.md)*
