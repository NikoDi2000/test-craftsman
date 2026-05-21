# Layer 10 深度报告：HTTP 语义测试与 RESTful API 测试

> **前置知识**：本报告与 [Layer 2 - 输入空间建模](./layer-02-input-space.md) 紧密关联——HTTP 方法和状态码定义了 API 的输入空间边界。HTTP 语义验证本质上是 [Layer 6 - 预言选择](./layer-06-oracle-selection.md) 的特化——RFC 规范就是最精确的测试预言。[Layer 3 - 路径覆盖](./layer-03-path-coverage.md) 中的路径分析可直接应用于 HTTP 状态码路径覆盖。

---

## 一、HTTP 方法语义测试

### 1.1 RFC 9110 方法语义矩阵

RFC 9110（HTTP Semantics，2022）定义了 HTTP 方法的两个核心语义属性：

| 方法 | 安全性（Safe） | 幂等性（Idempotent） | 可缓存（Cacheable） | 语义 |
|------|--------------|--------------------|--------------------|------|
| **GET** | ✅ | ✅ | ✅ | 获取资源表示 |
| **HEAD** | ✅ | ✅ | ✅ | 获取资源元数据 |
| **OPTIONS** | ✅ | ✅ | ❌ | 获取通信选项 |
| **TRACE** | ✅ | ✅ | ❌ | 回显请求 |
| **POST** | ❌ | ❌ | ❌ | 创建/处理资源 |
| **PUT** | ❌ | ✅ | ❌ | 完整替换资源 |
| **DELETE** | ❌ | ✅ | ❌ | 删除资源 |
| **PATCH** | ❌ | ❌ | ❌ | 部分修改资源 |

**安全性（Safe）**：方法不改变服务器上的资源状态。GET 请求不应该有副作用。

**幂等性（Idempotent）**：多次执行同一请求与一次执行的效果相同。PUT 两次同一资源，结果与 PUT 一次相同。

### 1.2 安全性测试

```python
def test_get_is_safe(client, existing_user):
    """GET 请求不应改变资源状态"""
    initial_count = client.get("/api/v1/users").json()["total"]
    client.get(f"/api/v1/users/{existing_user.id}")
    client.get(f"/api/v1/users/{existing_user.id}")
    after_count = client.get("/api/v1/users").json()["total"]
    assert initial_count == after_count

def test_head_is_safe(client, existing_user):
    """HEAD 请求不应改变资源状态"""
    initial_updated_at = existing_user.updated_at
    client.head(f"/api/v1/users/{existing_user.id}")
    existing_user.refresh_from_db()
    assert existing_user.updated_at == initial_updated_at
```

### 1.3 幂等性测试

```python
def test_put_is_idempotent(client, existing_user):
    """PUT 同一请求多次，结果应与一次相同"""
    payload = {"name": "Alice Updated", "email": "alice_new@example.com"}

    response1 = client.put(f"/api/v1/users/{existing_user.id}", json=payload)
    assert response1.status_code == 200

    response2 = client.put(f"/api/v1/users/{existing_user.id}", json=payload)
    assert response2.status_code == 200

    get_response = client.get(f"/api/v1/users/{existing_user.id}")
    assert get_response.json()["name"] == "Alice Updated"

    count = client.get("/api/v1/users").json()["total"]
    assert count == 1  # 没有创建重复资源

def test_delete_is_idempotent(client, existing_user):
    """DELETE 已删除的资源应返回 404 或 204"""
    response1 = client.delete(f"/api/v1/users/{existing_user.id}")
    assert response1.status_code == 204

    response2 = client.delete(f"/api/v1/users/{existing_user.id}")
    assert response2.status_code in (204, 404)  # 两种都是合法的幂等行为
```

### 1.4 POST 非幂等性测试

