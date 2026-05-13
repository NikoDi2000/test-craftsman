# Flutter/Dart 技术栈适配

## 语言特定空值
- Dart 使用 `null`（空安全模式下，非空类型不得为 null）
- 必须测试：`?` 可空类型接收 null、`!` 强制解包在 null 时抛出、`late` 变量未初始化访问
- 必须测试：空集合 `[]`、空 Map `{}`、空字符串 `""` 的区分处理

## 异步与并发
- Dart 是单线程事件循环，"并发"表现为异步 `Future` 和 `Stream`
- 必须测试：`await` 缺失导致的时序错误、`Future` 完成前 Widget 已卸载、`Stream` 未关闭导致的内存泄漏
- 必须测试：`async` 函数中的异常是包裹在 `Future.error` 还是直接抛出

## Widget 与 UI 边界
- 必须测试：不同屏幕尺寸下的布局溢出（`Overflow`）、最小/最大约束
- 必须测试：Widget Key 冲突导致的树重建异常、GlobalKey 重复
- 必须测试：`setState` 在 `dispose` 后调用（`mounted` 检查缺失）
- 必须测试：动画控制器 `AnimationController` 未释放导致的资源泄漏

## 状态管理边界
- 必须测试：Provider/Bloc/Riverpod 中状态在 Widget 树外访问
- 必须测试：状态更新通知遗漏（`notifyListeners` 缺失）
- 必须测试：同一事件重复发送导致的重复副作用

## Mock 策略
- 外部 HTTP：使用 `http` 包的 `MockClient` 或 `dio` 的适配器
- 平台通道：使用 `MethodChannel.setMockMethodCallHandler`
- 数据库：使用内存版 `sqflite_common_ffi` 或 `hive` 内存实例
- **禁止**：Mock `BuildContext`、`Widget`、`State`（这些是框架内部，应通过集成测试验证）

## 痛苦场景追加清单

| 编号 | 场景 | 预期行为 |
|------|------|----------|
| F1 | 屏幕旋转/尺寸变化后状态丢失 | 状态恢复或正确重建 |
| F2 | 无限列表滚动到边界 | 正确加载更多/显示无更多数据 |
| F3 | 动画控制器未释放 | 测试内存泄漏（通过 LeakTracking） |
| F4 | 图片加载失败/超时 | 显示占位图，不崩溃 |
| F5 | 输入框快速连续输入（防抖/节流） | 最终状态正确，无竞态 |
| F6 | Navigator 跳转时异步操作未完成 | 不操作已卸载 Widget 的 context |
| F7 | 主题/语言切换后 Widget 重建 | 正确应用新主题/语言 |

## 变异假设追加

- 假设F1：如果实现者硬编码 Widget 子树 → 不同输入参数的 Widget 测试会失败
- 假设F2：如果实现者移除 `mounted` 检查 → 异步回调后 setState 的测试会失败
- 假设F3：如果实现者将 `await` 改为 fire-and-forget → 依赖顺序的集成测试会失败
- 假设F4：如果实现者忘记 `dispose` 资源 → 内存泄漏检测测试会失败