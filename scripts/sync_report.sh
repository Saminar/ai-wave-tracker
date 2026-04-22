#!/bin/bash
# ============================================================
# AI浪潮产业链 — GitHub knowledge-base 同步器
# 用法: bash sync_report.sh <report_html> [report_date]
#
# 同步到: Saminar/knowledge-base/docs/investment/
# ============================================================

set -e

REPORT_HTML="$1"
REPORT_DATE="${2:-$(date +%Y-%m-%d)}"
KB_DIR="/Users/yangyangfan/WorkBuddy/20260413095620/knowledge-base"
INVEST_DIR="$KB_DIR/docs/investment"

if [ -z "$REPORT_HTML" ]; then
    echo "❌ 用法: bash sync_report.sh <report.html> [YYYY-MM-DD]"
    echo "   示例: bash sync_report.sh /tmp/aiwave_report_2026-04-22.html 2026-04-22"
    exit 1
fi

if [ ! -f "$REPORT_HTML" ]; then
    echo "❌ 报告文件不存在: $REPORT_HTML"
    exit 1
fi

REPORT_SIZE=$(wc -c < "$REPORT_HTML")
if [ "$REPORT_SIZE" -lt 1024 ]; then
    echo "❌ 报告文件过小（$REPORT_SIZE bytes），可能生成失败"
    exit 1
fi

echo "🌊 AI浪潮产业链报告 — 同步到 GitHub knowledge-base"
echo "  报告文件: $REPORT_HTML ($REPORT_SIZE bytes)"
echo "  报告日期: $REPORT_DATE"
echo "  目标目录: $INVEST_DIR"
echo ""

# 1. 确保目录存在
mkdir -p "$INVEST_DIR"

# 2. 复制报告
DEST_FILE="$INVEST_DIR/aiwave_report_${REPORT_DATE}.html"
cp "$REPORT_HTML" "$DEST_FILE"
echo "  ✅ 已复制到: $DEST_FILE"

# 3. 创建/更新 latest 软链接
ln -sf "aiwave_report_${REPORT_DATE}.html" "$INVEST_DIR/aiwave_report_latest.html"
echo "  ✅ 已更新 latest 链接"

# 4. 更新 AI浪潮 索引文件
INDEX_FILE="$INVEST_DIR/aiwave_index.md"
cat > "$INDEX_FILE" << MDEOF
# 🌊 AI浪潮产业链投资研究

AI芯片/GPU/光模块/AI服务器产业链追踪分析报告合集。
覆盖A股、港股、美股三大市场60+家核心标的。

## 分析框架

### 四象限产业透视法
- 象限一：算力底座（AI GPU/ASIC/先进代工/HBM）
- 象限二：数据通路（光模块/交换机/网络）
- 象限三：算法平台（云厂/大模型/国产替代生态）
- 象限四：应用落地（AI Server/AI PC/AI Phone/边缘推理）

### 五维投资评估框架
1. 技术壁垒 | 2. 市场地位 | 3. AI受益度 | 4. 政策顺风 | 5. 估值安全边际

## 最新报告

- [最新AI产业链报告](./aiwave_report_latest.html) — 自动更新 ($REPORT_DATE)

## 港股重点推荐

| 等级 | 代码 | 名称 | 目标弹性 | 逻辑 |
|------|------|------|---------|------|
| 🥇一线 | 00981 | 中芯国际 | +40% | 18A量产+大基金+国产替代 |
| 🥇一线 | 09988 | 阿里巴巴 | +85% | 云AI变现+严重低估+回购 |
| 🥇一线 | 00992 | 联想集团 | +30% | PE 8x+AI服务器+AI PC |
| 🥈二线 | 09903 | 天数智芯 | +50% | 国产AI GPU+DeepSeek生态 |
| 🥈二线 | 06809 | 澜起科技H | +45% | HBM接口超级周期 |
| 🥈二线 | 09888 | 百度集团 | +35% | 文心API+萝卜快跑商业化 |
| ⚠️回避 | 00020 | 商汤科技 | N/A | 持续亏损，高估值 |
| ⚠️回避 | 06060 | 旷视科技 | N/A | 亏损，竞争格局恶化 |

## 历史报告

MDEOF

# 列出所有历史报告（倒序）
for f in $(ls -r "$INVEST_DIR"/aiwave_report_2*.html 2>/dev/null); do
    fname=$(basename "$f")
    rdate=$(echo "$fname" | sed 's/aiwave_report_//;s/.html//')
    fsize=$(du -sh "$f" | cut -f1)
    echo "- [$rdate AI浪潮产业链报告](./$fname) — $fsize" >> "$INDEX_FILE"
done

echo "  ✅ 已更新 aiwave_index.md"

# 5. 更新总 investment index
MAIN_INDEX="$INVEST_DIR/index.md"
cat > "$MAIN_INDEX" << MDEOF2
# 📊 投资研究报告库

自动生成的产业链追踪与投资分析报告。

## 报告系列

| 系列 | 最新报告 | 说明 |
|------|---------|------|
| 🌊 AI浪潮产业链 | [最新](./aiwave_report_latest.html) | AI芯片/GPU/光模块/AI服务器全产业链 |
| 🔋 宁德时代产业链 | [最新](./catl_report_latest.html) | 动力电池上下游全产业链 |
| 🟢 英伟达产业链 | [最新](./nvda_report_latest.html) | NVDA上下游30+核心标的 |

## 快速索引

- [AI浪潮产业链报告索引](./aiwave_index.md)

MDEOF2

echo "  ✅ 已更新主 index.md"

# 6. Git commit & push
cd "$KB_DIR"
if [ -d ".git" ] || [ -f ".git" ] || git rev-parse --git-dir > /dev/null 2>&1; then
    git add docs/investment/

    if git diff --cached --quiet; then
        echo "  ℹ️ 无新变更需要提交"
    else
        git commit -m "🌊 AI浪潮产业链日报 $REPORT_DATE" \
            -m "自动同步：AI芯片/GPU/光模块/AI服务器产业链追踪报告"

        if git remote | grep -q origin; then
            echo "  📤 推送到 GitHub..."
            git push origin main 2>/dev/null || \
            git push origin master 2>/dev/null || \
            echo "  ⚠️ push 失败，请手动推送: cd $KB_DIR && git push"
        fi
        echo "  ✅ Git commit & push 完成"
    fi
else
    echo "  ⚠️ $KB_DIR 不是 git 仓库，仅完成文件复制"
fi

echo ""
echo "✅ GitHub knowledge-base 同步完成！"
echo ""
echo "📂 报告路径: $DEST_FILE"
echo "🔗 GitHub: https://github.com/Saminar/knowledge-base/tree/main/docs/investment/"