```python
def test_post_is_not_idempotent(client):
    """POST 同一请求多次，应创建多个资源"""
    payload = {"name": "Alice", "email": "alice@example.com"}

    response1 = client.post("/api/v1/users", json=payload)
    assert response1.status_code == 201

    response2 = client.post("/api/v1/users", json=payload)
    # 如果 email 有唯一约束，应返回 409/422
    # 如果没有，应创建第二个资源
    assert response2.status_code in (201, 409, 422)
```

---

## 二、HTTP 状态码语义测试

### 2.1 精确语义匹配

HTTP 状态码不是随意选择的，每个状态码都有精确的语义：

| 状态码 | 语义 | 常见误用 |
|--------|------|---------|
| **200** | 请求成功 | ❌ 用于创建资源（应 201） |
| **201** | 资源创建成功 | ❌ 不返回 Location 头 |
| **204** | 成功但无响应体 | ❌ 返回了响应体 |
| **400** | 请求语法错误 | ❌ 用于业务逻辑错误（应 422） |
| **401** | 未认证 | ❌ 与 403 混淆 |
| **403** | 已认证但无权限 | ❌ 与 401 混淆 |
| **404** | 资源不存在 | ❌ 用于隐藏无权限资源 |
| **405** | 方法不允许 | ❌ 不返回 Allow 头 |
| **409** | 资源状态冲突 | ❌ 用于所有业务错误 |
| **415** | 不支持的媒体类型 | ❌ 用于所有格式错误 |
| **422** | 语义错误（可处理） | ✅ FastAPI 默认使用 |

### 2.2 400 vs 422 的精确区分

```python
def test_400_malformed_json(client):
    """400：请求体不是合法的 JSON"""
    response = client.post(
        "/api/v1/users",
        data="{invalid json",
        headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 400  # JSON 解析失败

def test_422_semantic_validation_error(client):
    """422：JSON 合法但语义不满足约束"""
    response = client.post("/api/v1/users", json={
        "name": "A",  # 太短
        "email": "not-an-email"  # 格式错误
    })
    assert response.status_code == 422
    body = response.json()
    assert "detail" in body
    assert len(body["detail"]) >= 2  # 至少两个验证错误
```

**FastAPI 的默认行为**：FastAPI 自动将 Pydantic 验证错误映射为 422，这是符合 RFC 9110 的正确行为。

### 2.3 401 vs 403 的精确区分

```python
def test_401_no_token(client):
    """401：未提供认证凭据"""
    response = client.get("/api/v1/admin/users")
    assert response.status_code == 401
    assert "WWW-Authenticate" in response.headers  # RFC 9110 要求

def test_401_invalid_token(client):
    """401：认证凭据无效"""
    response = client.get(
        "/api/v1/admin/users",
        headers={"Authorization": "Bearer invalid_token"}
    )
    assert response.status_code == 401

def test_403_insufficient_permissions(client, regular_user_token):
    """403：已认证但权限不足"""
    response = client.get(
        "/api/v1/admin/users",
        headers={"Authorization": f"Bearer {regular_user_token}"}
    )
    assert response.status_code == 403
    # 403 不应返回 WWW-Authenticate（用户已认证，问题在于权限）
```

**关键区分**：

```
401 = "你是谁？" → 需要认证
403 = "我知道你是谁，但你不能做这件事" → 需要授权
```

---

## 三、HTTP 头部语义测试

### 3.1 Location 头（201 响应必需）

```python
def test_create_user_returns_location(client):
    """201 响应必须包含 Location 头指向新创建的资源"""
    response = client.post("/api/v1/users", json={
        "name": "Alice",
        "email": "alice@example.com"
    })
    assert response.status_code == 201
    assert "Location" in response.headers
    location = response.headers["Location"]
    assert "/api/v1/users/" in location

    # Location 应该是可访问的
    get_response = client.get(location)
    assert get_response.status_code == 200
```

### 3.2 Allow 头（405 响应必需）

