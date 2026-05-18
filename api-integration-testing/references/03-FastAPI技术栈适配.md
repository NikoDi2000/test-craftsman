# FastAPI 技术栈集成测试适配

## 与 adversarial-tdd 技术栈适配的关系

本文档补充 `adversarial-tdd/references/07-FastAPI技术栈适配.md`，专注集成测试层面的技术栈特定场景。

## TestClient 配置

### 同步路由测试

```python
# tests/conftest.py
from fastapi.testclient import TestClient
from app.main import app

@pytest.fixture(scope="function")
def client():
    with TestClient(app) as c:
        yield c
```

### 异步路由测试

```python
# tests/conftest.py
import pytest
from httpx import ASGITransport, AsyncClient

@pytest.fixture(scope="function")
async def async_client():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test"
    ) as ac:
        yield ac
```

### 同步/异步混用

```python
# 同步路由 → TestClient
# 异步路由 → AsyncClient

# 不要混用！
# 错误示例：
async def test_sync():
    response = await ac.get("/sync-endpoint")  # 可工作但不推荐
```

## Pydantic 模型集成

### 请求体验证测试

```python
class TestPydanticValidation:
    def test_missing_required_field(self):
        response = client.post(
            "/users/",
            json={"email": "alice@example.com"}  # 缺少 "name"
        )
        assert response.status_code == 422
        errors = response.json()["detail"]
        assert any("name" in str(e) for e in errors)

    def test_invalid_email_format(self):
        response = client.post(
            "/users/",
            json={"name": "Alice", "email": "invalid-email"}
        )
        assert response.status_code == 422
        assert "email" in response.json()["detail"][0]["loc"]

    def test_invalid_type_for_int_field(self):
        response = client.post(
            "/items/",
            json={"name": "Item", "price": "not-a-number"}
        )
        assert response.status_code == 422
```

### 响应模型验证

```python
def test_response_model_structure():
    response = client.get("/users/1")
    assert response.status_code == 200

    data = response.json()
    assert "id" in data
    assert "name" in data
    assert "email" in data
    assert "created_at" in data

    # 验证类型
    assert isinstance(data["id"], int)
    assert isinstance(data["created_at"], str)  # datetime 被序列化为 ISO 格式
```

## 路径参数测试

```python
class TestPathParameters:
    def test_valid_path_param(self):
        response = client.get("/users/123")
        assert response.status_code == 200

    def test_invalid_path_param_type(self):
        response = client.get("/users/abc")  # 期望 int
        assert response.status_code == 422

    def test_nonexistent_resource(self):
        response = client.get("/users/999999")
        assert response.status_code == 404
```

## 查询参数测试

```python
class TestQueryParameters:
    def test_pagination_defaults(self):
        response = client.get("/users/")
        assert response.status_code == 200
        data = response.json()
        assert "items" in data
        assert "total" in data

    def test_custom_pagination(self):
        response = client.get("/users/?skip=10&limit=5")
        assert response.status_code == 200
        data = response.json()
        assert len(data["items"]) <= 5

    def test_filter_parameters(self):
        response = client.get("/users/?role=admin&is_active=true")
        assert response.status_code == 200
        for user in response.json()["items"]:
            assert user["role"] == "admin"
            assert user["is_active"] is True
```

## 请求体测试

### JSON Body

```python
class TestRequestBody:
    def test_valid_json(self):
        response = client.post(
            "/items/",
            json={
                "name": "Test Item",
                "price": 29.99,
                "tags": ["electronics", "sale"]
            }
        )
        assert response.status_code == 201

    def test_empty_body(self):
        response = client.post("/items/", json={})
        assert response.status_code == 422

    def test_extra_fields_stripped(self):
        """FastAPI 默认忽略额外字段"""
        response = client.post(
            "/items/",
            json={
                "name": "Item",
                "unknown_field": "should be ignored"
            }
        )
        assert response.status_code == 201
```

### Form Data

```python
class TestFormData:
    def test_login_form(self):
        response = client.post(
            "/token",
            data={"username": "user", "password": "pass"}
        )
        assert response.status_code == 200
        assert "access_token" in response.json()
```

## HTTP 状态码测试

```python
class TestHTTPStatusCodes:
    def test_success_codes(self):
        assert client.post("/items/", json={"name": "i"}).status_code == 201
        assert client.get("/items/1").status_code == 200
        assert client.delete("/items/1").status_code == 204

    def test_client_error_codes(self):
        assert client.get("/nonexistent").status_code == 404
        assert client.post("/items/", json={}).status_code == 422  # Validation error
        assert client.post("/items/", json={"name": ""}).status_code == 422

    def test_auth_error_codes(self):
        assert client.get("/admin").status_code == 401  # Unauthorized
        assert client.get("/protected").status_code == 401
```

