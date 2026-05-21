# Layer 1 深度报告：可测试性设计

---

## 一、可测试性的学术定义与理论基础

### 1.1 Freedman (1991) 的奠基性工作

Roy S. Freedman 在 1991 年 IEEE TSE 上发表的《Testability of Software Components》是可测试性理论的奠基之作。他首次将硬件测试中成熟的"可控性 + 可观测性"框架移植到软件领域。

**核心定义**：

```
Domain Testability = Observability × Controllability
```

- **可观测性（Observability）**：确定指定输入是否影响输出的容易程度。如果一个程序的输出不能唯一确定输入的影响，那么它就是不可观测的。
- **可控性（Controllability）**：从指定输入产生指定输出的容易程度。如果某些输出无法通过任何输入组合产生，那么该程序就是不可控的。

Freedman 进一步量化了这两个概念：
- **Ob**：使一个不可观测的程序变得可观测所需额外引入的二进制输入数量
- **Ct**：使一个不可控的程序变得可控所需额外引入的二进制输入数量

Ob 和 Ct 的值越大，程序的可测试性越差。

### 1.2 Voas 的 PIE 模型（故障敏感性）

Voas (1992) 从另一个角度定义了可测试性——故障敏感性（Fault Sensitivity）：

```
PIE = Execution × Infection × Propagation
```

- **Execution**：故障代码被执行的概率
- **Infection**：故障执行后感染程序状态的概率
- **Propagation**：被感染的状态传播到可观测输出的概率

**关键洞察**：PIE 模型解释了为什么高覆盖率 ≠ 高缺陷检测率。如果代码执行了故障但没有感染状态（Infection = 0），或者感染了但没有传播到输出（Propagation = 0），那么测试仍然无法发现 bug。

**PIE 模型的工业意义**：

```
高 PIE = 高可测试性 = 即使简单的测试也能发现 bug
低 PIE = 低可测试性 = 需要精心设计测试才能发现 bug
```

### 1.3 Binder (1994) 的 OO 可测试性框架

Binder 将 Freedman 的工作扩展到面向对象系统，提出了六维可测试性框架：

| 维度 | 定义 | 破坏该维度的反模式 |
|------|------|------------------|
| **可控制性** | 控制组件状态和输入的能力 | 隐藏状态、全局单例 |
| **可观测性** | 观察组件状态和输出的能力 | 无返回值的方法、private 状态 |
| **可隔离性** | 独立测试组件的能力 | 硬编码依赖、循环依赖 |
| **可自动化性** | 自动化测试执行的能力 | 需要 GUI 交互、需要人工判断 |
| **可理解性** | 理解组件行为的能力 | 过长方法、命名不清晰 |
| **异质性** | 使用不同测试方法的能力 | 平台绑定、环境依赖 |

---

## 二、Michael Feathers 的 Seams 理论

### 2.1 核心概念

Michael Feathers 在《Working Effectively with Legacy Code》(2004) 中提出了"Seams"（接缝）概念，这是将不可测试代码变为可测试代码的核心理论工具。

**定义**：

> "A Seam is a place where you can alter behavior in your program without editing in that place."

> "Every Seam has an Enabling Point."

**Seam（接缝）** = 你可以在不修改该位置代码的情况下改变其行为的位置。
**Enabling Point（启用点）** = 让你能够利用这个 Seam 的地方。

**关键区分**：
- Seam 本身是代码中的一个位置——比如一个方法调用点
- Enabling Point 是你可以在测试中做替换的地方——比如构造函数参数、配置文件、类路径

### 2.2 四种 Seam 类型

#### Object Seam（对象接缝）

**适用**：面向对象语言（Java、Python、C#、Dart、C++）

**Enabling Point**：构造函数的参数、setter 方法、工厂方法

```python
# 不可测试的代码——没有 Seam
class OrderService:
    def process(self, order_id):
        db = RealDatabase("prod://...")  # 硬编码
        payment = StripeGateway("sk_live_...")  # 硬编码
        # ... 业务逻辑

# 引入 Object Seam——通过依赖注入
class OrderService:
    def __init__(self, db=None, payment=None):
        self.db = db or RealDatabase("prod://...")
        self.payment = payment or StripeGateway("sk_live_...")
    
    def process(self, order_id):
        # ... 业务逻辑（不变）

# 测试时：
def test_order_processing():
    fake_db = FakeDatabase()
    fake_payment = FakePaymentGateway()
    service = OrderService(db=fake_db, payment=fake_payment)
    service.process(42)
    assert fake_payment.was_charged(99.99)
```