```python
def test_method_not_allowed_returns_allow(client, existing_user):
    """405 响应必须包含 Allow 头列出允许的方法"""
    response = client.patch(f"/api/v1/users/{existing_user.id}", json={"name": "X"})
    assert response.status_code == 405
    assert "Allow" in response.headers
    allowed = [m.strip() for m in response.headers["Allow"].split(",")]
    assert "GET" in allowed
    assert "PUT" in allowed
    assert "DELETE" in allowed
    assert "PATCH" not in allowed
```

### 3.3 Vary 头

```python
def test_vary_header_for_content_negotiation(client):
    """返回不同表示的资源应包含 Vary 头"""
    response = client.get("/api/v1/users")
    if "Vary" in response.headers:
        vary_values = [v.strip() for v in response.headers["Vary"].split(",")]
        # 如果支持内容协商，Vary 应包含 Accept
        # 如果包含认证内容，Vary 应包含 Authorization
        # 如果使用压缩，Vary 应包含 Accept-Encoding
        pass
```

### 3.4 WWW-Authenticate 头

```python
def test_401_includes_www_authenticate(client):
    """401 响应必须包含 WWW-Authenticate 头（RFC 9110 §11.6.1）"""
    response = client.get("/api/v1/admin/users")
    assert response.status_code == 401
    www_auth = response.headers.get("WWW-Authenticate", "")
    assert "Bearer" in www_auth
    # 可以包含 realm 和其他参数
    # WWW-Authenticate: Bearer realm="api", error="invalid_token"
```

---

## 四、REST 约束测试

### 4.1 无状态约束测试

```python
def test_statelessness_no_session(client):
    """每个请求必须包含所有必要信息，不依赖服务器端会话"""
    response1 = client.get("/api/v1/users", headers={
        "Authorization": "Bearer valid_token"
    })
    assert response1.status_code == 200

    response2 = client.get("/api/v1/users")  # 不带 token
    assert response2.status_code == 401  # 不依赖前一个请求的认证
```

### 4.2 统一接口约束测试

```python
def test_uniform_interface_resource_identification(client):
    """资源通过 URI 标识，而非通过请求体"""
    response = client.get("/api/v1/users/123")
    assert response.status_code in (200, 404)
    # 不应该通过 POST /api/v1/getUser 来获取用户

def test_uniform_interface_self_descriptive_messages(client):
    """响应应包含足够的元数据（Content-Type 等）"""
    response = client.get("/api/v1/users/123")
    if response.status_code == 200:
        assert "Content-Type" in response.headers
        assert "application/json" in response.headers["Content-Type"]
```

### 4.3 HATEOAS 约束测试

详见第七节。

---

## 五、HTTP 幂等性和安全性的测试意义

### 5.1 重试安全

幂等性最重要的实际意义是**重试安全**——网络故障时可以安全重试：

```python
def test_put_retry_safety(client, existing_user):
    """PUT 请求可以安全重试"""
    payload = {"name": "Updated", "email": "updated@example.com"}

    # 模拟：第一次请求成功但客户端未收到响应
    response1 = client.put(f"/api/v1/users/{existing_user.id}", json=payload)
    assert response1.status_code == 200

    # 客户端重试
    response2 = client.put(f"/api/v1/users/{existing_user.id}", json=payload)
    assert response2.status_code == 200

    # 最终状态与单次请求一致
    final = client.get(f"/api/v1/users/{existing_user.id}")
    assert final.json()["name"] == "Updated"
```

### 5.2 缓存友好

安全方法可以被缓存：

```python
def test_get_cacheable(client, existing_user):
    """GET 响应应包含缓存相关头部"""
    response = client.get(f"/api/v1/users/{existing_user.id}")
    if "Cache-Control" in response.headers:
        cc = response.headers["Cache-Control"]
        # 安全方法应该允许缓存（除非明确 no-cache）
        assert "no-store" not in cc or "private" in cc
```

### 5.3 爬虫友好

安全方法告诉爬虫可以安全地抓取：

