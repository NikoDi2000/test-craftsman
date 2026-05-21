# Layer 5 深度报告：形式验证

---

## 一、形式验证的定位

### 1.1 测试 vs 验证

测试和形式验证处于质量保障光谱的两端：

```
测试 ──────────────────────────── 形式验证
"证明存在 bug"                   "证明没有 bug"
特定输入验证                      所有输入验证
可能有遗漏                        穷举（在给定深度内）
容易上手                          学习曲线陡峭
成本低                            成本高
```

**它们不是替代关系，而是互补关系。**

### 1.2 形式验证的核心思想

形式验证不运行程序。它用数学方法证明程序满足某个属性：

```
程序 P 是否满足属性 φ？
  → 将 P 和 ¬φ 编码为逻辑公式
  → 用 SAT/SMT 求解器求解
  → 如果可满足 → 找到反例（P 违反 φ）
  → 如果不可满足 → P 满足 φ（在搜索范围内）
```

---

## 二、契约式设计

### 2.1 Bertrand Meyer 的原始构想

Bertrand Meyer 在 1986 年提出 Design by Contract（DbC）。核心思想：**每个函数有一个契约，定义了调用者的义务（前置条件）和被调用者的承诺（后置条件）。**

```
契约 = 前置条件 + 后置条件 + 不变量

前置条件: 调用者必须保证什么
后置条件: 被调用者保证什么（当前置条件满足时）
不变量: 始终为真的属性
```

### 2.2 契约的代码表示

**Python 风格**：
```python
def transfer(from_account, to_account, amount):
    """
    转账

    前置条件:
        - amount > 0
        - from_account.balance >= amount
        - from_account != to_account

    后置条件:
        - from_account.balance == old(from_account.balance) - amount
        - to_account.balance == old(to_account.balance) + amount

    不变量:
        - 所有账户的总余额不变
    """
    from_account.balance -= amount
    to_account.balance += amount
```

**Eiffel 原生风格**（Meyer 的语言）：
```eiffel
transfer (from_account, to_account: ACCOUNT; amount: INTEGER) is
    require
        amount > 0
        from_account.balance >= amount
        from_account /= to_account
    do
        from_account.withdraw(amount)
        to_account.deposit(amount)
    ensure
        from_account.balance = old from_account.balance - amount
        to_account.balance = old to_account.balance + amount
    end
```

### 2.3 契约的三个层次

```
弱契约: 前置条件少，后置条件多 → 调用者负担小，实现者负担大
强契约: 前置条件多，后置条件少 → 调用者负担大，实现者负担小

正确的契约应该平衡两者。
```

**契约强度选择原则**：
- 库函数：弱前置条件（调用者不应该知道太多内部细节）
- 内部函数：强前置条件（调用者是同事，知道约束）
- 安全关键函数：强前置条件 + 强后置条件（双重保险）

---

## 三、Bounded Model Checking

### 3.1 BMC 的原理

BMC 是形式验证中最实用、工业应用最广泛的技术。

**核心思想**：不验证所有可能的执行，只验证到给定深度 k。

```
BMC 的公式编码:

P(k) = I(s₀) ∧ T(s₀, s₁) ∧ T(s₁, s₂) ∧ ... ∧ T(sₖ₋₁, sₖ) ∧ (¬φ(sₖ))

其中:
  I(s₀): 初始状态约束
  T(sᵢ, sᵢ₊₁): 从状态 i 到状态 i+1 的转换关系
  φ(sₖ): 要证明的属性（安全属性）
  ¬φ(sₖ): 属性的否定——我们要找违反属性的状态
```

**如果公式可满足 → 找到反例**：存在一条长度 ≤ k 的执行路径，最终违反属性 φ。

**如果公式不可满足 → 在深度 k 内没有反例**：程序在 k 步内不会违反属性 φ。这不等价于完全正确，但足够发现大多数 bug。

### 3.2 BMC 的适用场景

BMC 特别适合发现**浅层 bug**——在少量步骤内就能触发的错误：