**Object Seam 的关键原则**：
1. 构造函数注入是最常见的 Enabling Point
2. 方法参数注入用于单次使用的依赖
3. 工厂方法替换用于需要延迟创建的依赖

#### Link Seam（链接接缝）

**适用**：编译型语言（C、C++、Java）、支持模块系统的语言（Python）

**Enabling Point**：链接时的库文件路径、类路径（classpath）

```python
# Python 中的 Link Seam 示例

# 生产环境的依赖
# production_payment.py
class PaymentGateway:
    def charge(self, amount):
        # 真实的 Stripe 调用
        ...

# 测试时替换——修改 PYTHONPATH 或 import 路径
# test_payment.py（放在 PYTHONPATH 更靠前的位置）
class PaymentGateway:
    def charge(self, amount):
        # 什么都不做
        return {"status": "ok"}
```

**Link Seam 的风险**（Feathers 特别警告）：
> "Take pains to make sure the difference between test and production environments is obvious when using link seams, because it's easy for that to get buried in a build script somewhere."

#### Preprocessing Seam（预处理接缝）

**适用**：C/C++（`#ifdef`）、任何支持预处理的语言

**Enabling Point**：预处理器宏定义

```c
// 生产和测试共享同一文件
#ifdef TESTING
    #define DATABASE_URL "mock://localhost"
#else
    #define DATABASE_URL "prod://realdb.company.com"
#endif
```

**预处理接缝的缺点**：
- 编译时决策，无法运行时切换
- 容易导致 `#ifdef` 地狱
- 测试代码和生产代码混在同一文件中

#### Text Seam（文本接缝）

**适用**：动态语言（Python、JavaScript、Ruby）

**Enabling Point**：运行时的 monkey-patching

```python
# Python 的 Text Seam——Monkey Patching
def test_send_email():
    # 保存原始函数
    original_send = email_service.send
    
    # 替换
    email_service.send = lambda *args: None
    
    # 运行测试
    register_user("test@example.com")
    
    # 恢复
    email_service.send = original_send
```

**Text Seam 的风险**：
- 极难追踪——替换发生在运行时，没有编译时检查
- 测试之间可能互相污染
- 不推荐作为主要策略，只作为最后手段

### 2.3 Feathers 的遗留代码变更算法

Feathers 提出了一套在遗留代码（= 没有测试的代码）上安全工作的算法：

```
1. Identify Change Points    → 找到你要改的地方
2. Find Test Points          → 找到你可以加测试的 Seam
3. Break Dependencies        → 用 Seam 断开依赖（最小侵入性重构）
4. Write Tests               → 加上 Characterization Tests
5. Make Changes + Refactor   → 安全修改 + 清理代码
```

**注意**：写新代码是最后一步。在此之前，大部分工作是理解和小心地选择切入点。

### 2.4 遗留代码困境（Legacy Code Dilemma）

```
要安全改代码 → 需要测试
要加测试     → 需要改代码（断开依赖）
```

Feathers 的解决方案：**做极其保守、极小的重构来断开依赖。这些重构可以在没有测试的情况下安全完成。**

保守重构的例子：
- **Extract Method**：把一个纯计算的部分提取成独立函数
- **Introduce Parameter**：把硬编码的值改成参数
- **Extract Interface**：为一个类提取接口

这些重构之所以"安全"，是因为它们是**机械性的、可逆的、不影响外部行为的**。

---

## 三、可测试性度量：从静态指标到动态证据

### 3.1 传统方法：基于软件度量的静态指标

Chidamber & Kemerer (C-K) 度量套件是最常用于评估 OO 可测试性的：

| 度量 | 含义 | 对可测试性的影响 |
|------|------|----------------|
| **WMC** (加权方法数) | 类的复杂度 | WMC 高 → 更难测 |
| **DIT** (继承深度) | 继承层次深度 | DIT 高 → 更难隔离 |
| **NOC** (子类数量) | 多少子类继承 | NOC 高 → 父类变更影响大 |
| **CBO** (耦合度) | 与其他类的耦合 | CBO 高 → 更难隔离 |
| **RFC** (响应集) | 一个方法调用的其他方法数 | RFC 高 → 更难控制 |
| **LCOM** (内聚缺失) | 方法之间的关联度 | LCOM 高 → 更难理解 |