```python
def test_safe_methods_in_robots_txt():
    """安全方法不应触发副作用，爬虫可以安全调用"""
    # GET /api/v1/public-data → 安全，可缓存
    # POST /api/v1/users → 不安全，不应被爬虫调用
    pass
```

### 5.4 幂等键（Idempotency Key）

对于需要幂等性的 POST 请求，使用幂等键模式：

```python
def test_idempotency_key(client):
    """带幂等键的 POST 请求应保证幂等性"""
    headers = {"Idempotency-Key": "unique-key-123"}

    response1 = client.post("/api/v1/payments", json={
        "amount": 100,
        "currency": "USD"
    }, headers=headers)
    assert response1.status_code == 201
    payment_id_1 = response1.json()["id"]

    response2 = client.post("/api/v1/payments", json={
        "amount": 100,
        "currency": "USD"
    }, headers=headers)
    assert response2.status_code == 200  # 返回已有结果
    assert response2.json()["id"] == payment_id_1  # 同一个支付
```

---

## 六、API 版本化测试策略

### 6.1 三种版本化方式

| 方式 | 示例 | 优点 | 缺点 |
|------|------|------|------|
| **URI 版本化** | `/api/v1/users` | 简单直观 | URI 变更影响客户端 |
| **头部版本化** | `Accept: application/vnd.api.v1+json` | URI 不变 | 不直观，调试困难 |
| **查询参数版本化** | `/api/users?version=1` | 简单 | 不 RESTful，缓存问题 |

### 6.2 版本化测试

```python
def test_uri_versioning(client):
    """URI 版本化：不同版本应有不同的端点"""
    v1_response = client.get("/api/v1/users")
    v2_response = client.get("/api/v2/users")
    assert v1_response.status_code == 200
    assert v2_response.status_code == 200
    # v1 和 v2 的响应格式可能不同
    assert "full_name" not in v1_response.json()[0]  # v1 用 name
    assert "full_name" in v2_response.json()[0]  # v2 用 full_name

def test_header_versioning(client):
    """头部版本化：通过 Accept 头选择版本"""
    v1_response = client.get("/api/users", headers={
        "Accept": "application/vnd.api.v1+json"
    })
    v2_response = client.get("/api/users", headers={
        "Accept": "application/vnd.api.v2+json"
    })
    assert v1_response.status_code == 200
    assert v2_response.status_code == 200
```

### 6.3 Sunset Header（RFC 8594）

RFC 8594 定义了 `Sunset` 头，用于通知客户端 API 版本即将废弃：

```python
def test_sunset_header_for_deprecated_endpoint(client):
    """废弃的 API 端点应返回 Sunset 头"""
    response = client.get("/api/v1/users")
    if "Sunset" in response.headers:
        sunset_date = response.headers["Sunset"]
        # Sunset 头应包含一个 HTTP 日期
        from email.utils import parsedate_to_datetime
        sunset_dt = parsedate_to_datetime(sunset_date)
        assert sunset_dt > datetime.now(timezone.utc)  # 废弃日期应在未来

    # 同时应包含 Link 头指向替代端点
    if "Link" in response.headers:
        assert "api/v2" in response.headers["Link"]
```

---

## 七、HATEOAS 测试方法

### 7.1 HAL 格式

HAL（Hypertext Application Language）是 HATEOAS 最常用的格式：

```json
{
  "_links": {
    "self": { "href": "/api/v1/users/123" },
    "orders": { "href": "/api/v1/users/123/orders" },
    "profile": { "href": "/api/v1/users/123/profile" }
  },
  "name": "Alice",
  "email": "alice@example.com"
}
```

### 7.2 链接发现测试

```python
def test_hal_links_discovery(client, existing_user):
    """HAL 响应应包含可导航的链接"""
    response = client.get(f"/api/v1/users/{existing_user.id}")
    assert response.status_code == 200
    body = response.json()

    assert "_links" in body
    assert "self" in body["_links"]
    assert body["_links"]["self"]["href"] == f"/api/v1/users/{existing_user.id}"
```

