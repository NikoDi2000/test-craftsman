#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/NikoDi2000/test-craftsman"
TMPDIR=""
TARGET="."

cleanup() {
  if [[ -n "$TMPDIR" ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

echo "🔧 安装 test-craftsman 质量工程师体系..."
echo ""

SKILLS=()
AGENTS=()
RULES=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --all)
      SKILLS=("adversarial-tdd" "property-based-testing" "api-integration-testing")
      AGENTS=("测试设计师" "实现者" "测试审计员" "集成测试工程师")
      RULES=("测试有效性规则" "API集成测试规则")
      shift
      ;;
    --atdd)
      SKILLS+=("adversarial-tdd")
      AGENTS+=("测试设计师" "实现者" "测试审计员")
      RULES+=("测试有效性规则")
      shift
      ;;
    --pbt)
      SKILLS+=("property-based-testing")
      AGENTS+=("测试设计师")
      shift
      ;;
    --api)
      SKILLS+=("api-integration-testing")
      AGENTS+=("测试设计师" "集成测试工程师" "测试审计员")
      RULES+=("API集成测试规则")
      shift
      ;;
    --dir)
      if [[ $# -lt 2 ]]; then
        echo "错误: --dir 需要一个目录参数"
        exit 1
      fi
      TARGET="$2"
      shift 2
      ;;
    *)
      echo "未知参数: $1"
      echo "用法: install.sh [--all|--atdd|--pbt|--api] [--dir <path>]"
      exit 1
      ;;
  esac
done

if [[ ${#SKILLS[@]} -eq 0 ]]; then
  echo "请选择要安装的 Skill："
  echo "  --all    安装全部（ATDD + PBT + API 集成测试）"
  echo "  --atdd   对抗性 TDD"
  echo "  --pbt    属性驱动测试"
  echo "  --api    API 集成测试"
  echo ""
  echo "可以组合使用，如：--atdd --api"
  echo "可以用 --dir 指定目标目录，默认为当前目录"
  exit 1
fi

if ! command -v git &>/dev/null; then
  echo "错误: 需要 git，请先安装 git"
  exit 1
fi

TMPDIR=$(mktemp -d)
echo "📥 克隆仓库..."
git clone --depth 1 "$REPO" "$TMPDIR/repo" 2>/dev/null

mkdir -p "$TARGET/.opencode/agents"
mkdir -p "$TARGET/.opencode/skills"
mkdir -p "$TARGET/.opencode/rules"

UNIQUE_AGENTS=()
declare -A SEEN_AGENTS
for agent in "${AGENTS[@]}"; do
  if [[ -z "${SEEN_AGENTS[$agent]+x}" ]]; then
    UNIQUE_AGENTS+=("$agent")
    SEEN_AGENTS[$agent]=1
  fi
done

echo ""
echo "📦 安装 Agent..."
for agent in "${UNIQUE_AGENTS[@]}"; do
  src="$TMPDIR/repo/agents/${agent}.md"
  dst="$TARGET/.opencode/agents/${agent}.md"
  if [[ -f "$src" ]]; then
    cp "$src" "$dst"
    echo "  ✅ ${agent}"
  else
    echo "  ⚠️  未找到: ${agent}.md"
  fi
done

echo ""
echo "📦 安装 Skill..."
for skill in "${SKILLS[@]}"; do
  src="$TMPDIR/repo/${skill}"
  dst="$TARGET/.opencode/skills/${skill}"
  if [[ -d "$src" ]]; then
    cp -r "$src" "$dst"
    echo "  ✅ ${skill}"
  else
    echo "  ⚠️  未找到: ${skill}"
  fi
done

echo ""
echo "📦 安装规则..."
for rule in "${RULES[@]}"; do
  case $rule in
    "测试有效性规则")
      src="$TMPDIR/repo/adversarial-tdd/assets/全局规则模板.md"
      ;;
    "API集成测试规则")
      src="$TMPDIR/repo/api-integration-testing/assets/全局规则模板.md"
      ;;
  esac
  dst="$TARGET/.opencode/rules/${rule}.md"
  if [[ -f "$src" ]]; then
    cp "$src" "$dst"
    echo "  ✅ ${rule}"
  fi
done

echo ""
echo "📝 配置 opencode.json..."

AGENT_JSON=""
for i in "${!UNIQUE_AGENTS[@]}"; do
  agent="${UNIQUE_AGENTS[$i]}"
  if [[ $i -gt 0 ]]; then
    AGENT_JSON+=","
  fi
  AGENT_JSON+=$'\n'"          \"${agent}\": \"allow\""
done

if [[ -f "$TARGET/opencode.json" ]]; then
  echo "  ⚠️  opencode.json 已存在，请手动添加以下配置："
  echo ""
  echo '  {'
  echo '    "agent": {'
  echo '      "build": {'
  echo '        "permission": {'
  echo '          "task": {'
  for agent in "${UNIQUE_AGENTS[@]}"; do
    echo "            \"${agent}\": \"allow\","
  done
  echo '          }'
  echo '        }'
  echo '      }'
  echo '    }'
  echo '  }'
else
  cat > "$TARGET/opencode.json" << EOF
{
  "agent": {
    "build": {
      "permission": {
        "task": {${AGENT_JSON}
        }
      }
    }
  }
}
EOF
  echo "  ✅ 已创建 opencode.json"
fi

echo ""
echo "📝 配置全局身份..."
if [[ ! -f "$TARGET/.AGENTS.md" ]]; then
  cp "$TMPDIR/repo/AGENTS.md" "$TARGET/.AGENTS.md"
  echo "  ✅ 已创建 .AGENTS.md"
else
  echo "  ⚠️  .AGENTS.md 已存在，跳过"
fi

echo ""
echo "✨ 安装完成！"
echo ""
echo "安装内容："
echo "  Agent: ${UNIQUE_AGENTS[*]}"
echo "  Skill: ${SKILLS[*]}"
echo "  规则: ${RULES[*]}"
echo ""
echo "请重启 OpenCode 使配置生效。"
