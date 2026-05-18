# Layer 6 深度报告：预言选择

---

## 一、测试预言问题

### 1.1 问题的本质

Barr et al. (2015) 在 IEEE TSE 上发表的综述论文《The Oracle Problem in Software Testing》中明确指出：

> **测试自动化最核心的挑战不是"怎么生成输入"，而是"怎么判断输出对不对"。**

一个完整的测试有三个要素：
```
测试 = 输入生成 + 程序执行 + 预言
```

- **输入生成**：已由大量研究解决（随机、搜索、符号执行）
- **程序执行**：已由测试框架解决（pytest、JUnit、xUnit）
- **预言**：仍然是最大的未解决问题

### 1.2 为什么预言问题是根本性的

考虑这个问题：

```python
def test_sort():
    arr = [3, 1, 2]
    result = sort(arr)
    # 你怎么知道 result 是正确的？
    assert result == [1, 2, 3]  # 这是你"知道"的答案
```

这个测试能工作是因为你**预先知道正确答案**。但对于以下场景，你无法预先知道：

- `def test_ai_response()`: AI 的输出——你不知道"正确"是什么
- `def test_image_filter()`: 图像处理后——你不知道每个像素的值
- `def test_physics_simulation()`: 物理模拟——结果是非线性的

**预言问题 = 当正确答案未知时，如何判断输出是否正确。**

---

## 二、预言类型的分类学

### 2.1 六种预言类型

| 类型 | 定义 | 强度 | 适用场景 |
|------|------|------|---------|
| **精确预言** | 断言输出 == 预期值 | 最强 | 确定性算法、数据变换 |
| **属性预言** | 断言输出满足某性质 | 强 | 验证、解析、数据结构 |
| **蜕变预言** | 断言输入变化导致输出变化符合规律 | 中 | ML、物理模拟、图像处理 |
| **启发式预言** | 基于经验判断 | 弱 | 崩溃检测、性能检查 |
| **统计预言** | 基于统计分布 | 弱 | 大规模数据、概率性输出 |
| **人类预言** | 人判断 | 不可自动化 | UI 美观、用户体验 |

### 2.2 选择预言的决策树

```
是否有确定的正确答案？
  ├── 是 → 精确预言
  └── 否 → 是否有已知的"输入-输出关系"？
            ├── 是 → 蜕变预言
            └── 否 → 是否有必须满足的属性？
                      ├── 是 → 属性预言
                      └── 否 → 启发式预言 + 统计预言
```

---

## 三、蜕变测试

### 3.1 蜕变测试的核心思想

Chen et al. (1998) 提出蜕变测试来解决预言问题。核心思想：

> **不直接判断输出对不对，而是验证"输入的变化是否导致输出的合理变化"。**

```
蜕变关系（Metamorphic Relation, MR）:
  如果输入 x 经过变换 T 得到 x'，
  那么输出 f(x) 和 f(x') 之间应该满足关系 R。
```

### 3.2 蜕变关系的类型

| MR 类型 | 数学形式 | 示例 |
|---------|---------|------|
| **恒等** | f(T(x)) = f(x) | 数据加常数，ML 排序不变 |
| **置换** | f(permute(x)) = f(x) | 数据集行顺序改变，分类不变 |
| **单调** | x₁ ≤ x₂ → f(x₁) ≤ f(x₂) | 增加训练数据，模型准确率不降 |
| **加法** | f(x + Δ) = g(f(x), Δ) | sin(x + 2π) = sin(x) |
| **乘法** | f(k × x) = h(f(x), k) | 所有特征 × 2，预测应成比例 |

### 3.3 蜕变测试在 ML 中的应用

这是蜕变测试最闪耀的场景——ML 模型没有确定的"正确输出"：