### 7.3 状态驱动链接测试

```python
def test_links_change_with_state(client, pending_order):
    """链接应根据资源状态变化"""
    response = client.get(f"/api/v1/orders/{pending_order.id}")
    body = response.json()

    # 待处理订单应有 "pay" 链接
    assert "pay" in body["_links"]
    assert "cancel" in body["_links"]
    # 待处理订单不应有 "refund" 链接
    assert "refund" not in body["_links"]

    # 支付后
    client.post(body["_links"]["pay"]["href"], json={"method": "credit_card"})
    response = client.get(f"/api/v1/orders/{pending_order.id}")
    body = response.json()

    # 已支付订单应有 "refund" 链接
    assert "refund" in body["_links"]
    # 已支付订单不应有 "pay" 链接
    assert "pay" not in body["_links"]
```

### 7.4 导航测试

```python
def test_navigation_through_links(client):
    """客户端应能仅通过链接导航，无需硬编码 URL"""
    # 从根入口开始
    root = client.get("/api/v1/").json()

    # 通过链接导航到用户列表
    users_url = root["_links"]["users"]["href"]
    users = client.get(users_url).json()

    # 通过链接导航到第一个用户
    first_user_url = users["_embedded"]["users"][0]["_links"]["self"]["href"]
    user = client.get(first_user_url).json()

    # 通过链接导航到该用户的订单
    orders_url = user["_links"]["orders"]["href"]
    orders = client.get(orders_url).json()
    assert "_embedded" in orders
```

---

## 八、HTTP 缓存行为测试

### 8.1 ETag 测试

```python
def test_etag_on_get(client, existing_user):
    """GET 响应应包含 ETag"""
    response = client.get(f"/api/v1/users/{existing_user.id}")
    assert "ETag" in response.headers
    etag = response.headers["ETag"]

    # 条件请求：If-None-Match
    conditional_response = client.get(
        f"/api/v1/users/{existing_user.id}",
        headers={"If-None-Match": etag}
    )
    assert conditional_response.status_code == 304  # Not Modified
    assert conditional_response.content == b""  # 无响应体
```

### 8.2 Last-Modified 测试

```python
def test_last_modified(client, existing_user):
    """GET 响应应包含 Last-Modified"""
    response = client.get(f"/api/v1/users/{existing_user.id}")
    if "Last-Modified" in response.headers:
        last_modified = response.headers["Last-Modified"]

        # 条件请求：If-Modified-Since
        conditional_response = client.get(
            f"/api/v1/users/{existing_user.id}",
            headers={"If-Modified-Since": last_modified}
        )
        assert conditional_response.status_code == 304
```

### 8.3 Cache-Control 测试

```python
def test_cache_control_for_public_resources(client):
    """公开资源应允许缓存"""
    response = client.get("/api/v1/public/config")
    if "Cache-Control" in response.headers:
        cc = response.headers["Cache-Control"]
        assert "public" in cc or "max-age" in cc

def test_cache_control_for_private_resources(client, auth_headers):
    """私有资源应禁止共享缓存"""
    response = client.get("/api/v1/users/me", headers=auth_headers)
    if "Cache-Control" in response.headers:
        cc = response.headers["Cache-Control"]
        assert "private" in cc or "no-store" in cc
```

### 8.4 条件请求测试矩阵

| 条件请求头 | 配合 | 预期结果 |
|-----------|------|---------|
| `If-None-Match: <etag>` | GET | 304 if match, 200 if not |
| `If-Match: <etag>` | PUT/DELETE | 412 if not match, proceed if match |
| `If-Modified-Since: <date>` | GET | 304 if not modified, 200 if modified |
| `If-Unmodified-Since: <date>` | PUT/DELETE | 412 if modified, proceed if not |