| 适用 | 不适用 |
|------|--------|
| 数组越界 | 需要深循环的复杂算法正确性 |
| 空指针解引用 | 无限状态系统的活性属性 |
| 缓冲区溢出 | 并发系统的完全验证 |
| 断言违反 | 需要归纳证明的属性 |
| 除零错误 | |
| 整数溢出 | |

**关键发现**：对于安全关键代码（如 AWS 的 C 库），大多数内存安全 bug 在 10 步以内就能触发。BMC 在这个深度内非常有效。

---

## 四、CBMC

### 4.1 CBMC 简介

CBMC（C Bounded Model Checker）是使用最广泛的软件验证工具之一，由 Daniel Kroening 开发。

**特点**：
- 直接处理 C 代码（不需要模型转换）
- 验证内存安全（数组越界、空指针、缓冲区溢出）
- 验证用户断言
- 被 Linux 内核开发者、AWS 等使用

### 4.2 CBMC 的工作流程

```bash
# 1. 写一个带断言的 C 程序
cat > example.c << 'EOF'
#include <assert.h>

int binary_search(int *arr, int size, int target) {
    int low = 0, high = size - 1;
    while (low <= high) {
        int mid = (low + high) / 2;
        if (arr[mid] == target) return mid;
        if (arr[mid] < target) low = mid + 1;
        else high = mid - 1;
    }
    return -1;
}

int main() {
    int arr[10];
    int target;
    // arr 和 target 是符号值（任意值）
    int result = binary_search(arr, 10, target);
    if (result != -1) {
        assert(arr[result] == target);  // 后置条件
        assert(0 <= result && result < 10);  // 边界检查
    }
    return 0;
}
EOF

# 2. 运行 CBMC
cbmc example.c --unwind 20  # 循环最多展开 20 次

# 3. 解读结果
# VERIFICATION SUCCESSFUL → 在 20 次循环内没有 bug
# VERIFICATION FAILED → CBMC 输出反例（具体输入值）
```

### 4.3 CBMC 的验证能力

| 验证项 | 自动 | 需要注解 |
|--------|------|---------|
| 数组越界 | ✅ 自动 | |
| 空指针解引用 | ✅ 自动 | |
| 除零错误 | ✅ 自动 | |
| 整数溢出 | ✅ 自动 | |
| 缓冲区溢出 | ✅ 自动 | |
| 内存泄漏 | ✅ 自动 | |
| 业务逻辑正确性 | | ✅ 需要 `assert` |
| 算法正确性 | | ✅ 需要 `assert` |
| 不变量维护 | | ✅ 需要 `__CPROVER_assert` |

---

## 五、Unit Proof

### 5.1 什么是 Unit Proof

Unit Proof 是将 BMC 应用到单个函数的实践方法。Amazon/AWS 在安全关键组件中广泛使用这种模式。

**核心模板**：

```c
int parse_packet(uint8_t *buf, size_t len) {
    // Step 1: ASSUME（前置条件）
    __CPROVER_assume(buf != NULL);
    __CPROVER_assume(len <= MAX_PACKET_SIZE);
    __CPROVER_assume(len >= MIN_PACKET_SIZE);

    // Step 2: 函数体（被测代码）
    PacketHeader header;
    parse_header(buf, len, &header);
    
    // Step 3: ASSERT（后置条件）
    assert(header.version <= MAX_VERSION);
    assert(header.payload_size <= len - HEADER_SIZE);
    assert(header.payload_size >= 0);
    
    return header.payload_size;
}
```

**CBMC 会尝试所有满足 `__CPROVER_assume` 的输入，验证所有路径都不会违反任何 `assert`。**

### 5.2 Unit Proof 的价值

| 测试 | Unit Proof |
|------|-----------|
| 测试 1 个具体输入 | 验证所有合法输入 |
| "这个输入通过了" | "没有输入能导致崩溃" |
| 覆盖率 ≈ 选择输入的质量 | 覆盖率 = 100%（在给定深度内） |

**Unit Proof 适合的场景**：
- 安全关键代码（加密、认证、权限）
- 输入解析代码（协议解析、文件格式解析）
- 数学/算法代码（排序、搜索、数据结构）