```python
# 图像分类器的蜕变测试
def test_image_classifier_metamorphic(classifier, image):
    # MR1: 轻微旋转不应改变分类（恒等关系）
    rotated = rotate(image, angle=5)
    assert classifier(image) == classifier(rotated)

    # MR2: 轻微噪声不应改变分类（恒等关系）
    noisy = add_gaussian_noise(image, sigma=0.01)
    assert classifier(image) == classifier(noisy)

    # MR3: 亮度变化不应改变分类（恒等关系）
    brightened = adjust_brightness(image, factor=0.9)
    assert classifier(image) == classifier(brightened)

    # MR4: 水平翻转不应改变"对称物体"的分类（部分恒等）
    flipped = horizontal_flip(image)
    if is_symmetric_object(image):
        assert classifier(image) == classifier(flipped)

    # MR5: 置信度应该合理（单调关系）
    blurred = gaussian_blur(image, radius=5)
    # 模糊图像的分类置信度不应该比原图更高
    assert classifier.confidence(image) >= classifier.confidence(blurred)
```

### 3.4 蜕变测试在 NLP/AI 中的应用

这对你的 PydanticAI 项目至关重要：

```python
def test_ai_agent_metamorphic(agent):
    # MR1: 同义改写不应该产生完全不同的输出（语义恒等）
    prompt1 = "推荐 3 本 Python 编程书"
    prompt2 = "请给我介绍 3 本适合学 Python 的书籍"
    result1 = agent.run(prompt1)
    result2 = agent.run(prompt2)
    # 两个结果的结构应该一致
    assert type(result1) == type(result2)

    # MR2: 更具体的 prompt 不应该得到更少的信息（单调关系）
    general = agent.run("介绍机器学习")
    specific = agent.run("介绍 Python 机器学习入门书籍")
    # 更具体的问题应该有至少一样多的信息量
    assert len(specific) >= len(general) * 0.5

    # MR3: 相同 prompt 多次执行，输出应该不同但结构一致
    results = [agent.run("推荐 3 本书") for _ in range(5)]
    # 5 次结果不应该完全一样（AI 有随机性）
    assert len(set(results)) > 1
    # 但每次都应该包含书的信息
    for r in results:
        assert "书" in r or "book" in r.lower()
```

---

## 四、断言模式

### 4.1 断言设计的层次

```
Level 1: 存在性断言 — "输出里有没有这个字段？"
  assert "name" in result

Level 2: 类型断言 — "这个字段的类型对不对？"
  assert isinstance(result["age"], int)

Level 3: 范围断言 — "这个值在合理范围内吗？"
  assert 0 <= result["age"] <= 150

Level 4: 关系断言 — "这几个字段之间的关系对不对？"
  assert result["end_time"] >= result["start_time"]

Level 5: 精确断言 — "这个值就是预期的值"
  assert result["age"] == 42
```

**原则**：尽量用 Level 1-4 的断言。Level 5 的精确断言最脆弱。

### 4.2 断言的反模式

| 反模式 | 例子 | 问题 |
|--------|------|------|
| **脆弱断言** | `assert json_str == '{"name":"John"}'` | 空格、顺序、缩进一变就碎 |
| **过度断言** | `assert len(result) == 5 and result[0].name == "A" and ...` | 一个测试测太多，失败不知道原因 |
| **无意义断言** | `assert result is not None` | 太弱，几乎没用 |
| **魔法值** | `assert discount == 0.13` | 这个 0.13 从哪里来？后人看不懂 |

### 4.3 好断言的特征

| 特征 | 例子 |
|------|------|
| **描述行为** | `assert user_can_login("admin", "password")` |
| **一个断言测一件事** | 不要 10 个 assert 在一个测试里 |
| **失败信息清晰** | `assert age > 0, f"age should be positive, got {age}"` |
| **容错（允许合理的变异）** | `assert abs(actual - expected) < 0.01` |

---

## 五、GenAI 系统的预言问题

### 5.1 GenAI 测试的根本挑战

GenAI 测试面临双重预言问题：

```
问题 1: 输出不确定 —— 相同输入每次输出不同
问题 2: 没有正确答案 —— "好的 AI 回复"没有客观标准
```

**传统 TDD 的精确断言完全失效。**

### 5.2 GenAI 测试的预言策略

对你的 PydanticAI 项目的具体建议：