```python
def test_conditional_put_with_if_match(client, existing_user):
    """PUT 请求配合 If-Match 实现乐观并发控制"""
    response = client.get(f"/api/v1/users/{existing_user.id}")
    etag = response.headers["ETag"]

    # 另一个客户端修改了资源
    client.put(f"/api/v1/users/{existing_user.id}", json={
        "name": "Modified by other",
        "email": "other@example.com"
    })

    # 当前客户端尝试基于旧 ETag 修改
    response = client.put(
        f"/api/v1/users/{existing_user.id}",
        json={"name": "My update", "email": "my@example.com"},
        headers={"If-Match": etag}  # 使用旧 ETag
    )
    assert response.status_code == 412  # Precondition Failed
```

---

## 九、内容协商测试

### 9.1 Accept 头测试

```python
def test_accept_json(client):
    """请求 JSON 格式"""
    response = client.get("/api/v1/users", headers={
        "Accept": "application/json"
    })
    assert response.status_code == 200
    assert "application/json" in response.headers["Content-Type"]

def test_accept_xml_not_supported(client):
    """请求不支持的格式"""
    response = client.get("/api/v1/users", headers={
        "Accept": "application/xml"
    })
    assert response.status_code == 406  # Not Acceptable
```

### 9.2 Content-Type 头测试

```python
def test_post_with_correct_content_type(client):
    """POST 请求使用正确的 Content-Type"""
    response = client.post("/api/v1/users", json={"name": "Alice"})
    assert response.status_code == 201

def test_post_with_wrong_content_type(client):
    """POST 请求使用错误的 Content-Type"""
    response = client.post(
        "/api/v1/users",
        data="name=Alice",
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    )
    assert response.status_code == 415  # Unsupported Media Type
```

### 9.3 Vary 头验证

```python
def test_vary_header_for_negotiation(client):
    """支持内容协商的端点应返回 Vary 头"""
    response = client.get("/api/v1/users")
    if response.status_code == 200:
        # 如果响应因 Accept 头不同而不同，Vary 应包含 Accept
        vary = response.headers.get("Vary", "")
        vary_fields = [v.strip() for v in vary.split(",")]
        # 至少应包含 Accept 和 Authorization
        # （如果支持内容协商和认证内容）
        pass
```

---

## 十、Richardson 成熟度模型对应的测试策略

### 10.1 Richardson 成熟度模型

```
Level 3: Hypermedia Controls (HATEOAS)
    ↑  链接驱动、状态机
Level 2: HTTP Verbs (CRUD 映射)
    ↑  正确使用 HTTP 方法和状态码
Level 1: Resources (URI 分割)
    ↑  每个资源一个 URI
Level 0: The Swamp of POX
    单一端点，RPC 风格
```

### 10.2 Level 0 → Level 1 测试矩阵

| 测试项 | Level 0 | Level 1 |
|--------|---------|---------|
| **URI 结构** | `/api` (单一端点) | `/api/users`, `/api/orders` |
| **测试重点** | 请求体格式 | URI 路由正确性 |
| **关键测试** | RPC 方法名在请求体中 | 资源 URI 可访问 |

```python
# Level 0 测试
def test_rpc_style(client):
    response = client.post("/api", json={
        "method": "getUser",
        "params": {"id": 123}
    })
    assert response.status_code == 200

# Level 1 测试
def test_resource_uris(client):
    response = client.get("/api/v1/users/123")
    assert response.status_code in (200, 404)
```

### 10.3 Level 1 → Level 2 测试矩阵

| 测试项 | Level 1 | Level 2 |
|--------|---------|---------|
| **HTTP 方法** | 只用 GET/POST | 正确使用 GET/POST/PUT/DELETE/PATCH |
| **状态码** | 总是 200 | 201/204/400/404/405/422 等 |
| **测试重点** | URI 可访问 | HTTP 语义正确性 |