**静态度量的致命缺陷**（Bruntink et al., 多项研究）：
- 不同研究得出**矛盾的结果**——某个度量在一些研究中是好预测器，在另一些研究中不是
- 依赖于被研究的项目样本
- 没有统一的可测试性标准

### 3.2 新方法：基于自动测试生成的可测试性估计

Guglielmo, Mariani & Denaro (2023) 提出了一个革命性的方法——**不用静态度量，直接用自动测试生成和变异分析来量化可测试性**：

```
可测试性证据 = 自动生成的测试 + 变异分析
```

**方法**：
1. 用 EvoSuite（自动测试生成工具）生成测试套件
2. 运行变异分析
3. 从变异分析结果中提取两类证据：

| 证据类型 | 含义 |
|---------|------|
| **可控性证据** | 变异体被执行的比例——说明 API 是否提供了足够的手段来控制程序 |
| **可观测性证据** | 变异体被杀死的比例——说明输出是否能暴露故障 |

**关键发现**：
- 这种基于动态证据的可测试性估计捕捉了**传统静态度量无法捕捉的维度**
- 结合静态度量和动态证据，预测准确度最高
- 这意味着：**可测试性不只是代码结构的问题，也是 API 设计的问题**

---

## 四、核心可测试性模式

### 4.1 依赖注入（Dependency Injection）

这是创建 Object Seam 的最标准方式。

**三种注入方式**：

```python
# 1. 构造函数注入（Constructor Injection）
class UserService:
    def __init__(self, db: Database):
        self.db = db  # Enabling Point: 构造函数参数

# 2. 方法参数注入（Method Injection）
class UserService:
    def register(self, user, email_service=None):
        email_service = email_service or RealEmailService()
        # Enabling Point: 方法参数

# 3. 属性注入（Property Injection）
class UserService:
    db: Database = None
    
service = UserService()
service.db = FakeDatabase()  # Enabling Point: 公开属性
```

### 4.2 接口隔离（Interface Segregation）

Feathers 的核心原则：**Seam 最好建立在接口上。**

```python
# 坏：Seam 建立在具体类上
class OrderService:
    def __init__(self, db: PostgresDatabase):  # 具体类
        ...

# 好：Seam 建立在接口上
from abc import ABC, abstractmethod

class Database(ABC):
    @abstractmethod
    def query(self, sql: str): ...

class OrderService:
    def __init__(self, db: Database):  # 抽象接口
        ...
```

### 4.3 Characterization Tests（特征测试）

Feathers 引入的一种特殊测试——不测试"应该做什么"，而是测试"实际做什么"：

```python
# 传统测试：验证"应该做什么"
def test_discount_calculator():
    assert calculate_discount(150) == 15  # 我知道正确结果

# Characterization Test：记录"实际做什么"
def test_discount_calculator_characterization():
    # 步骤 1: 写一个明显错误的预期
    # 步骤 2: 运行测试 → 看到实际输出
    # 步骤 3: 用实际输出替换预期
    assert calculate_discount(99.99) == 12  # 我不知道对不对，但这就是现在的行为
```

**Characterization Test 的价值**：
- 锁住当前行为——即使是 bug（先把 bug 锁住，后面再决定是否修复）
- 提供安全网——任何后续修改都能立即知道是否改变了行为
- 不需要理解业务逻辑——只需要观察输入输出

### 4.4 Sprout Method / Sprout Class

当你需要在不可测试的代码中添加新功能时，不要直接在旧代码中加，而是"发芽"出新方法/新类：

```python
# 旧代码：不可测试
class LegacyReportGenerator:
    def generate(self, data):
        # 2000 行不可测试的逻辑
        total = 0
        for item in data:
            # 需要加折扣计算
            # ... 复杂逻辑
            pass

# Sprout Method：从旧代码中"发芽"出可测试的新方法
class LegacyReportGenerator:
    def generate(self, data):
        # ... 旧逻辑
        discount = self.calculate_discount(data)  # 新方法
        # ...

    @staticmethod
    def calculate_discount(data):
        # 这个方法是全新的，可以独立测试
        if len(data) > 100:
            return 0.10
        return 0.0

# 测试只测新方法
def test_calculate_discount():
    assert LegacyReportGenerator.calculate_discount([1]*200) == 0.10
    assert LegacyReportGenerator.calculate_discount([1]) == 0.0
```

### 4.5 Wrap Method / Wrap Class

用装饰器模式包装不可测试的代码：

