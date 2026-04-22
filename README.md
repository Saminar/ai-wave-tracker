# ai-wave-tracker

AI浪潮产业链股票追踪与分析 Skill。

自动获取港股 / A股 / 美股三大市场 35+ 家核心 AI 产业链公司（AI GPU / 光模块 / AI 服务器 / 云平台 / 先进代工）的实时行情与新闻催化剂，生成带买卖建议的暗色主题可视化 HTML 报告，并同步到 GitHub 知识库统一管理。

**触发词：** AI浪潮、AI产业链、AI芯片分析、GPU产业链、光模块分析、AI服务器、港股AI、国产替代、DeepSeek影响。

## 目录结构

```
ai-wave-tracker/
├── SKILL.md                    # Skill 主说明（AI 会读取此文件执行）
├── references/
│   └── companies.json          # 62 家产业链公司结构化数据（含分级/目标涨幅/信号）
└── scripts/
    ├── fetch_stock_data.py     # 拉取实时行情（腾讯财经 API，覆盖港/A/美三市场）
    ├── fetch_news_analysis.py  # 获取 A 股新闻（AKShare）+ 构建投资主题
    ├── generate_report.sh      # 生成暗色主题可视化 HTML 报告（7 Tab + 11 ECharts）
    └── sync_report.sh          # 同步报告到 GitHub knowledge-base 知识库
```

## 安装方式

### Claude Code

```bash
git clone git@github.com:Saminar/ai-wave-tracker.git ~/.claude/skills/ai-wave-tracker
```

### Gemini CLI

```bash
git clone git@github.com:Saminar/ai-wave-tracker.git ~/.gemini/skills/ai-wave-tracker
```

### WorkBuddy

```bash
git clone git@github.com:Saminar/ai-wave-tracker.git ~/.workbuddy/skills/ai-wave-tracker
```

> 若为私有仓库，需要先配置 SSH key 或 GitHub Personal Access Token。

## 使用要求

- **Python 3**：需安装 `requests` 和 `akshare`（`pip3 install requests akshare`）
- **Bash**：脚本通过 shell 编排
- **网络**：可访问腾讯财经 API（实时行情）和 AKShare（A 股新闻）
- **可选：** 使用 `sync_report.sh` 需要访问 `Saminar/knowledge-base` 仓库（可在脚本中改为自己的知识库路径）

## 使用方式

安装后直接对 AI 说触发词即可，例如：

- "AI浪潮产业链今日行情"
- "生成 AI 产业链分析报告"
- "港股 AI 芯片板块分析"
- "DeepSeek 对国产算力的影响"

AI 会自动读取 SKILL.md 并按 5 步流程执行。

## 分析框架

### 四象限产业透视法

| 象限 | 领域 | 代表标的 |
|------|------|---------|
| 一 | 算力底座（AI GPU / ASIC / 先进代工 / HBM） | NVDA、中芯国际、寒武纪、澜起科技 |
| 二 | 数据通路（光模块 / 交换机 / 网络互联） | 中际旭创、天孚通信、新易盛、MRVL |
| 三 | 算法平台（云厂商 / 大模型 / 国产替代生态） | 阿里巴巴、腾讯、百度、天数智芯 |
| 四 | 应用落地（AI Server / AI PC / AI Phone / 边缘推理） | 联想集团、浪潮信息、工业富联、小米 |

### 五维投资评估框架

| 维度 | 权重 | 说明 |
|------|------|------|
| 技术壁垒 | 40% | 核心技术护城河深度 |
| 市场地位 | — | 行业排名与份额 |
| AI 受益度 | — | 与 AI 浪潮直接相关程度 |
| 政策顺风 | — | 国产替代 / 大基金等政策加持 |
| 估值安全边际 | — | PE/PB 相对历史低位程度 |

### 港股核心推荐速览

| 等级 | 代码 | 名称 | 目标弹性 | 核心逻辑 |
|------|------|------|---------|---------|
| 🥇一线 | 00981 | 中芯国际 | +40% | 18A量产 + 大基金 + 国产替代 |
| 🥇一线 | 09988 | 阿里巴巴 | +85% | 云AI变现 + 严重低估 + 回购 |
| 🥇一线 | 00992 | 联想集团 | +30% | PE 8x + AI服务器 + AI PC |
| 🥈二线 | 09903 | 天数智芯 | +50% | 国产AI GPU + DeepSeek生态 |
| 🥈二线 | 06809 | 澜起科技H | +45% | HBM接口超级周期 |
| 🥈二线 | 09888 | 百度集团 | +35% | 文心API + 萝卜快跑商业化 |
| ⚠️回避 | 00020 | 商汤科技 | N/A | 持续亏损，高估值 |
| ⚠️回避 | 06060 | 旷视科技 | N/A | 亏损，竞争格局恶化 |

## 报告示例

生成的 HTML 报告包含：
- **7 个 Tab**：市场总览 / 港股分析 / A 股分析 / 美股分析 / 产业链图谱 / 投资组合 / 新闻催化
- **11+ ECharts 图表**：五维雷达图、目标涨幅条形图、估值气泡图、PE 分布、信号热力图、Sankey 产业链图、Treemap 板块权重等
- **实时数据驱动**：行情数据由腾讯财经 API 实时获取，新闻由 AKShare 抓取