```python
# Level 2 测试矩阵
class TestUserResourceLevel2:
    def test_list_users(self, client):
        response = client.get("/api/v1/users")
        assert response.status_code == 200

    def test_create_user(self, client):
        response = client.post("/api/v1/users", json={"name": "Alice"})
        assert response.status_code == 201
        assert "Location" in response.headers

    def test_get_user(self, client, existing_user):
        response = client.get(f"/api/v1/users/{existing_user.id}")
        assert response.status_code == 200

    def test_update_user(self, client, existing_user):
        response = client.put(f"/api/v1/users/{existing_user.id}", json={"name": "Updated"})
        assert response.status_code == 200

    def test_delete_user(self, client, existing_user):
        response = client.delete(f"/api/v1/users/{existing_user.id}")
        assert response.status_code == 204

    def test_method_not_allowed(self, client, existing_user):
        response = client.patch(f"/api/v1/users/{existing_user.id}", json={"name": "X"})
        assert response.status_code == 405
        assert "Allow" in response.headers
```

### 10.4 Level 2 → Level 3 测试矩阵

| 测试项 | Level 2 | Level 3 |
|--------|---------|---------|
| **链接** | 无 | HAL/JSON-LD 链接 |
| **状态驱动** | 客户端硬编码 URL | 服务器驱动链接 |
| **发现** | 需要文档 | 通过链接自发现 |
| **测试重点** | CRUD 语义 | 链接导航、状态转换 |

```python
# Level 3 测试矩阵
class TestUserResourceLevel3:
    def test_self_link(self, client, existing_user):
        response = client.get(f"/api/v1/users/{existing_user.id}")
        body = response.json()
        assert body["_links"]["self"]["href"] == f"/api/v1/users/{existing_user.id}"

    def test_related_links(self, client, existing_user):
        response = client.get(f"/api/v1/users/{existing_user.id}")
        body = response.json()
        assert "orders" in body["_links"]
        orders_response = client.get(body["_links"]["orders"]["href"])
        assert orders_response.status_code == 200

    def test_state_driven_links(self, client, pending_order):
        response = client.get(f"/api/v1/orders/{pending_order.id}")
        body = response.json()
        assert "pay" in body["_links"]
        assert "refund" not in body["_links"]  # 未支付不能退款
```

### 10.5 完整测试矩阵总览

| 成熟度级别 | 测试类别 | 测试数量（估计） | 关键断言 |
|-----------|---------|----------------|---------|
| Level 0 | RPC 调用 | 少 | 方法名、参数格式 |
| Level 1 | URI 路由 | 中 | URI 可访问、404 |
| Level 2 | HTTP 语义 | 多 | 方法、状态码、头部 |
| Level 3 | HATEOAS | 最多 | 链接存在、可导航、状态驱动 |

---

## 十一、总结：HTTP 语义测试的核心原则

| # | 原则 | 说明 |
|---|------|------|
| 1 | **每个 HTTP 方法都有精确语义** | 安全性、幂等性不是建议，是规范要求 |
| 2 | **状态码不是装饰，是协议** | 400 vs 422、401 vs 403 有精确区分 |
| 3 | **头部是 HTTP 协议的一等公民** | Location、Allow、WWW-Authenticate 不可省略 |
| 4 | **幂等性 = 重试安全** | PUT/DELETE 可以安全重试，POST 需要幂等键 |
| 5 | **缓存行为需要测试** | ETag、Last-Modified、Cache-Control 影响性能和正确性 |
| 6 | **内容协商是 REST 的核心** | Accept、Content-Type、Vary 构成协商三角 |
| 7 | **HATEOAS 是 REST 的最高成熟度** | 链接发现、状态驱动、导航测试 |
| 8 | **Richardson 模型指导测试策略** | Level 越高，测试维度越多 |
| 9 | **版本化需要 Sunset 策略** | RFC 8594 的 Sunset Header 通知废弃 |
| 10 | **条件请求实现乐观并发** | If-Match + ETag = 无锁并发控制 |

---

*上一章：[Layer 9 - 测试隔离理论](./layer-09-test-isolation.md)*
*下一章：[Layer 11 - 异步与并发测试](./layer-11-async-concurrent-testing.md)*