```python
# 旧代码：直接调用外部支付
class PaymentProcessor:
    def process(self, amount):
        # 直接调 Stripe，不可测试
        stripe.Charge.create(amount=amount)

# Wrap Class：用可测试的包装器包裹
class LoggingPaymentProcessor(PaymentProcessor):
    def __init__(self, wrapped):
        self.wrapped = wrapped
        self.log = []
    
    def process(self, amount):
        self.log.append(f"Processing {amount}")
        result = self.wrapped.process(amount)
        self.log.append(f"Result: {result}")
        return result

# 测试 LoggingPaymentProcessor 不依赖真实的 Stripe
def test_logging():
    fake = FakePaymentProcessor()
    wrapped = LoggingPaymentProcessor(fake)
    wrapped.process(100)
    assert "Processing 100" in wrapped.log
```

---

## 五、可测试性的反模式

### 5.1 全局状态

```python
# 反模式：模块级全局变量
CURRENT_USER = None

def get_dashboard():
    if CURRENT_USER.is_admin:  # 测试时必须设置全局状态
        ...
    else:
        ...

# 可测试的版本
def get_dashboard(user):
    if user.is_admin:
        ...
```

### 5.2 隐式依赖

```python
# 反模式：在函数内部创建依赖
def send_notification(user_id, message):
    db = Database()  # 隐式依赖——无法替换
    email = EmailService()  # 隐式依赖——无法替换
    user = db.get_user(user_id)
    email.send(user.email, message)

# 可测试的版本
def send_notification(user_id, message, db=None, email=None):
    db = db or Database()
    email = email or EmailService()
    ...
```

### 5.3 不可观测的输出

```python
# 反模式：函数没有返回值，输出不可观测
def validate_order(order):
    if order.total <= 0:
        raise ValidationError()  # 异常是输出
    order.status = "validated"  # 状态修改是输出
    order.db.save()  # 数据库操作是输出

# 可测试的版本：分离"计算"和"副作用"
def validate_order(order) -> ValidationResult:
    if order.total <= 0:
        return ValidationResult(error="invalid_total")
    return ValidationResult(ok=True)

def apply_validation(order, result):
    if result.ok:
        order.status = "validated"
        order.db.save()
    else:
        raise ValidationError(result.error)
```

### 5.4 非确定性行为

```python
# 反模式：依赖当前时间
def is_promotion_active():
    now = datetime.now()  # 每次运行结果不同
    return now < datetime(2024, 12, 31)

# 可测试的版本
def is_promotion_active(now=None):
    now = now or datetime.now()  # 可注入
    return now < datetime(2024, 12, 31)
```

---

## 六、各技术栈的可测试性策略

### 6.1 Python / FastAPI / PydanticAI

**Python 的优势**：
- 动态类型 → monkey-patching 容易（Text Seam）
- `unittest.mock` 内置 → 强大的 Mock 能力
- FastAPI 原生支持 `Depends()` → 自动依赖注入

**常见问题**：
- 全局模块级变量
- 函数内直接创建数据库连接
- AI Agent 调用外部 API 不可替换

**策略**：

```python
# FastAPI: 利用 Depends() 实现 Object Seam
from fastapi import Depends

def get_db():
    return RealDatabase()

@app.get("/users/{id}")
def get_user(id: int, db: Database = Depends(get_db)):
    return db.get_user(id)

# 测试时：替换 Depends
app.dependency_overrides[get_db] = lambda: FakeDatabase()
```

```python
# PydanticAI: Agent 的 Seam 策略
class MyAgent:
    def __init__(self, llm_client=None):
        self.llm = llm_client or RealLLMClient()
    
    def run(self, prompt: str) -> str:
        return self.llm.complete(prompt)

# 测试时：注入假 LLM
def test_agent_prompt():
    fake_llm = FakeLLMClient(responses=["Hello World"])
    agent = MyAgent(llm_client=fake_llm)
    result = agent.run("Say hello")
    assert "Hello" in result
```

### 6.2 Dart / Flutter

**Dart/Flutter 的特殊挑战**：
- `BuildContext` 是隐式依赖——几乎所有 Widget 方法都需要它
- Widget 树的构造和测试隔离困难
- Navigator、Theme、MediaQuery 都是通过 BuildContext 获取的全局状态

**策略**：