## 异步任务测试

### BackgroundTasks

```python
class TestBackgroundTasks:
    def test_background_task_executed(self):
        """验证 BackgroundTask 在请求后执行"""
        response = client.post(
            "/send-email",
            json={"to": "user@example.com", "subject": "Test"}
        )
        assert response.status_code == 202

        # 验证任务已排队（实际执行可能需要等待）
        # 可使用内存队列或 mock 来验证任务被调用
```

### StreamingResponse

```python
class TestStreamingResponse:
    def test_streaming_response(self):
        with client.stream("GET", "/stream-data") as response:
            assert response.status_code == 200
            chunks = list(response.iter_bytes())
            assert len(chunks) > 0

    def test_streaming_interruption(self):
        """验证流式响应中断时正确关闭连接"""
        with client.stream("GET", "/large-stream") as response:
            # 读取部分数据后中断
            first_chunk = next(response.iter_bytes())
            assert len(first_chunk) > 0
```

## 中间件交互测试

### CORS 测试

```python
class TestCORS:
    def test_cors_headers(self):
        response = client.options(
            "/users/",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "GET"
            }
        )
        assert response.status_code == 200
        assert "access-control-allow-origin" in response.headers
```

### 自定义中间件

```python
class TestCustomMiddleware:
    def test_request_id_added(self):
        response = client.get("/users/")
        assert "x-request-id" in response.headers

    def test_rate_limit_enforced(self):
        # 触发限流
        for _ in range(100):
            response = client.get("/api/limited")
        assert response.status_code == 429
```

## 异常处理测试

### HTTPException

```python
class TestHTTPExceptionHandling:
    def test_not_found_returns_json(self):
        response = client.get("/users/999999")
        assert response.status_code == 404
        assert response.headers["content-type"] == "application/json"
        assert "detail" in response.json()

    def test_custom_exception_handler(self):
        response = client.post("/users/", json={"email": "duplicate@example.com"})
        assert response.status_code == 409  # 自定义状态码
        data = response.json()
        assert "error_code" in data
```

## 错误响应格式

```python
class TestErrorResponseFormat:
    def test_validation_error_format(self):
        response = client.post("/users/", json={"name": ""})
        assert response.status_code == 422
        data = response.json()
        assert "detail" in data
        assert isinstance(data["detail"], list)
        for error in data["detail"]:
            assert "loc" in error
            assert "msg" in error
            assert "type" in error
```

## OpenAPI 集成

### 自动生成的 OpenAPI 规范测试

```python
def test_openapi_schema_valid():
    response = client.get("/openapi.json")
    assert response.status_code == 200

    schema = response.json()
    assert "openapi" in schema
    assert "paths" in schema
    assert "/users/" in schema["paths"]

def test_endpoint_in_openapi():
    schema = client.get("/openapi.json").json()
    users_path = schema["paths"]["/users/"]
    assert "post" in users_path
    assert "responses" in users_path["post"]
    assert "201" in users_path["post"]["responses"]
```

## 依赖注入链路测试

### 多层依赖

```python
# app/routers/users.py
@router.get("/users/{user_id}/posts")
async def get_user_posts(
    user_id: int,
    post_service: PostService = Depends(get_post_service),
    current_user: User = Depends(get_current_user)
):
    # user_id 来自路径
    # post_service 来自依赖
    # current_user 来自认证依赖
    pass
```

```python
# 测试多层依赖
def test_get_user_posts_with_auth():
    # 只 Mock 认证层，其他使用真实依赖
    app.dependency_overrides[get_current_user] = lambda: User(id=1)

    response = client.get("/users/1/posts")
    assert response.status_code == 200
```

## 文件上传/下载测试

```python
class TestFileOperations:
    def test_file_upload(self):
        files = {"file": ("test.txt", b"hello world", "text/plain")}
        response = client.post("/upload/", files=files)
        assert response.status_code == 201
        assert "file_id" in response.json()

    def test_file_download(self):
        # 先上传
        files = {"file": ("test.txt", b"content", "text/plain")}
        upload_resp = client.post("/upload/", files=files)
        file_id = upload_resp.json()["file_id"]

        # 再下载
        response = client.get(f"/files/{file_id}")
        assert response.status_code == 200
        assert response.content == b"content"
```
