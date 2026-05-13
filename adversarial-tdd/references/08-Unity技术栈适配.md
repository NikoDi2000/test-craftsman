# Unity/C# 技术栈适配

## 语言特定空值
- C# 使用 `null`，但 Unity 中大量对象继承自 `UnityEngine.Object`，其 `== null` 已被重载（检测原生对象是否销毁）
- 必须测试：`null` 与 `UnityEngine.Object` 的 "假 null"（对象已销毁但引用非空）区分
- 必须测试：`GetComponent&lt;T&gt;()` 返回 null、序列化字段未赋值

## 异步与并发
- Unity 使用协程 (`IEnumerator` + `StartCoroutine`) 和 `async/await`（Unity 2020+）
- 必须测试：协程在宿主 `MonoBehaviour` 销毁后继续运行（应停止）
- 必须测试：`async` 方法在对象销毁后访问 `transform` 等 Unity API
- 必须测试：主线程限制（Unity API 只能在主线程调用）

## 生命周期边界
- 必须测试：`Awake`/`OnEnable`/`Start` 调用顺序错误（如依赖在 `Start` 初始化，但 `Awake` 中访问）
- 必须测试：`OnDestroy` 中访问其他可能已销毁的对象
- 必须测试：场景加载/卸载时对象存活状态（`DontDestroyOnLoad` vs 普通对象）
- 必须测试：编辑器模式 (`Application.isPlaying == false`) 与运行模式行为差异

## 物理与渲染边界
- 必须测试：物理碰撞层 (`LayerMask`) 配置错误导致的穿透
- 必须测试：`Rigidbody` 受力计算与直接设置 `transform.position` 的差异
- 必须测试：帧率波动下的时序依赖（如假设固定 60fps 的位移计算）
- 必须测试：相机视锥体剔除导致的对象不可见但逻辑仍在运行

## 资源管理边界
- 必须测试：`Resources.Load`/`Addressables` 加载失败（路径错误、资源未打包）
- 必须测试：资源加载异步回调时对象已销毁（`CancellationToken` 或 `null` 检查）
- 必须测试：`Instantiate` 后的对象未正确初始化（预制体变体差异）
- 必须测试：`Destroy` 与 `DestroyImmediate` 在编辑器 vs 运行时的差异

## Mock 策略
- 外部系统：使用接口 + 注入，避免直接依赖 `UnityEngine` 静态类
- 物理：使用 `Physics2D/Physics` 的模拟模式或自定义 `IPhysics` 接口
- 输入：使用 `InputSystem` 的测试适配器或注入 `IInputService`
- **禁止**：在单元测试中直接实例化 `MonoBehaviour`（应提取纯逻辑到普通类测试）
- **禁止**：Mock `UnityEngine.Object` 子类（行为过于复杂，应使用集成测试）

## 痛苦场景追加清单

| 编号 | 场景 | 预期行为 |
|------|------|----------|
| U1 | 对象在协程中途被销毁 | 协程停止，不抛出 NullReference |
| U2 | 物理碰撞发生在禁用碰撞器后 | 不触发碰撞事件 |
| U3 | 资源热更新后旧引用失效 | 正确重新加载或返回默认 |
| U4 | 编辑器下运行测试与真机差异 | 关键逻辑在两者下行为一致 |
| U5 | 多摄像机渲染同一对象 | 无重复逻辑副作用 |
| U6 | 动画事件在动画被覆盖后触发 | 不触发已移除的事件 |
| U7 | 时间缩放 (`Time.timeScale = 0`) 下逻辑 | 暂停逻辑正确，UI 响应正常 |

## 变异假设追加

- 假设U1：如果实现者将协程停止逻辑从 `OnDestroy` 移除 → 对象生命周期测试会失败
- 假设U2：如果实现者将 `Rigidbody.AddForce` 改为直接设置 `position` → 物理一致性测试会失败
- 假设U3：如果实现者在后台线程中调用 `transform.position` → 主线程测试会失败
- 假设U4：如果实现者将 `Addressables.Load` 改为 `Resources.Load` 硬编码路径 → 资源变体测试会失败
- 假设U5：如果实现者移除 `Time.deltaTime` 使用固定值 → 帧率波动测试会失败