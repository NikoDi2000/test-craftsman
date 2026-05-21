# 安装指南

## 方式一：OpenCode Plugin（推荐）

参考 [Superpowers](https://github.com/obra/superpowers) 和 [Anthropic Skills](https://github.com/anthropics/skills) 的实践，使用 OpenCode 原生 plugin 系统安装。

在项目根目录的 `opencode.json` 中添加：

```json
{
  "plugin": ["test-craftsman@git+https://github.com/NikoDi2000/test-craftsman.git"]
}
```

重启 OpenCode，plugin 会自动注册所有 Skill 和 Agent。

锁定版本：

```json
{
  "plugin": ["test-craftsman@git+https://github.com/NikoDi2000/test-craftsman.git#v1.0.0"]
}
```

> **注意**：此方式依赖 OpenCode 的 plugin 系统支持 git 仓库作为 plugin 源。如果你的 OpenCode 版本不支持，请使用方式二。

### 配置 Agent 权限

无论使用哪种安装方式，都需要在 `opencode.json` 中配置 Agent 权限：

```json
{
  "plugin": ["test-craftsman@git+https://github.com/NikoDi2000/test-craftsman.git"],
  "agent": {
    "build": {
      "permission": {
        "task": {
          "测试设计师": "allow",
          "实现者": "allow",
          "测试审计员": "allow",
          "集成测试工程师": "allow"
        }
      }
    }
  }
}
```

按需安装时，只包含对应 Skill 需要的 Agent：

| Skill | 需要的 Agent |
|-------|-------------|
| adversarial-tdd | 测试设计师 + 实现者 + 测试审计员 |
| property-based-testing | 测试设计师 |
| api-integration-testing | 测试设计师 + 集成测试工程师 + 测试审计员 |

## 方式二：安装脚本

参考 [Claude Code](https://claude.ai/install.sh) 和 [OpenCode](https://opencode.ai/install) 的 `curl | bash` 模式，提供一键安装脚本。

```bash
# 安装全部（ATDD + PBT + API 集成测试）
curl -sSL https://raw.githubusercontent.com/NikoDi2000/test-craftsman/main/install.sh | bash -s -- --all

# 只安装对抗性 TDD
curl -sSL https://raw.githubusercontent.com/NikoDi2000/test-craftsman/main/install.sh | bash -s -- --atdd

# 只安装 API 集成测试
curl -sSL https://raw.githubusercontent.com/NikoDi2000/test-craftsman/main/install.sh | bash -s -- --api

# 组合安装
curl -sSL https://raw.githubusercontent.com/NikoDi2000/test-craftsman/main/install.sh | bash -s -- --atdd --api

# 指定目标目录
curl -sSL https://raw.githubusercontent.com/NikoDi2000/test-craftsman/main/install.sh | bash -s -- --all --dir /path/to/project
```

安装脚本会：
1. 临时 clone 仓库到 `/tmp`
2. 将 Agent 复制到 `.opencode/agents/`
3. 将 Skill 复制到 `.opencode/skills/`
4. 将规则复制到 `.opencode/rules/`
5. 生成 `opencode.json` 配置
6. 复制 `.AGENTS.md` 全局身份
7. 清理临时文件

**安装完成后不需要保留源仓库**，所有文件已复制到 `.opencode/` 目录。

## 方式三：手动安装

参考 [Claude Command Suite](https://github.com/spacescapes/Claude-Command-Suite) 和 [cursorrules](https://github.com/ivangrynenko/cursorrules) 的手动安装模式。

```bash
# 1. 临时 clone
git clone --depth 1 https://github.com/NikoDi2000/test-craftsman /tmp/test-craftsman

# 2. 安装 Agent
mkdir -p .opencode/agents
cp /tmp/test-craftsman/agents/*.md .opencode/agents/

# 3. 安装 Skill
mkdir -p .opencode/skills
cp -r /tmp/test-craftsman/adversarial-tdd .opencode/skills/
cp -r /tmp/test-craftsman/property-based-testing .opencode/skills/
cp -r /tmp/test-craftsman/api-integration-testing .opencode/skills/

# 4. 安装规则
mkdir -p .opencode/rules
cp /tmp/test-craftsman/adversarial-tdd/assets/全局规则模板.md .opencode/rules/测试有效性规则.md
cp /tmp/test-craftsman/api-integration-testing/assets/全局规则模板.md .opencode/rules/API集成测试规则.md

# 5. 配置全局身份
cp /tmp/test-craftsman/AGENTS.md .AGENTS.md

# 6. 清理
rm -rf /tmp/test-craftsman
```

然后手动创建 `opencode.json`（见上方配置）。

### 符号链接方式（开发用）

参考 [claude-commands](https://github.com/claude-commands) 的 symlink 模式，适合需要频繁更新的场景：

```bash
# clone 到固定位置
git clone https://github.com/NikoDi2000/test-craftsman ~/projects/test-craftsman

# 在项目中创建符号链接
ln -s ~/projects/test-craftsman/agents .opencode/agents
ln -s ~/projects/test-craftsman/adversarial-tdd .opencode/skills/adversarial-tdd
ln -s ~/projects/test-craftsman/property-based-testing .opencode/skills/property-based-testing
ln -s ~/projects/test-craftsman/api-integration-testing .opencode/skills/api-integration-testing
ln -s ~/projects/test-craftsman/AGENTS.md .AGENTS.md
```

更新时只需 `cd ~/projects/test-craftsman && git pull`。

## 更新

| 安装方式 | 更新方法 |
|---------|---------|
| Plugin | 重启 OpenCode 自动拉取最新版本；如未更新，清除 plugin 缓存后重启 |
| 安装脚本 | 重新运行安装脚本即可覆盖更新 |
| 符号链接 | `cd ~/projects/test-craftsman && git pull` |
| 手动安装 | 重新执行手动安装步骤 |

## 安装后验证

启动 OpenCode 后，尝试以下命令：

```
请用对抗性TDD帮我实现一个用户注册功能
```

```
请用属性驱动测试验证我的排序函数
```

```
请为我的 FastAPI 用户端点写集成测试
```

## 项目结构

安装完成后的结构：

```
你的项目/
├── opencode.json
├── .AGENTS.md
└── .opencode/
    ├── agents/
    │   ├── 测试设计师.md
    │   ├── 实现者.md
    │   ├── 测试审计员.md
    │   └── 集成测试工程师.md
    ├── skills/
    │   ├── adversarial-tdd/
    │   │   ├── SKILL.md
    │   │   ├── assets/
    │   │   └── references/
    │   ├── property-based-testing/
    │   │   ├── SKILL.md
    │   │   ├── assets/
    │   │   └── references/
    │   └── api-integration-testing/
    │       ├── SKILL.md
    │       ├── assets/
    │       └── references/
    └── rules/
        ├── 测试有效性规则.md
        └── API集成测试规则.md
```

## 故障排查

| 问题 | 解决 |
|------|------|
| Plugin 未加载 | 检查 `opencode.json` 中 `plugin` 字段格式；尝试 `opencode run --print-logs "hello" 2>&1 \| grep -i test-craftsman` |
| Agent 未触发 | 检查 `opencode.json` 中 `agent.build.permission.task` 是否包含对应 Agent |
| Skill 未加载 | 确认 `.opencode/skills/*/SKILL.md` 存在且包含 `name` 和 `description` frontmatter |
| 规则未生效 | 确认 `.opencode/rules/` 和 `.AGENTS.md` 存在 |
| 测试直接通过 | 确认测试在实现前确实失败（红灯检查） |
| Windows 安装问题 | 参考 [Superpowers 故障排查](https://github.com/obra/superpowers/blob/main/docs/README.opencode.md)，使用 npm 本地安装后指向本地路径 |

## 遵循的标准

本项目遵循 [Agent Skills Specification](https://agentskills.io/)（由 Anthropic 推动的开放标准）：

- 每个 Skill 目录包含 `SKILL.md`，带有 `name` 和 `description` YAML frontmatter
- 支持渐进式加载：发现（name/description）→ 激活（完整指令）→ 执行（引用资源）
- 兼容所有支持 Agent Skills 的客户端（Claude Code、OpenCode、Cursor 等）