```python
# ❌ 不要这样测
def test_agent_response():
    result = agent.run("推荐 3 本书")
    assert result == "《深入理解计算机系统》《代码大全》《设计模式》"
    # AI 每次输出不同，这个测试必然失败！

# ✅ 应该这样测
def test_agent_response():
    result = agent.run("推荐 3 本书")
    data = json.loads(result)

    # 1. 结构断言：输出必须是合法 JSON
    # （Level 1: 存在性）

    # 2. 属性断言：必须包含必填字段
    assert "books" in data  # （Level 1）
    assert isinstance(data["books"], list)  # （Level 2）
    assert len(data["books"]) >= 3  # （Level 3）

    # 3. 蜕变断言：更具体的 prompt，结果更精确
    specific = agent.run("推荐 3 本 Python 入门书")
    specific_data = json.loads(specific)
    # 更具体的问题，书的数量不应该更多
    assert len(specific_data["books"]) <= len(data["books"])

    # 4. 安全断言：不能泄露 PII
    for book in data["books"]:
        assert "@" not in book  # 不应该包含邮箱地址
        assert not re.search(r'\d{11}', book)  # 不应该包含手机号

    # 5. 统计断言（运行多次）：
    # 多次运行应该都返回合法 JSON
    for _ in range(10):
        r = agent.run("推荐 3 本书")
        assert json.loads(r)  # 不会抛异常
```

---

## 六、部分预言

### 6.1 什么是部分预言

**部分预言 = 不验证完整的输出，只验证输出的某些方面。**

| 部分预言 | 说明 | 例子 |
|---------|------|------|
| **无崩溃** | 程序不崩溃、不抛异常 | 最基本的预言 |
| **无挂起** | 程序不无限循环、不超时 | 超时检测 |
| **结构合法** | 输出结构符合预期 | JSON Schema 验证 |
| **类型正确** | 输出类型符合预期 | isinstance 检查 |
| **范围合理** | 输出值在合理范围内 | 年龄 0-150 |
| **关系保持** | 输出之间的关系正确 | end > start |

### 6.2 部分预言的层次策略

```
完整测试策略 = 精确预言（确定性部分）
              + 部分预言（非确定性部分）
              + 蜕变预言（输入-输出关系）
              + 无崩溃（最低保障）
```

---

## 七、预言选择对 AI 测试生成的启示

### 7.1 AI 应该做预言选择

当前的 AI 测试生成工具（Copilot、ChatGPT）默认生成精确断言。这是错误的默认。

**AI 应该在生成测试前回答：**

1. 这个函数的输出是确定性的吗？→ 精确预言
2. 这个函数的输出有已知的属性吗？→ 属性预言
3. 输入的变化如何影响输出？→ 蜕变预言
4. 输出的基本合法性？→ 部分预言

### 7.2 对 adversarial-tdd 的启示

你的 adversarial-tdd 中的测试设计师 Agent 目前默认写精确断言。应该增加预言选择能力：

```
风险分析阶段新增：预言类型选择

功能: AI 书籍推荐
确定性: 非确定性（AI 输出每次不同）
预言类型: 部分预言 + 蜕变预言
  - 部分预言 1: 输出必须是合法 JSON
  - 部分预言 2: 输出必须包含 books 字段
  - 部分预言 3: books 是列表且至少有 1 个元素
  - 蜕变预言 1: 更具体的 prompt，结果更精确
  - 蜕变预言 2: 相同 prompt 多次运行，结果不应完全相同
```

---

## 八、总结：预言选择的核心原则

| # | 原则 | 说明 |
|---|------|------|
| 1 | **预言问题是测试的根本瓶颈** | 判断输出对不对 > 生成输入 |
| 2 | **精确断言是最脆弱的预言** | 只在确定性的场景使用 |
| 3 | **蜕变测试是 AI/ML 测试的关键** | 验证输入-输出关系，不验证具体值 |
| 4 | **部分预言好于无预言** | 结构合法性、类型正确性 > 没有检查 |
| 5 | **GenAI 测试需要多层预言** | 结构 → 属性 → 蜕变 → 安全 → 统计 |
| 6 | **AI 必须学会选择预言类型** | 不同场景需要不同预言，不能全是精确断言 |

---

*上一章：[Layer 5 - 形式验证](./layer-05-formal-verification.md)*  
*下一章：[Layer 7 - 认知循环](./layer-07-cognitive-loop.md)*