```dart
// 反模式：Widget 直接使用 Navigator
class MyButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        // 不可测试——依赖 BuildContext 和 Navigator 全局状态
        Navigator.push(context, MaterialPageRoute(...));
      },
      child: Text('Go'),
    );
  }
}

// 可测试的版本：将导航逻辑提取为回调
class MyButton extends StatelessWidget {
  final VoidCallback onPressed;
  
  const MyButton({required this.onPressed});
  
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      child: Text('Go'),
    );
  }
}

// 测试
testWidgets('button calls onPressed', (tester) async {
  bool wasPressed = false;
  await tester.pumpWidget(
    MaterialApp(
      home: MyButton(onPressed: () => wasPressed = true),
    ),
  );
  await tester.tap(find.byType(ElevatedButton));
  expect(wasPressed, true);
});
```

### 6.3 C# / Unity

**Unity 的特殊挑战**：
- `MonoBehaviour` 生命周期方法（`Start()`, `Update()`, `OnCollisionEnter()`）由引擎调用
- `GameObject.Find()`, `GetComponent<>()` 依赖场景层级结构
- 协程依赖 MonoBehaviour 的 `StartCoroutine()`
- `Time.deltaTime`, `Input.GetAxis()` 等全局静态方法

**策略**：

```csharp
// 反模式：MonoBehaviour 直接依赖场景对象
public class Player : MonoBehaviour {
    void Update() {
        // 不可测试——依赖全局 Input
        float move = Input.GetAxis("Horizontal");
        // 不可测试——依赖 GameObject.Find
        GameObject enemy = GameObject.Find("Enemy");
        // ...
    }
}

// 可测试的版本：分离业务逻辑
public class PlayerController {
    public float CalculateMovement(float inputAxis, float speed) {
        return inputAxis * speed * Time.deltaTime;
    }
}

// MonoBehaviour 只做薄层——把输入传给业务逻辑
public class Player : MonoBehaviour {
    private PlayerController controller = new PlayerController();
    
    void Update() {
        float input = Input.GetAxis("Horizontal");
        float movement = controller.CalculateMovement(input, 5f);
        transform.Translate(movement, 0, 0);
    }
}

// 测试（不依赖 Unity 引擎）
[Test]
public void CalculateMovement_ReturnsZero_WhenInputIsZero() {
    var controller = new PlayerController();
    var result = controller.CalculateMovement(0f, 5f);
    Assert.AreEqual(0f, result);
}
```

---

## 七、可测试性对 AI 测试生成的影响

### 7.1 核心洞察

**AI 不应该尝试测试不可测试的代码。** 如果代码本身缺少 Seams，AI 生成的测试必然是脆弱的（需要 Mock 整个外部世界）或者根本无法运行。

### 7.2 AI 应该做的可测试性评估

在生成测试之前，AI 应该回答三个问题：

```
Q1: 这段代码的每个外部依赖（数据库、HTTP、文件系统）都可以被替换吗？
   → 如果不能：Object Seam 缺失

Q2: 这段代码运行 100 次，每次都返回相同的结果吗？
   → 如果不能：非确定性行为（时间、随机数、全局状态）

Q3: 这段代码的输出可以直接被观察到吗？
   → 如果不能：可观测性缺失
```

### 7.3 AI 对不可测试代码的响应

如果代码不可测试，AI 应该：

1. **不勉强生成测试**——生成的测试要么跑不起来，要么是假的
2. **建议最小重构**——只做机械性、可逆的重构来引入 Seam
3. **先写 Characterization Test**——锁住当前行为，然后安全重构
4. **重构后再写测试**——这才是正确的测试

---

## 八、总结：可测试性设计的核心原则

| # | 原则 | 说明 |
|---|------|------|
| 1 | **每个外部依赖都应该有一个 Object Seam** | 构造函数参数、方法参数、工厂方法 |
| 2 | **分离计算和副作用** | 计算函数（纯函数）→ 副作用函数（IO）|
| 3 | **所有输入都应该是显式的** | 时间、随机数、全局状态都通过参数传入 |
| 4 | **所有输出都应该是可观测的** | 返回值 > 状态修改 > 异常 > 日志 |
| 5 | **测试也是客户端** | 如果测试用起来别扭，API 设计有问题 |
| 6 | **先锁住行为，再重构** | Characterization Tests → 重构 → 新测试 |
| 7 | **Seam 建立在接口上，不是具体类上** | 抽象 > 具体 |

---

*下一层：[Layer 2 - 输入空间建模](./layer-02-input-space.md)*