---

## 六、LLM + 形式验证

### 6.1 UnitTenX

UnitTenX (2025) 将 LLM 与 CBMC 结合，为遗留 C 代码自动生成 Unit Proof：

```
LLM 分析代码 → 生成候选 assume/assert → 
CBMC 验证 → 发现证明失败 → 
LLM 修正 assume/assert → 循环直到通过
```

**关键创新**：形式验证工具作为"外部真值源"，打破 LLM 的自我验证循环。LLM 不能"自欺欺人"——CBMC 会严格检查。

### 6.2 对 AI 测试生成的启示

这个模式可以推广到其他语言：

```
AI 生成测试 + 形式验证 = AI 不能自欺欺人的测试

Python: pytest + hypothesis + Z3（SMT 求解器）
Dart: test + 手动 assume/assert + 符号执行
C#: xUnit + 手动 assume/assert + 符号执行
```

---

## 七、不变量推断

### 7.1 什么是程序不变量

不变量 = 在程序执行的某个点始终为真的属性。

```python
def find_max(arr):
    max_val = arr[0]
    for i in range(1, len(arr)):
        # 循环不变量: max_val 是 arr[0:i] 中的最大值
        if arr[i] > max_val:
            max_val = arr[i]
    return max_val
```

### 7.2 不变量推断工具

| 工具 | 方法 | 适用 |
|------|------|------|
| **Daikon** | 动态分析（运行程序，观察不变属性） | 通用 |
| **LoopInvGen** | ML + 逻辑推理 | C 程序 |
| **Gin-Dyn** | 遗传算法 + 动态分析 | Java |
| **LLM-based** | LLM 从代码语义推理 | 新兴方向 |

### 7.3 不变量在测试中的作用

不变量是"永真"的断言。把它们加入测试可以捕获更多错误：

```python
def test_stack_operations():
    stack = Stack()
    
    # 不变量：push 后栈不为空
    stack.push(1)
    assert not stack.is_empty()
    
    # 不变量：push-pop 组合后栈恢复原状
    stack.push(2)
    stack.pop()
    assert stack.peek() == 1
```

---

## 八、对 adversarial-tdd 的启示

你的 adversarial-tdd 可以增加一个 Layer 5 的形式验证维度：

1. **在风险分析中增加契约定义**：让测试设计师定义前置条件、后置条件、不变量
2. **实现者必须满足后置条件**：不满足则实现未完成
3. **审计员验证契约覆盖**：测试是否覆盖了所有契约条款

```
增强的风险分析模板：

功能: 转账
前置条件:
  1. amount > 0
  2. from_account 存在
  3. to_account 存在
  4. from_account.balance >= amount

后置条件:
  1. from_account.balance 减少 amount
  2. to_account.balance 增加 amount
  3. 返回成功

不变量:
  1. 总余额不变
  2. 没有账户余额变为负数

痛苦场景:
  1. amount 为负数 → 前置条件违反 → 应返回错误
  2. from_account 不存在 → 前置条件违反 → 应返回错误
  3. from_account.balance 不足 → 前置条件违反 → 应返回错误
```

---

## 九、总结：形式验证的核心原则

| # | 原则 | 说明 |
|---|------|------|
| 1 | **验证 > 测试** | 验证证明"没有 bug"，测试只能"发现 bug" |
| 2 | **契约先行** | 前置条件 + 后置条件 + 不变量 = 完整的功能规格 |
| 3 | **BMC 是实用的** | 不要求完全正确，但在给定深度内提供保证 |
| 4 | **外部真值源打破循环** | 形式验证工具验证 AI 的输出，AI 不能自欺欺人 |
| 5 | **Unit Proof 是单元测试的终极形态** | 验证所有输入，而非几个输入 |
| 6 | **不变量是活文档** | 不只是验证工具，也是理解代码的入口 |

---

*上一章：[Layer 4 - 对抗生成/变异测试](./layer-04-mutation-testing.md)*  
*下一章：[Layer 6 - 预言选择](./layer-06-oracle-selection.md)*