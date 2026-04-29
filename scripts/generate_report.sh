#!/bin/bash
# ============================================================
# AI浪潮产业链 — HTML可视化报告生成器
# 用法: bash generate_report.sh <stock.json> <news.json> <analysis.json> [output_dir]
#
# 生成暗色主题、多Tab、ECharts多图表的单文件HTML投资仪表盘
# ============================================================

set -e

STOCK_JSON="${1:-/tmp/aiwave_stock.json}"
NEWS_JSON="${2:-/tmp/aiwave_news.json}"
ANALYSIS_JSON="${3:-/tmp/aiwave_analysis.json}"
OUTPUT_DIR="${4:-/tmp}"
REPORT_DATE=$(date +%Y-%m-%d)
OUTPUT_FILE="$OUTPUT_DIR/aiwave_report_${REPORT_DATE}.html"

echo "🌊 AI浪潮产业链 — HTML报告生成器"
echo "  行情数据: $STOCK_JSON"
echo "  新闻数据: $NEWS_JSON"
echo "  分析数据: $ANALYSIS_JSON"
echo "  输出报告: $OUTPUT_FILE"
echo ""

# ─── 读取JSON数据 ─────────────────────────────────────────────────────────────
STOCK_DATA="{}"
NEWS_DATA="{}"
ANALYSIS_DATA="{}"

[ -f "$STOCK_JSON" ] && STOCK_DATA=$(cat "$STOCK_JSON")
[ -f "$NEWS_JSON" ] && NEWS_DATA=$(cat "$NEWS_JSON")
[ -f "$ANALYSIS_JSON" ] && ANALYSIS_DATA=$(cat "$ANALYSIS_JSON")

# ─── 生成HTML报告 ─────────────────────────────────────────────────────────────
python3 - "$OUTPUT_FILE" "$REPORT_DATE" "$ANALYSIS_JSON" << 'PYEOF'
import sys
import json
from pathlib import Path

output_path = sys.argv[1]
report_date = sys.argv[2]
analysis_json_path = sys.argv[3] if len(sys.argv) > 3 else '/tmp/aiwave_analysis.json'

# 读取 analysis.json，提取港股推荐数据用于图表注入
try:
    with open(analysis_json_path, 'r', encoding='utf-8') as f:
        analysis = json.load(f)
    hk_recs = analysis.get('hk_recommendations', [])
except Exception:
    hk_recs = []

# ── 从 hk_recs 构建三个图表的数据 ──
# 过滤掉 sell 信号且无目标价的标的（如商汤）
chart_recs = [r for r in hk_recs if r.get('upside_pct') is not None]

# 评分归一化辅助函数：将 0-100 或 0-10 的评分统一到 0-10 量纲
def norm_score(v, default=7):
    """将评分归一化到 0-10 量纲，兼容 0-100 和 0-10 两种输入。"""
    if v is None:
        return default
    return round(v / 10.0, 1) if v > 10 else float(v)

# 雷达图：取前5个（tier1+tier2 中 buy/accumulate）
radar_recs = [r for r in chart_recs if r.get('signal') in ('buy','accumulate')][:5]
radar_names = json.dumps([r['name'] for r in radar_recs], ensure_ascii=False)
radar_colors = ['#38bdf8','#fbbf24','#34d399','#a78bfa','#fb923c']
radar_series_js = ''
for idx, r in enumerate(radar_recs):
    sc = r.get('scores', {})
    vals = [
        norm_score(sc.get('tech_moat')),
        norm_score(sc.get('market_position')),
        norm_score(sc.get('ai_exposure')),
        norm_score(sc.get('policy_tailwind')),
        norm_score(sc.get('valuation_safety')),
    ]
    col = radar_colors[idx % len(radar_colors)]
    radar_series_js += f'''        {{ value: {vals}, name: '{r['name']}',
          areaStyle: {{ color: '{col}33' }},
          lineStyle: {{ color: '{col}' }}, itemStyle: {{ color: '{col}' }} }},\n'''

# 弹性柱状图：所有 chart_recs 按 upside_pct 升序
sorted_recs = sorted(chart_recs, key=lambda r: r.get('upside_pct', 0))
upside_names = json.dumps([r['name'] for r in sorted_recs], ensure_ascii=False)
upside_vals  = json.dumps([round(r.get('upside_pct', 0), 1) for r in sorted_recs])

# 气泡图：风险 = 100 - valuation_safety；收益 = upside_pct；信心 = (tech_moat+ai_exposure)/2
bubble_data_js = ''
signal_map = {'buy':'买入','accumulate':'积累','hold':'持有','sell':'回避'}
for r in chart_recs:
    sc = r.get('scores', {})
    # 风险度：估值安全(反向)线性映射到 25-75，+market_position 微扰避免重叠
    # val_safety(0-10): 4→75, 5→63, 6→52, 7→40, 8→29, 9→17  (range ~17-75)
    val_safety = norm_score(sc.get('valuation_safety'))
    mkt_pos    = norm_score(sc.get('market_position'))
    base_risk  = round((10 - val_safety) / 6 * 56 + 19)
    risk = min(90, max(10, round(base_risk + (mkt_pos - 7) * 1.5)))
    ret  = round(r.get('upside_pct', 0), 1)
    conf = round((norm_score(sc.get('tech_moat')) + norm_score(sc.get('ai_exposure'))) / 2)
    sig  = signal_map.get(r.get('signal','hold'), r.get('signal','持有'))
    bubble_data_js += f"    [{risk}, {ret}, {conf}, '{r['name']}', '{sig}'],\n"
# 追加 sell 标的
for r in hk_recs:
    if r.get('signal') == 'sell':
        sc = r.get('scores', {})
        val_safety = norm_score(sc.get('valuation_safety'))
        mkt_pos    = norm_score(sc.get('market_position'))
        base_risk  = round((10 - val_safety) / 6 * 56 + 19)
        risk = min(90, max(10, round(base_risk + (mkt_pos - 7) * 1.5)))
        ret  = -15
        conf = round((norm_score(sc.get('tech_moat', 6)) + norm_score(sc.get('ai_exposure', 7))) / 2)
        bubble_data_js += f"    [{risk}, {ret}, {conf}, '{r['name']}', '回避'],\n"

# 这里生成一个完整的自包含HTML，数据直接内嵌

html = f'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>🌊 AI浪潮产业链投资仪表盘 · {report_date}</title>
<script src="https://cdn.tailwindcss.com"></script>
<script src="https://cdn.jsdelivr.net/npm/echarts@5/dist/echarts.min.js"></script>
<style>
  :root {{
    --bg: #0f172a;
    --card: #1e293b;
    --card2: #162032;
    --border: #334155;
    --text: #e2e8f0;
    --muted: #94a3b8;
    --accent: #38bdf8;
    --green: #34d399;
    --red: #f87171;
    --yellow: #fbbf24;
    --purple: #a78bfa;
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ background: var(--bg); color: var(--text); font-family: -apple-system, 'PingFang SC', sans-serif; min-height: 100vh; }}

  .header-bg {{
    background: linear-gradient(135deg, #0f172a 0%, #1e3a5f 50%, #0f172a 100%);
    position: relative; overflow: hidden;
    border-bottom: 1px solid var(--border);
    padding: 28px 32px 24px;
  }}
  .header-bg::before {{
    content: '';
    position: absolute; top: -80px; left: 20%; width: 400px; height: 400px;
    background: radial-gradient(circle, rgba(56,189,248,0.08) 0%, transparent 70%);
    pointer-events: none;
    
  }}
  .header-bg::after {{
    content: '';
    position: absolute; bottom: -60px; right: 10%; width: 300px; height: 300px;
    background: radial-gradient(circle, rgba(167,139,250,0.07) 0%, transparent 70%);
    pointer-events: none;
    
  }}

  .kpi-grid {{ display: grid; grid-template-columns: repeat(6, 1fr); gap: 12px; margin-top: 20px; }}
  @media (max-width: 1200px) {{ .kpi-grid {{ grid-template-columns: repeat(3, 1fr); }} }}
  @media (max-width: 640px) {{ .kpi-grid {{ grid-template-columns: repeat(2, 1fr); }} }}

  .kpi-card {{
    background: rgba(30,41,59,0.7); border: 1px solid var(--border);
    border-radius: 12px; padding: 14px 16px;
    backdrop-filter: blur(10px);
  }}
  .kpi-value {{ font-size: 22px; font-weight: 700; line-height: 1.2; }}
  .kpi-label {{ font-size: 11px; color: var(--muted); margin-top: 4px; }}
  .kpi-sub {{ font-size: 11px; margin-top: 2px; }}

  .tab-nav {{ position: relative; z-index: 10;
    display: flex; gap: 4px; padding: 12px 32px;
    background: var(--card2); border-bottom: 1px solid var(--border);
    overflow-x: auto;
  }}
  .tab-btn {{
    padding: 7px 18px; border-radius: 8px; font-size: 13px; font-weight: 500;
    border: none; cursor: pointer; white-space: nowrap;
    background: transparent; color: var(--muted);
    transition: all 0.2s;
  }}
  .tab-btn:hover {{ background: rgba(56,189,248,0.1); color: var(--accent); }}
  .tab-btn.active {{ background: rgba(56,189,248,0.15); color: var(--accent); border: 1px solid rgba(56,189,248,0.3); }}

  .tab-panel {{ display: none; padding: 24px 32px; }}
  .tab-panel.active {{ display: block; }}

  .card {{
    background: var(--card); border: 1px solid var(--border);
    border-radius: 12px; padding: 20px;
    margin-bottom: 16px;
  }}
  .card-title {{ font-size: 15px; font-weight: 600; color: var(--accent); margin-bottom: 16px; display: flex; align-items: center; gap: 8px; }}

  .grid-2 {{ display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }}
  @media (max-width: 900px) {{ .grid-2 {{ grid-template-columns: 1fr; }} }}
  .grid-3 {{ display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 16px; }}
  @media (max-width: 900px) {{ .grid-3 {{ grid-template-columns: 1fr; }} }}

  .badge {{
    display: inline-block; padding: 2px 8px; border-radius: 4px;
    font-size: 11px; font-weight: 600;
  }}
  .badge-buy {{ background: rgba(52,211,153,0.15); color: var(--green); border: 1px solid rgba(52,211,153,0.3); }}
  .badge-sell {{ background: rgba(248,113,113,0.15); color: var(--red); border: 1px solid rgba(248,113,113,0.3); }}
  .badge-hold {{ background: rgba(251,191,36,0.15); color: var(--yellow); border: 1px solid rgba(251,191,36,0.3); }}
  .badge-accum {{ background: rgba(56,189,248,0.15); color: var(--accent); border: 1px solid rgba(56,189,248,0.3); }}
  .badge-reduce {{ background: rgba(167,139,250,0.15); color: var(--purple); }}

  .up {{ color: var(--green); }}
  .down {{ color: var(--red); }}
  .neutral {{ color: var(--muted); }}

  table {{ width: 100%; border-collapse: collapse; font-size: 13px; }}
  th {{ text-align: left; padding: 10px 12px; color: var(--muted); font-weight: 500; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; border-bottom: 1px solid var(--border); }}
  td {{ padding: 10px 12px; border-bottom: 1px solid rgba(51,65,85,0.5); }}
  tr:last-child td {{ border-bottom: none; }}
  tr:hover td {{ background: rgba(56,189,248,0.03); }}

  .rec-card {{
    background: var(--card); border: 1px solid var(--border);
    border-radius: 12px; padding: 18px 20px;
    transition: transform 0.2s, border-color 0.2s;
    cursor: default;
  }}
  .rec-card:hover {{ transform: translateY(-2px); border-color: var(--accent); }}
  .rec-card.gold {{ border-left: 4px solid #f59e0b; }}
  .rec-card.silver {{ border-left: 4px solid #94a3b8; }}
  .rec-card.bronze {{ border-left: 4px solid #cd7c37; }}
  .rec-card.avoid {{ border-left: 4px solid var(--red); opacity: 0.8; }}

  .score-bar-bg {{ background: rgba(51,65,85,0.6); border-radius: 4px; height: 6px; overflow: hidden; }}
  .score-bar-fill {{ height: 100%; border-radius: 4px; background: linear-gradient(90deg, var(--accent), #818cf8); transition: width 0.8s ease; }}

  .theme-card {{
    background: var(--card2); border: 1px solid var(--border);
    border-radius: 10px; padding: 16px;
    margin-bottom: 12px;
  }}
  .theme-card:hover {{ border-color: rgba(56,189,248,0.4); }}

  ::-webkit-scrollbar {{ width: 6px; height: 6px; }}
  ::-webkit-scrollbar-track {{ background: var(--bg); }}
  ::-webkit-scrollbar-thumb {{ background: var(--border); border-radius: 3px; }}
  ::-webkit-scrollbar-thumb:hover {{ background: #475569; }}
</style>
</head>
<body>

<!-- ═══ HEADER ═══ -->
<div class="header-bg">
  <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px;">
    <div>
      <div style="display:flex;align-items:center;gap:10px;">
        <span style="font-size:28px;">🌊</span>
        <div>
          <h1 style="font-size:22px;font-weight:700;color:#e2e8f0;">AI浪潮产业链投资仪表盘</h1>
          <p style="font-size:13px;color:#94a3b8;margin-top:2px;">AI Chip · GPU · 光模块 · AI服务器 · 算力平台 | A股/港股/美股</p>
        </div>
      </div>
    </div>
    <div style="text-align:right;">
      <div style="font-size:20px;font-weight:700;color:#38bdf8;">{report_date}</div>
      <div style="font-size:11px;color:#64748b;margin-top:2px;">每日更新 · 仅供参考</div>
    </div>
  </div>

  <div class="kpi-grid">
    <div class="kpi-card">
      <div class="kpi-value" style="color:#38bdf8;">$726B</div>
      <div class="kpi-label">🌍 全球AI芯片市场</div>
      <div class="kpi-sub" style="color:#34d399;">2026E预测规模</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-value" style="color:#a78bfa;">$50B+</div>
      <div class="kpi-label">🔵 光模块市场规模</div>
      <div class="kpi-sub" style="color:#34d399;">800G/1.6T驱动</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-value" style="color:#fbbf24;">344亿</div>
      <div class="kpi-label">🇨🇳 大基金三期规模</div>
      <div class="kpi-sub" style="color:#94a3b8;">持续投资2025-27</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-value" style="color:#34d399;">+47%</div>
      <div class="kpi-label">📈 港股IT ETF YTD</div>
      <div class="kpi-sub" style="color:#94a3b8;">机构资金持续流入</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-value" style="color:#f97316;">85%+</div>
      <div class="kpi-label">⚙️ 中芯18A良率</div>
      <div class="kpi-sub" style="color:#34d399;">量产验证关键指标</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-value" style="color:#e879f9;">8x</div>
      <div class="kpi-label">💰 联想集团PE</div>
      <div class="kpi-sub" style="color:#34d399;">远低于行业20-30x</div>
    </div>
  </div>
</div>

<!-- ═══ TAB NAV ═══ -->
<div class="tab-nav">
  <button class="tab-btn active" onclick="switchTab('overview', this)">📊 总览</button>
  <button class="tab-btn" onclick="switchTab('hkstocks', this)">🇭🇰 港股推荐</button>
  <button class="tab-btn" onclick="switchTab('themes', this)">💡 投资主题</button>
  <button class="tab-btn" onclick="switchTab('supply', this)">🔗 产业链图谱</button>
  <button class="tab-btn" onclick="switchTab('ashare', this)">🇨🇳 A股标的</button>
  <button class="tab-btn" onclick="switchTab('usstocks', this)">🇺🇸 美股标的</button>
  <button class="tab-btn" onclick="switchTab('portfolio', this)">💼 组合策略</button>
</div>

<!-- ═══════════════════════════════════════════════════════════════
     TAB 1: 总览
════════════════════════════════════════════════════════════════ -->
<div id="tab-overview" class="tab-panel active">
  <div class="grid-2">
    <!-- 五维雷达 -->
    <div class="card">
      <div class="card-title">🎯 港股核心标的五维对比雷达</div>
      <div id="radarMain" style="width:100%;height:320px;"></div>
    </div>
    <!-- 目标价弹性 -->
    <div class="card">
      <div class="card-title">📈 港股主要标的目标价弹性（分析师一致预期）</div>
      <div id="upsideBar" style="width:100%;height:320px;"></div>
    </div>
  </div>

  <!-- 风险收益气泡图 -->
  <div class="card">
    <div class="card-title">🫧 港股AI标的 — 风险·收益·信心度气泡图</div>
    <div style="font-size:12px;color:var(--muted);margin-bottom:12px;">横轴=风险度，纵轴=预期收益，气泡大小=分析师信心度</div>
    <div id="bubbleChart" style="width:100%;height:380px;"></div>
  </div>
</div>

<!-- ═══════════════════════════════════════════════════════════════
     TAB 2: 港股推荐
════════════════════════════════════════════════════════════════ -->
<div id="tab-hkstocks" class="tab-panel">
  <div class="grid-2">
    <!-- PE对比 -->
    <div class="card">
      <div class="card-title">📊 港股AI标的PE估值对比</div>
      <div id="peChart" style="width:100%;height:300px;"></div>
    </div>
    <!-- 技术信号热力图 -->
    <div class="card">
      <div class="card-title">🌡️ 综合信号热力图（技术面×基本面×估值）</div>
      <div id="signalChart" style="width:100%;height:300px;"></div>
    </div>
  </div>

  <!-- 推荐卡片 -->
  <div class="card">
    <div class="card-title">⭐ 分级推荐标的</div>
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:14px;">

      <div class="rec-card gold">
        <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
          <div>
            <span style="font-size:16px;">🥇</span>
            <span style="font-weight:700;font-size:16px;color:#f59e0b;margin-left:6px;">中芯国际</span>
            <span style="color:var(--muted);font-size:12px;margin-left:6px;">00981.HK</span>
          </div>
          <span class="badge badge-buy">强烈买入</span>
        </div>
        <div style="font-size:22px;font-weight:700;color:var(--green);">+40% <span style="font-size:13px;color:var(--muted);">目标弹性</span></div>
        <div style="font-size:12px;color:var(--muted);margin:8px 0;">先进代工 | PE ~48x</div>
        <div style="font-size:13px;color:var(--text);line-height:1.6;">18A量产催化剂 + 大基金三期加持 + 国产替代核心受益，2026年最确定的算力基础设施投资标的</div>
        <div style="margin-top:12px;">
          <div style="font-size:11px;color:var(--muted);margin-bottom:4px;">五维综合评分</div>
          <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px;font-size:11px;">
            <div>技术壁垒 <span style="color:var(--green);">90</span></div>
            <div>AI受益度 <span style="color:var(--green);">95</span></div>
            <div>政策顺风 <span style="color:var(--green);">98</span></div>
          </div>
        </div>
        <div style="margin-top:10px;font-size:11px;color:var(--yellow);">⚡ 催化剂: Q2 18A量产验证 · 大客户流片</div>
      </div>

      <div class="rec-card gold">
        <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
          <div>
            <span style="font-size:16px;">🥇</span>
            <span style="font-weight:700;font-size:16px;color:#f59e0b;margin-left:6px;">阿里巴巴</span>
            <span style="color:var(--muted);font-size:12px;margin-left:6px;">09988.HK</span>
          </div>
          <span class="badge badge-buy">强烈买入</span>
        </div>
        <div style="font-size:22px;font-weight:700;color:var(--green);">+85% <span style="font-size:13px;color:var(--muted);">目标弹性</span></div>
        <div style="font-size:12px;color:var(--muted);margin:8px 0;">云/AI平台 | PE ~14x</div>
        <div style="font-size:13px;color:var(--text);line-height:1.6;">阿里云AI变现加速，通义大模型API调用量爆发，估值处历史极低位，大规模回购支撑</div>
        <div style="margin-top:10px;font-size:11px;color:var(--yellow);">⚡ 催化剂: AI云收入超预期 · 回购规模扩大</div>
      </div>

      <div class="rec-card gold">
        <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
          <div>
            <span style="font-size:16px;">🥇</span>
            <span style="font-weight:700;font-size:16px;color:#f59e0b;margin-left:6px;">联想集团</span>
            <span style="color:var(--muted);font-size:12px;margin-left:6px;">00992.HK</span>
          </div>
          <span class="badge badge-buy">强烈买入</span>
        </div>
        <div style="font-size:22px;font-weight:700;color:var(--green);">+30% <span style="font-size:13px;color:var(--muted);">目标弹性</span></div>
        <div style="font-size:12px;color:var(--muted);margin:8px 0;">AI服务器+AI PC | PE ~8x</div>
        <div style="font-size:13px;color:var(--text);line-height:1.6;">PE仅8x严重低估，$155B订单储备，AI PC换机超级周期+ISG AI服务器利润率改善</div>
        <div style="margin-top:10px;font-size:11px;color:var(--yellow);">⚡ 催化剂: ISG利润率超预期 · AI PC出货数据</div>
      </div>

      <div class="rec-card silver">
        <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
          <div>
            <span style="font-size:16px;">🥈</span>
            <span style="font-weight:700;font-size:16px;color:#94a3b8;margin-left:6px;">天数智芯</span>
            <span style="color:var(--muted);font-size:12px;margin-left:6px;">09903.HK</span>
          </div>
          <span class="badge badge-accum">逢低积累</span>
        </div>
        <div style="font-size:22px;font-weight:700;color:var(--green);">+50% <span style="font-size:13px;color:var(--muted);">目标弹性</span></div>
        <div style="font-size:12px;color:var(--muted);margin:8px 0;">国产AI GPU | 成长期</div>
        <div style="font-size:13px;color:var(--text);line-height:1.6;">国产AI训练GPU，DeepSeek生态适配受益，华为替代路线之外重要备选，高风险高弹性</div>
        <div style="margin-top:10px;font-size:11px;color:var(--yellow);">⚡ 催化剂: 大客户订单 · DeepSeek适配发布</div>
      </div>

      <div class="rec-card silver">
        <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
          <div>
            <span style="font-size:16px;">🥈</span>
            <span style="font-weight:700;font-size:16px;color:#94a3b8;margin-left:6px;">澜起科技H</span>
            <span style="color:var(--muted);font-size:12px;margin-left:6px;">06809.HK</span>
          </div>
          <span class="badge badge-buy">买入</span>
        </div>
        <div style="font-size:22px;font-weight:700;color:var(--green);">+45% <span style="font-size:13px;color:var(--muted);">目标弹性</span></div>
        <div style="font-size:12px;color:var(--muted);margin:8px 0;">HBM接口芯片 | PE ~28x</div>
        <div style="font-size:13px;color:var(--text);line-height:1.6;">DDR5/HBM接口芯片超级周期，8-12季度能见度极高，A股澜起科技H股折价提供安全边际</div>
        <div style="margin-top:10px;font-size:11px;color:var(--yellow);">⚡ 催化剂: HBM4接口量产 · AI服务器内存升级</div>
      </div>

      <div class="rec-card silver">
        <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
          <div>
            <span style="font-size:16px;">🥈</span>
            <span style="font-weight:700;font-size:16px;color:#94a3b8;margin-left:6px;">百度集团</span>
            <span style="color:var(--muted);font-size:12px;margin-left:6px;">09888.HK</span>
          </div>
          <span class="badge badge-accum">逢低积累</span>
        </div>
        <div style="font-size:22px;font-weight:700;color:var(--green);">+35% <span style="font-size:13px;color:var(--muted);">目标弹性</span></div>
        <div style="font-size:12px;color:var(--muted);margin:8px 0;">AI原生平台 | PE ~12x</div>
        <div style="font-size:13px;color:var(--text);line-height:1.6;">文心大模型API爆发，萝卜快跑L4自动驾驶商业化，估值处历史低位，困境反转逻辑</div>
        <div style="margin-top:10px;font-size:11px;color:var(--yellow);">⚡ 催化剂: 萝卜快跑城市扩张 · AI广告收入转正</div>
      </div>

      <div class="rec-card avoid">
        <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
          <div>
            <span style="font-size:16px;">⚠️</span>
            <span style="font-weight:700;font-size:16px;color:var(--red);margin-left:6px;">商汤科技</span>
            <span style="color:var(--muted);font-size:12px;margin-left:6px;">00020.HK</span>
          </div>
          <span class="badge badge-sell">回避</span>
        </div>
        <div style="font-size:13px;color:var(--text);line-height:1.6;">持续亏损，AI变现路径不清晰，估值虚高（PS>10x），短期无催化剂，优先回避</div>
      </div>

      <div class="rec-card avoid">
        <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
          <div>
            <span style="font-size:16px;">⚠️</span>
            <span style="font-weight:700;font-size:16px;color:var(--red);margin-left:6px;">旷视科技</span>
            <span style="color:var(--muted);font-size:12px;margin-left:6px;">06060.HK</span>
          </div>
          <span class="badge badge-sell">回避</span>
        </div>
        <div style="font-size:13px;color:var(--text);line-height:1.6;">计算机视觉竞争格局恶化，政府安防预算压缩，持续亏损，无近期反转催化剂</div>
      </div>
    </div>
  </div>
</div>

<!-- ═══════════════════════════════════════════════════════════════
     TAB 3: 投资主题
════════════════════════════════════════════════════════════════ -->
<div id="tab-themes" class="tab-panel">
  <div class="grid-2">
    <div>
      <div class="theme-card">
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
          <span style="font-size:20px;">⚙️</span>
          <div>
            <div style="font-weight:700;color:#e2e8f0;">中芯18A量产催化</div>
            <div style="font-size:13px;color:#fbbf24;margin-top:2px;">★★★★★ 最高优先级</div>
          </div>
        </div>
        <div style="font-size:13px;color:var(--muted);line-height:1.7;">18A工艺（1.8nm等效）量产在即，良率突破85%，首批大客户流片验证。大陆先进代工能力突破是2026年最重要的科技事件。</div>
        <div style="margin-top:10px;display:flex;flex-wrap:wrap;gap:6px;">
          <span style="font-size:11px;padding:3px 8px;background:rgba(52,211,153,0.1);color:#34d399;border-radius:4px;">00981 中芯国际 ↑</span>
          <span style="font-size:11px;padding:3px 8px;background:rgba(52,211,153,0.1);color:#34d399;border-radius:4px;">01347 华虹半导体 ↑</span>
        </div>
      </div>

      <div class="theme-card">
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
          <span style="font-size:20px;">🔵</span>
          <div>
            <div style="font-weight:700;color:#e2e8f0;">光模块 800G→1.6T 升级</div>
            <div style="font-size:13px;color:#fbbf24;margin-top:2px;">★★★★☆ 持续全年</div>
          </div>
        </div>
        <div style="font-size:13px;color:var(--muted);line-height:1.7;">全球AI数据中心扩容推动光模块需求爆发。800G大规模出货，1.6T进入量产准备，CPO技术商业化提速，A股光模块龙头是最直接受益者。</div>
        <div style="margin-top:10px;display:flex;flex-wrap:wrap;gap:6px;">
          <span style="font-size:11px;padding:3px 8px;background:rgba(56,189,248,0.1);color:#38bdf8;border-radius:4px;">300308 中际旭创</span>
          <span style="font-size:11px;padding:3px 8px;background:rgba(56,189,248,0.1);color:#38bdf8;border-radius:4px;">300394 天孚通信</span>
          <span style="font-size:11px;padding:3px 8px;background:rgba(56,189,248,0.1);color:#38bdf8;border-radius:4px;">300502 新易盛</span>
        </div>
      </div>

      <div class="theme-card">
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
          <span style="font-size:20px;">🤖</span>
          <div>
            <div style="font-weight:700;color:#e2e8f0;">DeepSeek × 国产算力爆发</div>
            <div style="font-size:13px;color:#fbbf24;margin-top:2px;">★★★★☆ 加速中</div>
          </div>
        </div>
        <div style="font-size:13px;color:var(--muted);line-height:1.7;">DeepSeek验证国产AI能力，Jevons悖论效应：效率提升→需求爆发→国产GPU/算力订单超预期。出口限制进一步加速国产替代。</div>
        <div style="margin-top:10px;display:flex;flex-wrap:wrap;gap:6px;">
          <span style="font-size:11px;padding:3px 8px;background:rgba(167,139,250,0.1);color:#a78bfa;border-radius:4px;">09903 天数智芯</span>
          <span style="font-size:11px;padding:3px 8px;background:rgba(167,139,250,0.1);color:#a78bfa;border-radius:4px;">688256 寒武纪</span>
          <span style="font-size:11px;padding:3px 8px;background:rgba(167,139,250,0.1);color:#a78bfa;border-radius:4px;">00981 中芯国际</span>
        </div>
      </div>
    </div>

    <div>
      <div class="theme-card">
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
          <span style="font-size:20px;">💻</span>
          <div>
            <div style="font-weight:700;color:#e2e8f0;">AI PC / AI Phone 换机超级周期</div>
            <div style="font-size:13px;color:#94a3b8;margin-top:2px;">★★★☆☆ H2 2026显现</div>
          </div>
        </div>
        <div style="font-size:13px;color:var(--muted);line-height:1.7;">搭载NPU本地推理的AI PC/手机普及，3-4年换机周期叠加AI功能驱动，PC出货量有望超预期反弹。</div>
        <div style="margin-top:10px;display:flex;flex-wrap:wrap;gap:6px;">
          <span style="font-size:11px;padding:3px 8px;background:rgba(249,115,22,0.1);color:#f97316;border-radius:4px;">00992 联想集团</span>
          <span style="font-size:11px;padding:3px 8px;background:rgba(249,115,22,0.1);color:#f97316;border-radius:4px;">01810 小米集团</span>
        </div>
      </div>

      <div class="theme-card">
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
          <span style="font-size:20px;">🏦</span>
          <div>
            <div style="font-weight:700;color:#e2e8f0;">大基金三期344亿加持</div>
            <div style="font-size:13px;color:#fbbf24;margin-top:2px;">★★★★☆ 2025-2027</div>
          </div>
        </div>
        <div style="font-size:13px;color:var(--muted);line-height:1.7;">国家集成电路产业投资基金三期持续投资先进代工、关键设备、核心材料，政策资金作为定海神针稳定估值。</div>
        <div style="margin-top:10px;display:flex;flex-wrap:wrap;gap:6px;">
          <span style="font-size:11px;padding:3px 8px;background:rgba(52,211,153,0.1);color:#34d399;border-radius:4px;">00981 中芯国际</span>
          <span style="font-size:11px;padding:3px 8px;background:rgba(52,211,153,0.1);color:#34d399;border-radius:4px;">A股半导体设备</span>
        </div>
      </div>

      <div class="theme-card">
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
          <span style="font-size:20px;">☁️</span>
          <div>
            <div style="font-weight:700;color:#e2e8f0;">云厂AI变现加速</div>
            <div style="font-size:13px;color:#94a3b8;margin-top:2px;">★★★☆☆ Q2起提速</div>
          </div>
        </div>
        <div style="font-size:13px;color:var(--muted);line-height:1.7;">阿里/腾讯/百度AI API调用量2026年同比增速预计超200%，大模型从ToB向ToC延伸，货币化率快速提升。</div>
        <div style="margin-top:10px;display:flex;flex-wrap:wrap;gap:6px;">
          <span style="font-size:11px;padding:3px 8px;background:rgba(251,191,36,0.1);color:#fbbf24;border-radius:4px;">09988 阿里巴巴</span>
          <span style="font-size:11px;padding:3px 8px;background:rgba(251,191,36,0.1);color:#fbbf24;border-radius:4px;">00700 腾讯控股</span>
          <span style="font-size:11px;padding:3px 8px;background:rgba(251,191,36,0.1);color:#fbbf24;border-radius:4px;">09888 百度集团</span>
        </div>
      </div>
      <div class="theme-card">
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
          <span style="font-size:20px;">⚡</span>
          <div>
            <div style="font-weight:700;color:#e2e8f0;">电力基建 — AI算力能源瓶颈</div>
            <div style="font-size:13px;color:#fbbf24;margin-top:2px;">★★★★☆ 2026-2028长线主题</div>
          </div>
        </div>
        <div style="font-size:13px;color:var(--muted);line-height:1.7;">AI数据中心电力需求2025-2030年CAGR超40%，核电PPA/储能BESS/智能电网成为算力基础设施新短板。核电+储能+特高压变压器是最直接受益链条。</div>
        <div style="margin-top:10px;display:flex;flex-wrap:wrap;gap:6px;">
          <span style="font-size:11px;padding:3px 8px;background:rgba(251,191,36,0.1);color:#fbbf24;border-radius:4px;">CEG Constellation</span>
          <span style="font-size:11px;padding:3px 8px;background:rgba(251,191,36,0.1);color:#fbbf24;border-radius:4px;">600406 国电南瑞</span>
          <span style="font-size:11px;padding:3px 8px;background:rgba(251,191,36,0.1);color:#fbbf24;border-radius:4px;">300750 宁德时代</span>
          <span style="font-size:11px;padding:3px 8px;background:rgba(251,191,36,0.1);color:#fbbf24;border-radius:4px;">600089 特变电工</span>
        </div>
      </div>
      </div>
    </div>
  </div>
</div>

<!-- ═══════════════════════════════════════════════════════════════
     TAB 4: 产业链图谱
════════════════════════════════════════════════════════════════ -->
<div id="tab-supply" class="tab-panel">
  <div class="card">
    <div class="card-title">🔗 AI算力产业链价值流向（桑基图）</div>
    <div id="sankeyChart" style="width:100%;height:420px;"></div>
  </div>
  <div class="card">
    <div class="card-title">🗺️ AI产业链板块分布（树状图）</div>
    <div id="treemapChart" style="width:100%;height:380px;"></div>
  </div>
</div>

<!-- ═══════════════════════════════════════════════════════════════
     TAB 5: A股标的
════════════════════════════════════════════════════════════════ -->
<div id="tab-ashare" class="tab-panel">
  <div class="card">
    <div class="card-title">🇨🇳 A股AI产业链核心标的</div>
    <div style="overflow-x:auto;">
      <table>
        <thead>
          <tr>
            <th>代码</th><th>公司</th><th>市场</th><th>板块</th><th>核心逻辑</th><th>关注信号</th>
          </tr>
        </thead>
        <tbody id="ashare-table-body"></tbody>
      </table>
    </div>
  </div>
</div>

<!-- ═══════════════════════════════════════════════════════════════
     TAB 6: 美股标的
════════════════════════════════════════════════════════════════ -->
<div id="tab-usstocks" class="tab-panel">
  <div class="grid-2">
    <div class="card">
      <div class="card-title">📊 美股AI核心公司市值对比</div>
      <div id="usMcapChart" style="width:100%;height:300px;"></div>
    </div>
    <div class="card">
      <div class="card-title">🥧 美股AI板块分布</div>
      <div id="usPieChart" style="width:100%;height:300px;"></div>
    </div>
  </div>
  <div class="card">
    <div class="card-title">🇺🇸 美股AI产业链核心标的</div>
    <div style="overflow-x:auto;">
      <table>
        <thead>
          <tr>
            <th>代码</th><th>公司</th><th>板块</th><th>市值(亿$)</th><th>核心竞争力</th><th>AI相关性</th>
          </tr>
        </thead>
        <tbody id="us-table-body"></tbody>
      </table>
    </div>
  </div>
</div>

<!-- ═══════════════════════════════════════════════════════════════
     TAB 7: 组合策略
════════════════════════════════════════════════════════════════ -->
<div id="tab-portfolio" class="tab-panel">
  <div class="grid-3">
    <div class="card">
      <div class="card-title">🛡️ 保守型组合</div>
      <div id="portfolioConserv" style="width:100%;height:220px;"></div>
      <div style="font-size:12px;color:var(--muted);margin-top:8px;text-align:center;">年化目标 +15-20%，最大回撤 ≤15%</div>
    </div>
    <div class="card">
      <div class="card-title">⚖️ 平衡型组合</div>
      <div id="portfolioBalance" style="width:100%;height:220px;"></div>
      <div style="font-size:12px;color:var(--muted);margin-top:8px;text-align:center;">年化目标 +25-35%，最大回撤 ≤25%</div>
    </div>
    <div class="card">
      <div class="card-title">🚀 进取型组合</div>
      <div id="portfolioAggress" style="width:100%;height:220px;"></div>
      <div style="font-size:12px;color:var(--muted);margin-top:8px;text-align:center;">年化目标 +40-60%，最大回撤 ≤40%</div>
    </div>
  </div>

  <!-- 风险矩阵 -->
  <div class="card">
    <div class="card-title">⚠️ 核心风险矩阵（概率 × 影响度）</div>
    <div id="riskMatrix" style="width:100%;height:340px;"></div>
  </div>

  <!-- 操作原则 -->
  <div class="card">
    <div class="card-title">📋 投资操作原则</div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;font-size:13px;">
      <div>
        <div style="color:var(--green);font-weight:600;margin-bottom:8px;">✅ 买入信号</div>
        <ul style="list-style:none;color:var(--muted);line-height:1.9;">
          <li>• 五维综合评分 ≥70分</li>
          <li>• 股价低于200日均线 + RSI &lt;40</li>
          <li>• 明确催化剂在3个月内落地</li>
          <li>• PE/PEG相对历史低位或行业折价</li>
          <li>• 量能放大同时价格创新高</li>
        </ul>
      </div>
      <div>
        <div style="color:var(--red);font-weight:600;margin-bottom:8px;">❌ 卖出/回避信号</div>
        <ul style="list-style:none;color:var(--muted);line-height:1.9;">
          <li>• 持续亏损 + 高估值（PS>10x）</li>
          <li>• 管理层业绩指引下调超15%</li>
          <li>• 核心产品ASP压缩 &gt;15% QoQ</li>
          <li>• 主要客户集中度过高且关系松动</li>
          <li>• RSI &gt;80 + 量能萎缩背离</li>
        </ul>
      </div>
    </div>
  </div>
</div>

<!-- ═══ 免责声明 ═══ -->
<div style="padding:16px 32px;text-align:center;font-size:11px;color:#475569;border-top:1px solid var(--border);">
  ⚠️ 本报告由 AI 自动生成，数据来自公开渠道，仅供学习研究参考，<strong>不构成任何投资建议</strong>。投资有风险，入市需谨慎。
  <br>生成时间: {report_date} | 🌊 AI浪潮产业链追踪 Skill
</div>

<script>
// ─── 数据 ──────────────────────────────────────────────────────────────────
const REPORT_DATE = '{report_date}';

const ashareData = [
  // ── AI芯片/算力 ──
  {{ code:"688256", name:"寒武纪", market:"科创板", sector:"AI推理芯片", logic:"国产AI推理芯片龙头，思元590系列，政府采购加速", signal:"watch" }},
  {{ code:"688041", name:"海光信息", market:"科创板", sector:"CPU/DCU", logic:"x86兼容DCU，数据中心加速场景，国产替代路线", signal:"hold" }},
  {{ code:"688047", name:"龙芯中科", market:"科创板", sector:"CPU", logic:"自主LoongArch ISA，党政军信创核心受益", signal:"hold" }},
  {{ code:"603828", name:"澜起科技", market:"上交所", sector:"HBM接口", logic:"DDR5/HBM接口芯片超级周期，A股核心AI硬件受益", signal:"buy" }},
  {{ code:"301269", name:"华大九天", market:"创业板", sector:"EDA", logic:"国产EDA唯一上市龙头，国家软件自主可控战略", signal:"buy" }},
  // ── 光模块/光器件 ──
  {{ code:"300308", name:"中际旭创", market:"创业板", sector:"光模块", logic:"800G/1.6T全球龙头，NVDA/Meta/MSFT核心供应商", signal:"buy" }},
  {{ code:"300394", name:"天孚通信", market:"创业板", sector:"光器件", logic:"FA组件/光器件上游，随光模块出货量弹性增长", signal:"buy" }},
  {{ code:"300502", name:"新易盛", market:"创业板", sector:"光模块", logic:"800G快速放量，1.6T技术储备完善", signal:"buy" }},
  {{ code:"000988", name:"华工科技", market:"深交所", sector:"激光/光模块", logic:"激光器+光模块多元化，汽车激光切割新增长极", signal:"hold" }},
  {{ code:"002281", name:"光迅科技", market:"深交所", sector:"光器件", logic:"中国信科旗下，光芯片自主化核心企业", signal:"hold" }},
  {{ code:"603083", name:"剑桥科技", market:"上交所", sector:"光模块/交换机", logic:"光模块+以太网交换机双主线，AI数据中心互连核心，800G出货加速，2026年高增长可期", signal:"buy" }},
  // ── AI服务器 ──
  {{ code:"000977", name:"浪潮信息", market:"深交所", sector:"AI服务器", logic:"国内AI服务器龙头，腾讯/阿里/百度核心供应商", signal:"buy" }},
  {{ code:"601138", name:"工业富联", market:"上交所", sector:"AI服务器ODM", logic:"全球AI服务器ODM前三，英伟达GPU服务器代工", signal:"buy" }},
  {{ code:"603019", name:"中科曙光", market:"上交所", sector:"高性能计算", logic:"高性能计算+AI服务器，政府/科研机构优先采购", signal:"hold" }},
  // ── 存储 ──
  {{ code:"603986", name:"兆易创新", market:"深交所", sector:"存储芯片", logic:"NOR Flash/DRAM国产龙头，AI端侧存储需求爆发受益", signal:"buy" }},
  {{ code:"300223", name:"北京君正", market:"创业板", sector:"存储芯片", logic:"DRAM+SRAM芯片，车载/工业+AI边缘计算受益", signal:"watch" }},
  // ── 半导体设备 ──
  {{ code:"002371", name:"北方华创", market:"深交所", sector:"半导体设备", logic:"刻蚀/PVD设备国产龙头，国内晶圆厂扩产核心受益", signal:"buy" }},
  {{ code:"688012", name:"中微公司", market:"科创板", sector:"半导体设备", logic:"等离子刻蚀设备，5nm制程突破，国产替代加速", signal:"buy" }},
  {{ code:"688072", name:"拓荆科技", market:"科创板", sector:"半导体设备", logic:"薄膜沉积PECVD/ALD设备，先进制程关键环节", signal:"watch" }},
  // ── 半导体材料 ──
  {{ code:"002318", name:"雅克科技", market:"深交所", sector:"半导体材料", logic:"半导体特气/前驱体材料，先进制程必需品", signal:"hold" }},
  {{ code:"688188", name:"南大光电", market:"科创板", sector:"半导体材料", logic:"光刻胶/电子特气，EUV光刻胶国产突破", signal:"buy" }},
  {{ code:"002106", name:"鼎龙股份", market:"深交所", sector:"半导体材料", logic:"CMP抛光垫国产替代龙头，晶圆制造关键耗材", signal:"hold" }},
  {{ code:"603989", name:"江化微", market:"上交所", sector:"半导体材料", logic:"超纯电子湿化学品，12寸晶圆线配套供应商", signal:"hold" }},
  // ── 先进封装 ──
  {{ code:"601986", name:"长电科技", market:"上交所", sector:"先进封装", logic:"全球封测前三，FCBGA/SiP高端封装受益AI算力需求", signal:"buy" }},
  {{ code:"002156", name:"通富微电", market:"深交所", sector:"先进封装", logic:"AMD/英伟达封测合作，Chiplet先进封装受益", signal:"buy" }},
  {{ code:"002185", name:"华天科技", market:"深交所", sector:"先进封装", logic:"车载+AI封测双轮驱动，Bumping/WLP产能扩张", signal:"hold" }},
  // ── 网络互连 ──
  {{ code:"301165", name:"锐捷网络", market:"创业板", sector:"网络互连", logic:"AI训练集群万兆/400G交换机，国内数据中心核心供应商", signal:"buy" }},
  // ── 电源/散热 ──
  {{ code:"002334", name:"英威腾", market:"深交所", sector:"电源/散热", logic:"数据中心UPS+储能逆变器，AI算力配套基础设施", signal:"hold" }},
  {{ code:"301018", name:"申菱环境", market:"创业板", sector:"电源/散热", logic:"液冷/精密空调，AI数据中心散热需求爆发受益", signal:"buy" }},
  // ── AI应用 ──
  {{ code:"002230", name:"科大讯飞", market:"深交所", sector:"AI应用", logic:"星火大模型龙头，教育/医疗/政务AI应用场景落地", signal:"hold" }},
  {{ code:"300418", name:"昆仑万维", market:"创业板", sector:"AI应用", logic:"天工大模型，AGI布局最激进A股标的之一", signal:"watch" }},
  // ── 电力基建（发电/输电/储电/用电） ──
  {{ code:"601985", name:"中国核电", market:"上交所", sector:"电力基建/发电", logic:"核电龙头，数据中心清洁能源供应，签约微软/谷歌等AI企业核电PPA合同趋势受益", signal:"accumulate" }},
  {{ code:"600900", name:"长江电力", market:"上交所", sector:"电力基建/发电", logic:"水电巨头，零碳稳定电力，AI数据中心偏好清洁能源PPA，股息率高安全边际足", signal:"accumulate" }},
  {{ code:"600406", name:"国电南瑞", market:"上交所", sector:"电力基建/输电", logic:"智能电网核心设备龙头，数字化电网+AI调度系统，国家电网直系受益方", signal:"buy" }},
  {{ code:"600089", name:"特变电工", market:"上交所", sector:"电力基建/输电", logic:"变压器全球龙头，国内外超高压变压器订单爆满，AI数据中心配套电力设施直接受益", signal:"buy" }},
  {{ code:"688676", name:"金盘科技", market:"科创板", sector:"电力基建/输电", logic:"固态变压器/数字能源管理设备，数据中心专用模块化变压器，新型电力系统受益", signal:"buy" }},
  {{ code:"002364", name:"中恒电气", market:"深交所", sector:"电力基建/输电", logic:"HVDC换流阀+直流断路器，大型数据中心直流供电改造，特高压输电核心设备", signal:"buy" }},
  {{ code:"300750", name:"宁德时代", market:"创业板", sector:"电力基建/储电", logic:"储能BESS全球龙头，AI数据中心UPS级大型储能系统，大型电网侧储能订单持续扩张", signal:"buy" }},
  {{ code:"300274", name:"阳光电源", market:"创业板", sector:"电力基建/储电", logic:"储能逆变器+光伏逆变器双龙头，大型储能电站系统集成全球前三，数据中心供电侧受益", signal:"accumulate" }},
  {{ code:"002335", name:"科华数据", market:"深交所", sector:"电力基建/用电", logic:"数据中心UPS+模块化机房，国内AI算力基础设施配套电源供应商", signal:"buy" }},
  {{ code:"002837", name:"英维克", market:"深交所", sector:"电力基建/用电", logic:"数据中心精密温控+液冷系统，AI服务器高热密度催生液冷爆发，订单高速增长", signal:"accumulate" }},
  {{ code:"600875", name:"东方电气", market:"上交所", sector:"电力基建/发电设备", logic:"核电/风电/水电发电设备制造龙头，核电站主要设备供应，清洁能源产能扩张受益", signal:"accumulate" }},
];

const usData = [
  // ── AI GPU/算力 ──
  {{ code:"NVDA", name:"英伟达", sector:"AI GPU", mcap:"30000", moat:"AI GPU垄断，CUDA生态护城河，Blackwell/Rubin路线图清晰", ai_rel:"★★★★★" }},
  {{ code:"AMD", name:"超微半导体", sector:"AI GPU", mcap:"2500", moat:"MI300X/MI350高性价比，ROCm生态追赶", ai_rel:"★★★★☆" }},
  {{ code:"AVGO", name:"博通", sector:"ASIC/网络", mcap:"8000", moat:"定制ASIC三大超级客户，AI网络芯片垄断", ai_rel:"★★★★★" }},
  {{ code:"MRVL", name:"迈威尔", sector:"光DSP/AI芯片", mcap:"550", moat:"光互联DSP+定制AI芯片，CPO核心使能者", ai_rel:"★★★★☆" }},
  {{ code:"COHR", name:"科锐", sector:"光组件", mcap:"150", moat:"激光器+CPO技术，数据中心光模块关键组件", ai_rel:"★★★★☆" }},
  {{ code:"SMCI", name:"超微电脑", sector:"AI服务器", mcap:"250", moat:"AI服务器快速上市能力，NVDA首选ODM合作", ai_rel:"★★★★★" }},
  {{ code:"ARM", name:"Arm", sector:"CPU/NPU IP", mcap:"1300", moat:"移动端CPU IP垄断，AI芯片NPU设计基础", ai_rel:"★★★★☆" }},
  {{ code:"SNPS", name:"新思科技", sector:"EDA", mcap:"900", moat:"EDA工具龙头，先进工艺芯片设计不可或缺", ai_rel:"★★★☆☆" }},
  {{ code:"ASML", name:"阿斯麦", sector:"光刻机", mcap:"3200", moat:"EUV光刻机全球垄断，无可替代", ai_rel:"★★★★☆" }},
  {{ code:"MSFT", name:"微软", sector:"云/AI平台", mcap:"32000", moat:"Azure+OpenAI捆绑，企业AI工作流标准", ai_rel:"★★★★★" }},
  // ── 存储/HBM ──
  {{ code:"MU", name:"美光科技", sector:"存储/HBM", mcap:"1000", moat:"HBM3E全球三大供应商之一，AI算力内存核心", ai_rel:"★★★★★" }},
  // ── 半导体设备 ──
  {{ code:"AMAT", name:"应用材料", sector:"半导体设备", mcap:"1500", moat:"CVD/PVD/CMP设备全覆盖，全球最大半导体设备公司", ai_rel:"★★★★☆" }},
  {{ code:"LRCX", name:"科林研发", sector:"半导体设备", mcap:"1000", moat:"刻蚀设备龙头，FinFET/GAA先进制程必需", ai_rel:"★★★★☆" }},
  {{ code:"KLAC", name:"科磊", sector:"半导体设备", mcap:"900", moat:"量测/检测设备垄断，良率管控不可或缺", ai_rel:"★★★☆☆" }},
  // ── 先进封装/代工 ──
  {{ code:"TSM", name:"台积电", sector:"先进封装/代工", mcap:"9000", moat:"2nm/CoWoS封装垄断，所有顶级AI芯片唯一代工", ai_rel:"★★★★★" }},
  // ── 网络互连 ──
  {{ code:"CSCO", name:"思科", sector:"网络互连", mcap:"2000", moat:"数据中心400G/800G交换机，AI集群网络骨干", ai_rel:"★★★☆☆" }},
  // ── 电源/散热 ──
  {{ code:"VRT", name:"维谛技术", sector:"电源/散热", mcap:"400", moat:"数据中心UPS+液冷全栈，AI算力基础设施首选", ai_rel:"★★★★☆" }},
  // ── AI应用 ──
  {{ code:"GOOG", name:"谷歌", sector:"AI应用/云", mcap:"20000", moat:"Gemini+TPU自研，搜索/广告+GCP三引擎", ai_rel:"★★★★★" }},
  {{ code:"META", name:"Meta", sector:"AI应用/社交", mcap:"15000", moat:"Llama开源生态+40亿用户AI推荐，广告AI驱动增长", ai_rel:"★★★★★" }},
  // ── 电力基建 ──
  {{ code:"CEG", name:"Constellation Energy", sector:"电力基建/核电", mcap:"700", moat:"美国最大核电运营商，微软/谷歌签约核电PPA，AI数据中心清洁能源首选", ai_rel:"★★★★★" }},
  {{ code:"VST", name:"Vistra Energy", sector:"电力基建/核电+热", mcap:"450", moat:"核电+天然气电力，德州电网龙头，数据中心选址优势，ERCOT市场高溢价", ai_rel:"★★★★☆" }},
  {{ code:"NEE", name:"NextEra Energy", sector:"电力基建/可再生", mcap:"1500", moat:"全球最大可再生能源公司，AI数据中心长期PPA协议规模最大", ai_rel:"★★★☆☆" }},
  {{ code:"ETN", name:"Eaton Corporation", sector:"电力基建/用电", mcap:"1200", moat:"数据中心配电+UPS+断路器全栈，AI数据中心电力基础设施订单激增", ai_rel:"★★★★☆" }},
  {{ code:"PWR", name:"Quanta Services", sector:"电力基建/输电", mcap:"500", moat:"北美最大电网建设承包商，超导输电/变电站升级，数据中心电力接入工程", ai_rel:"★★★★☆" }},
];

// ─── 工具函数 ───────────────────────────────────────────────────────────────
function getChart(id) {{
  const dom = document.getElementById(id);
  if (!dom) return null;
  const existing = echarts.getInstanceByDom(dom);
  if (existing) existing.dispose();
  return echarts.init(dom, 'dark');
}}

function switchTab(name, btn) {{
  document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.getElementById('tab-' + name).classList.add('active');
  if (btn) btn.classList.add('active');
  setTimeout(() => {{
    if (name === 'overview') {{ initRadarMain(); initUpsideBar(); initBubbleChart(); }}
    if (name === 'hkstocks') {{ initPeChart(); initSignalChart(); }}
    if (name === 'supply') {{ initSankeyChart(); initTreemapChart(); }}
    if (name === 'usstocks') {{ initUsMcapChart(); initUsPieChart(); renderUsTables(); }}
    if (name === 'portfolio') {{ initPortfolioCharts(); initRiskMatrix(); }}
  }}, 150);
}}

// ─── 总览图表 ────────────────────────────────────────────────────────────────
function initRadarMain() {{
  const chart = getChart('radarMain');
  if (!chart) return;
  const radarNames = {radar_names};
  const radarSeries = [
{radar_series_js}  ];
  chart.setOption({{
    backgroundColor: 'transparent',
    legend: {{ data: radarNames, bottom: 0, textStyle: {{ color: '#94a3b8', fontSize: 11 }} }},
    radar: {{
      indicator: [
        {{ name: '技术壁垒\\n(研发/专利)', max: 10 }},
        {{ name: '市场地位\\n(份额/定价)', max: 10 }},
        {{ name: 'AI受益度\\n(直接相关)', max: 10 }},
        {{ name: '政策顺风\\n(国产替代)', max: 10 }},
        {{ name: '估值安全\\n(PE/PEG)', max: 10 }},
      ],
      splitArea: {{ areaStyle: {{ color: ['rgba(30,41,59,0.3)','rgba(30,41,59,0.5)','rgba(30,41,59,0.7)','rgba(30,41,59,0.9)','rgba(30,41,59,1)'].reverse() }} }},
      axisName: {{ color: '#94a3b8', fontSize: 11, lineHeight: 16 }},
      splitLine: {{ lineStyle: {{ color: '#334155' }} }},
      axisLine: {{ lineStyle: {{ color: '#334155' }} }},
    }},
    series: [{{ type: 'radar', data: radarSeries }}],
  }});
  window.addEventListener('resize', () => chart.resize());
}}

function initUpsideBar() {{
  const chart = getChart('upsideBar');
  if (!chart) return;
  const stocks = {upside_names};
  const upsides = {upside_vals};
  const colors = upsides.map(v => v < 0 ? '#f87171' : v > 40 ? '#34d399' : '#38bdf8');
  chart.setOption({{
    backgroundColor: 'transparent',
    grid: {{ left: 90, right: 70, top: 10, bottom: 20 }},
    xAxis: {{ type: 'value', axisLabel: {{ color: '#94a3b8', formatter: v => v + '%' }}, splitLine: {{ lineStyle: {{ color: '#1e293b' }} }}, axisLine: {{ show: false }} }},
    yAxis: {{ type: 'category', data: stocks, axisLabel: {{ color: '#94a3b8', fontSize: 12 }}, axisLine: {{ show: false }}, axisTick: {{ show: false }} }},
    series: [{{
      type: 'bar', data: upsides.map((v, i) => ({{ value: v, itemStyle: {{ color: colors[i], borderRadius: [0, 4, 4, 0] }} }})),
      label: {{ show: true, position: 'right', color: '#e2e8f0', formatter: p => p.value > 0 ? '+' + p.value + '%' : p.value + '%' }},
    }}],
    markLine: {{ data: [{{ xAxis: 0, lineStyle: {{ color: '#475569', type: 'dashed' }} }}] }},
  }});
  window.addEventListener('resize', () => chart.resize());
}}

function initBubbleChart() {{
  const chart = getChart('bubbleChart');
  if (!chart) return;
  // [risk, return, confidence, name, signal]  — 由 analysis.json 动态注入
  const data = [
{bubble_data_js}  ];
  chart.setOption({{
    backgroundColor: 'transparent',
    grid: {{ left: 60, right: 100, top: 40, bottom: 60 }},
    xAxis: {{ name: '风险度 →', nameLocation: 'end', min: 0, max: 100, nameTextStyle: {{ color: '#94a3b8' }}, axisLabel: {{ color: '#94a3b8' }}, splitLine: {{ lineStyle: {{ color: '#1e293b' }} }}, axisLine: {{ lineStyle: {{ color: '#334155' }} }} }},
    yAxis: {{ name: '↑ 预期收益', nameLocation: 'end', min: -30, max: 100, nameTextStyle: {{ color: '#94a3b8' }}, axisLabel: {{ color: '#94a3b8', formatter: v => v + '%' }}, splitLine: {{ lineStyle: {{ color: '#1e293b' }} }}, axisLine: {{ lineStyle: {{ color: '#334155' }} }} }},
    series: [{{
      type: 'scatter',
      data: data.map(d => ({{ value: [d[0], d[1], d[2]], name: d[3],
        itemStyle: {{ color: d[1] > 30 ? 'rgba(52,211,153,0.85)' : d[1] < 0 ? 'rgba(248,113,113,0.85)' : 'rgba(56,189,248,0.85)' }} }})),
      symbolSize: d => Math.max(Math.sqrt(d[2]) * 15, 20),
      label: {{ show: true, formatter: p => p.name, position: 'right', color: '#e2e8f0', fontSize: 11 }},
    }}],
    markLine: {{ data: [{{ xAxis: 50, lineStyle: {{ color: '#475569', type: 'dashed' }} }}, {{ yAxis: 0, lineStyle: {{ color: '#475569', type: 'dashed' }} }}] }},
    tooltip: {{ formatter: p => `${{p.name}}<br/>风险度: ${{p.value[0]}}<br/>预期收益: +${{p.value[1]}}%<br/>信心度: ${{p.value[2]}}` }},
  }});
  window.addEventListener('resize', () => chart.resize());
}}

// ─── 港股图表 ────────────────────────────────────────────────────────────────
function initPeChart() {{
  const chart = getChart('peChart');
  if (!chart) return;
  const stocks = ['商汤科技','旷视科技','中兴通讯','百度集团','中芯国际','腾讯控股','阿里巴巴','小米集团','联想集团'];
  const pes    = [999, 999, 15, 12, 48, 22, 14, 25, 8];
  const colors = pes.map(p => p > 50 ? '#f87171' : p < 15 ? '#34d399' : '#38bdf8');
  chart.setOption({{
    backgroundColor: 'transparent',
    grid: {{ left: 90, right: 60, top: 20, bottom: 20 }},
    xAxis: {{ type: 'value', max: 100, axisLabel: {{ color: '#94a3b8' }}, splitLine: {{ lineStyle: {{ color: '#1e293b' }} }}, axisLine: {{ show: false }} }},
    yAxis: {{ type: 'category', data: stocks, axisLabel: {{ color: '#94a3b8' }}, axisLine: {{ show: false }}, axisTick: {{ show: false }} }},
    series: [
      {{ type: 'bar', data: pes.map((p, i) => ({{ value: Math.min(p, 95), itemStyle: {{ color: colors[i], borderRadius: [0,4,4,0] }} }})),
        label: {{ show: true, position: 'right', color: '#e2e8f0', formatter: p => pes[p.dataIndex] > 100 ? '亏损' : p.value + 'x' }} }},
      {{ type: 'line', data: new Array(stocks.length).fill(15), lineStyle: {{ color: '#fbbf24', type: 'dashed' }}, symbol: 'none', markLine: {{ show: false }}, z: 10 }},
    ],
  }});
  window.addEventListener('resize', () => chart.resize());
}}

function initSignalChart() {{
  const chart = getChart('signalChart');
  if (!chart) return;
  const stocks = ['中芯国际','阿里巴巴','联想集团','天数智芯','澜起科技H','百度集团','腾讯控股','中兴通讯'];
  const dims   = ['技术面','基本面','估值','催化剂','流动性'];
  const scores = [
    [85,90,70,95,80], // 中芯
    [75,88,92,88,95], // 阿里
    [70,82,96,80,90], // 联想
    [65,60,55,82,50], // 天数
    [80,78,72,85,65], // 澜起
    [68,70,88,75,85], // 百度
    [78,85,80,70,95], // 腾讯
    [72,74,78,72,80], // 中兴
  ];
  const flatData = [];
  stocks.forEach((s, i) => dims.forEach((d, j) => flatData.push([j, i, scores[i][j]])));
  chart.setOption({{
    backgroundColor: 'transparent',
    grid: {{ left: 80, right: 20, top: 20, bottom: 60 }},
    xAxis: {{ type: 'category', data: dims, axisLabel: {{ color: '#94a3b8' }}, axisLine: {{ show: false }} }},
    yAxis: {{ type: 'category', data: stocks, axisLabel: {{ color: '#94a3b8' }}, axisLine: {{ show: false }} }},
    visualMap: {{ min: 0, max: 100, calculable: true, orient: 'horizontal', left: 'center', bottom: 0, textStyle: {{ color: '#94a3b8' }},
      inRange: {{ color: ['#1e3a5f','#0369a1','#0284c7','#34d399','#10b981'] }} }},
    series: [{{ type: 'heatmap', data: flatData, label: {{ show: true, color: '#fff', fontSize: 11, formatter: p => p.value[2] }}, emphasis: {{ itemStyle: {{ shadowBlur: 10 }} }} }}],
    tooltip: {{ formatter: p => `${{stocks[p.value[1]]}} · ${{dims[p.value[0]]}}：${{p.value[2]}}` }},
  }});
  window.addEventListener('resize', () => chart.resize());
}}

// ─── 产业链图表 ──────────────────────────────────────────────────────────────
function initSankeyChart() {{
  const chart = getChart('sankeyChart');
  if (!chart) return;
  chart.setOption({{
    backgroundColor: 'transparent',
    series: [{{
      type: 'sankey', layout: 'none', emphasis: {{ focus: 'adjacency' }},
      nodeWidth: 14, nodeGap: 10,
      nodes: [
        // ── L0: 原材料/基础 ──
        {{name:'半导体材料\\n(雅克/南大光电)'}},
        // ── L1: 设备/EDA ──
        {{name:'ASML 光刻机'}},
        {{name:'AMAT/LRCX/KLAC 设备'}},
        {{name:'北方华创/中微 国产设备'}},
        {{name:'EDA\\n(SNPS/华大九天)'}},
        {{name:'ARM IP核'}},
        // ── L2: 代工/封装 ──
        {{name:'台积电 CoWoS先进封装'}},
        {{name:'中芯国际 SMIC'}},
        {{name:'先进封装\\n(长电/通富微电)'}},
        // ── L3: 存储 ──
        {{name:'HBM存储\\n(美光MU)'}},
        {{name:'DRAM/NOR\\n(兆易/君正)'}},
        // ── L4: 芯片 ──
        {{name:'NVDA Blackwell GPU'}},
        {{name:'AMD MI300X'}},
        {{name:'ASIC芯片\\n(AVGO/MRVL)'}},
        {{name:'华为昇腾 910B'}},
        {{name:'国产GPU/AI芯片'}},
        {{name:'光电混合算力\\n(曦智科技)'}},
        // ── L5: 服务器 + 网络互连 + 电源散热 ──
        {{name:'SMCI/Dell AI服务器'}},
        {{name:'浪潮/富联 AI服务器'}},
        {{name:'光模块\\n(旭创/新易盛)'}},
        {{name:'光互连/光计算互连\\n(MRVL DSP)'}},
        {{name:'网络互连\\n(思科/锐捷)'}},
        {{name:'电源散热\\n(VRT/申菱)'}},
        // ── L6: 云/数据中心 ──
        {{name:'AWS/Azure/GCP'}},
        {{name:'阿里云/腾讯云'}},
        {{name:'国内AI数据中心'}},
        // ── L7: AI应用 ──
        {{name:'AI大模型训练'}},
        {{name:'AI推理\\n(谷歌/Meta/讯飞)'}},
      ],
      links: [
        // 材料 → 设备
        {{source:'半导体材料\\n(雅克/南大光电)', target:'ASML 光刻机', value:20}},
        {{source:'半导体材料\\n(雅克/南大光电)', target:'AMAT/LRCX/KLAC 设备', value:30}},
        {{source:'半导体材料\\n(雅克/南大光电)', target:'北方华创/中微 国产设备', value:20}},
        // 设备/EDA → 代工
        {{source:'ASML 光刻机', target:'台积电 CoWoS先进封装', value:80}},
        {{source:'AMAT/LRCX/KLAC 设备', target:'台积电 CoWoS先进封装', value:60}},
        {{source:'AMAT/LRCX/KLAC 设备', target:'中芯国际 SMIC', value:35}},
        {{source:'北方华创/中微 国产设备', target:'中芯国际 SMIC', value:30}},
        {{source:'EDA\\n(SNPS/华大九天)', target:'台积电 CoWoS先进封装', value:20}},
        {{source:'EDA\\n(SNPS/华大九天)', target:'中芯国际 SMIC', value:15}},
        {{source:'ARM IP核', target:'NVDA Blackwell GPU', value:50}},
        {{source:'ARM IP核', target:'AMD MI300X', value:30}},
        {{source:'ARM IP核', target:'ASIC芯片\\n(AVGO/MRVL)', value:20}},
        // 代工 → 封装
        {{source:'台积电 CoWoS先进封装', target:'先进封装\\n(长电/通富微电)', value:40}},
        // 代工/封装 → 芯片
        {{source:'台积电 CoWoS先进封装', target:'NVDA Blackwell GPU', value:100}},
        {{source:'台积电 CoWoS先进封装', target:'AMD MI300X', value:60}},
        {{source:'台积电 CoWoS先进封装', target:'ASIC芯片\\n(AVGO/MRVL)', value:40}},
        {{source:'中芯国际 SMIC', target:'华为昇腾 910B', value:50}},
        {{source:'中芯国际 SMIC', target:'国产GPU/AI芯片', value:30}},
        {{source:'先进封装\\n(长电/通富微电)', target:'NVDA Blackwell GPU', value:20}},
        {{source:'先进封装\\n(长电/通富微电)', target:'国产GPU/AI芯片', value:20}},
        // 存储 → 服务器
        {{source:'HBM存储\\n(美光MU)', target:'NVDA Blackwell GPU', value:60}},
        {{source:'HBM存储\\n(美光MU)', target:'AMD MI300X', value:30}},
        {{source:'DRAM/NOR\\n(兆易/君正)', target:'浪潮/富联 AI服务器', value:25}},
        {{source:'DRAM/NOR\\n(兆易/君正)', target:'SMCI/Dell AI服务器', value:15}},
        // 芯片 → 服务器
        {{source:'NVDA Blackwell GPU', target:'SMCI/Dell AI服务器', value:80}},
        {{source:'NVDA Blackwell GPU', target:'浪潮/富联 AI服务器', value:40}},
        {{source:'AMD MI300X', target:'SMCI/Dell AI服务器', value:40}},
        {{source:'ASIC芯片\\n(AVGO/MRVL)', target:'SMCI/Dell AI服务器', value:30}},
        {{source:'华为昇腾 910B', target:'浪潮/富联 AI服务器', value:50}},
        {{source:'国产GPU/AI芯片', target:'浪潮/富联 AI服务器', value:20}},
        // 光模块 → 服务器
        {{source:'光模块\\n(旭创/新易盛)', target:'SMCI/Dell AI服务器', value:50}},
        {{source:'光模块\\n(旭创/新易盛)', target:'浪潮/富联 AI服务器', value:30}},
        {{source:'光模块\\n(旭创/新易盛)', target:'光互连/光计算互连\\n(MRVL DSP)', value:40}},
        // 光电混合算力（曦智科技）← 上游：代工+光器件+EDA
        {{source:'台积电 CoWoS先进封装', target:'光电混合算力\\n(曦智科技)', value:35}},
        {{source:'光模块\\n(旭创/新易盛)', target:'光电混合算力\\n(曦智科技)', value:25}},
        {{source:'EDA\\n(SNPS/华大九天)', target:'光电混合算力\\n(曦智科技)', value:10}},
        // 光电混合算力 → 数据中心（替代传统GPU互连，显著降低能耗）
        {{source:'光电混合算力\\n(曦智科技)', target:'国内AI数据中心', value:45}},
        {{source:'光电混合算力\\n(曦智科技)', target:'阿里云/腾讯云', value:25}},
        // 光互连互连节点 → 服务器
        {{source:'光互连/光计算互连\\n(MRVL DSP)', target:'SMCI/Dell AI服务器', value:35}},
        {{source:'光互连/光计算互连\\n(MRVL DSP)', target:'浪潮/富联 AI服务器', value:25}},
        // 网络互连 → 服务器
        {{source:'网络互连\\n(思科/锐捷)', target:'SMCI/Dell AI服务器', value:30}},
        {{source:'网络互连\\n(思科/锐捷)', target:'浪潮/富联 AI服务器', value:20}},
        // 电源散热 → 服务器
        {{source:'电源散热\\n(VRT/申菱)', target:'SMCI/Dell AI服务器', value:25}},
        {{source:'电源散热\\n(VRT/申菱)', target:'浪潮/富联 AI服务器', value:20}},
        // 服务器 → 云
        {{source:'SMCI/Dell AI服务器', target:'AWS/Azure/GCP', value:100}},
        {{source:'SMCI/Dell AI服务器', target:'阿里云/腾讯云', value:30}},
        {{source:'浪潮/富联 AI服务器', target:'阿里云/腾讯云', value:70}},
        {{source:'浪潮/富联 AI服务器', target:'国内AI数据中心', value:50}},
        // 云 → AI训练
        {{source:'AWS/Azure/GCP', target:'AI大模型训练', value:100}},
        {{source:'阿里云/腾讯云', target:'AI大模型训练', value:70}},
        {{source:'国内AI数据中心', target:'AI大模型训练', value:50}},
        // 训练 → 推理/应用
        {{source:'AI大模型训练', target:'AI推理\\n(谷歌/Meta/讯飞)', value:220}},
      ],
      label: {{ color: '#e2e8f0', fontSize: 10 }},
      lineStyle: {{ color: 'gradient', opacity: 0.35 }},
      itemStyle: {{ borderWidth: 0 }},
    }}],
    tooltip: {{ trigger: 'item' }},
  }});
  window.addEventListener('resize', () => chart.resize());
}}

function initTreemapChart() {{
  const chart = getChart('treemapChart');
  if (!chart) return;
  chart.setOption({{
    backgroundColor: 'transparent',
    series: [{{
      type: 'treemap', roam: false,
      label: {{ show: true, formatter: p => p.name + '\\n' + p.value, fontSize: 11 }},
      breadcrumb: {{ show: false }},
      data: [
        {{ name: '🔴 AI GPU/ASIC', value: 350, itemStyle: {{ color: '#1e3a5f' }}, children: [
          {{ name: 'NVDA', value: 120 }}, {{ name: 'AVGO', value: 80 }},
          {{ name: 'AMD', value: 60 }}, {{ name: '寒武纪', value: 40 }},
          {{ name: '海光信息', value: 30 }}, {{ name: '天数智芯', value: 20 }},
        ]}},
        {{ name: '🟠 光模块/光计算', value: 250, itemStyle: {{ color: '#1a3040' }}, children: [
          {{ name: '中际旭创', value: 70 }}, {{ name: '天孚通信', value: 50 }},
          {{ name: '新易盛', value: 40 }}, {{ name: 'Coherent', value: 40 }},
          {{ name: '曦智科技\\n光电算力', value: 50 }},
        ]}},
        {{ name: '⚙️ 先进代工', value: 180, itemStyle: {{ color: '#1e2840' }}, children: [
          {{ name: '中芯国际', value: 90 }}, {{ name: '台积电', value: 60 }}, {{ name: '华虹半导体', value: 30 }},
        ]}},
        {{ name: '🟡 AI服务器', value: 160, itemStyle: {{ color: '#1c3030' }}, children: [
          {{ name: 'SMCI', value: 60 }}, {{ name: '联想集团', value: 50 }},
          {{ name: '浪潮信息', value: 30 }}, {{ name: '工业富联', value: 20 }},
        ]}},
        {{ name: '☁️ 云/AI平台', value: 250, itemStyle: {{ color: '#1e2a20' }}, children: [
          {{ name: '阿里巴巴', value: 100 }}, {{ name: '腾讯控股', value: 80 }},
          {{ name: '百度集团', value: 40 }}, {{ name: '微软', value: 30 }},
        ]}},
        {{ name: '🔧 EDA/设备', value: 100, itemStyle: {{ color: '#241e30' }}, children: [
          {{ name: 'ASML', value: 50 }}, {{ name: 'SNPS', value: 25 }}, {{ name: '华大九天', value: 25 }},
        ]}},
        {{ name: '💾 存储/HBM', value: 120, itemStyle: {{ color: '#1a2a3a' }}, children: [
          {{ name: '美光MU', value: 70 }}, {{ name: '兆易创新', value: 30 }}, {{ name: '北京君正', value: 20 }},
        ]}},
        {{ name: '🏭 半导体设备', value: 110, itemStyle: {{ color: '#2a1e30' }}, children: [
          {{ name: 'AMAT', value: 40 }}, {{ name: 'LRCX', value: 30 }}, {{ name: 'KLAC', value: 20 }},
          {{ name: '北方华创', value: 15 }}, {{ name: '中微公司', value: 5 }},
        ]}},
        {{ name: '📦 先进封装', value: 90, itemStyle: {{ color: '#2a2a1a' }}, children: [
          {{ name: '长电科技', value: 40 }}, {{ name: '通富微电', value: 30 }}, {{ name: '华天科技', value: 20 }},
        ]}},
        {{ name: '🌐 网络互连', value: 80, itemStyle: {{ color: '#1a302a' }}, children: [
          {{ name: 'Cisco', value: 50 }}, {{ name: '锐捷网络', value: 30 }},
        ]}},
        {{ name: '⚡ 电源散热', value: 60, itemStyle: {{ color: '#2a2010' }}, children: [
          {{ name: 'VRT', value: 30 }}, {{ name: '英威腾', value: 15 }}, {{ name: '申菱环境', value: 15 }},
        ]}},
        {{ name: '⚡ 电力基建', value: 130, itemStyle: {{ color: '#1a1a30' }}, children: [
          {{ name: 'CEG核电', value: 35 }}, {{ name: 'VST', value: 25 }},
          {{ name: '国电南瑞', value: 20 }}, {{ name: '宁德时代', value: 25 }},
          {{ name: '特变电工', value: 15 }}, {{ name: '长江电力', value: 10 }},
        ]}},
        {{ name: '🤖 AI应用', value: 180, itemStyle: {{ color: '#102a20' }}, children: [
          {{ name: '谷歌', value: 70 }}, {{ name: 'Meta', value: 60 }},
          {{ name: '科大讯飞', value: 30 }}, {{ name: '昆仑万维', value: 20 }},
        ]}},
      ],
    }}],
    tooltip: {{ formatter: p => `${{p.name}}: ${{p.value}}亿市值权重` }},
  }});
  window.addEventListener('resize', () => chart.resize());
}}

// ─── 美股图表 ────────────────────────────────────────────────────────────────
function initUsMcapChart() {{
  const chart = getChart('usMcapChart');
  if (!chart) return;
  const names = ['微软', '谷歌', 'Meta', '英伟达', '台积电', '阿斯麦', 'Arm', '博通', '美光', '思科', 'AMD', 'VRT', 'SNPS', '超微电脑', 'AMAT', 'LRCX', 'KLAC', '迈威尔', '科锐'];
  const mcaps = [32000, 20000, 15000, 30000, 9000, 3200, 1300, 8000, 1000, 2000, 2500, 400, 900, 250, 1500, 1000, 900, 550, 150];
  chart.setOption({{
    backgroundColor: 'transparent',
    grid: {{ left: 60, right: 40, top: 10, bottom: 20 }},
    xAxis: {{ type: 'category', data: names, axisLabel: {{ color: '#94a3b8', rotate: 30, fontSize: 11 }}, axisLine: {{ show: false }} }},
    yAxis: {{ type: 'value', axisLabel: {{ color: '#94a3b8', formatter: v => v >= 1000 ? (v/1000).toFixed(0) + 'T' : v + 'B' }}, splitLine: {{ lineStyle: {{ color: '#1e293b' }} }} }},
    series: [{{
      type: 'bar', data: mcaps.map(v => ({{ value: v, itemStyle: {{ color: v > 10000 ? '#38bdf8' : '#475569', borderRadius: [4,4,0,0] }} }})),
      label: {{ show: true, position: 'top', color: '#94a3b8', fontSize: 10, formatter: p => p.value >= 1000 ? '$' + (p.value/1000).toFixed(1) + 'T' : '$' + p.value + 'B' }},
    }}],
  }});
  window.addEventListener('resize', () => chart.resize());
}}

function initUsPieChart() {{
  const chart = getChart('usPieChart');
  if (!chart) return;
  chart.setOption({{
    backgroundColor: 'transparent',
    legend: {{ orient: 'vertical', right: 10, textStyle: {{ color: '#94a3b8', fontSize: 11 }} }},
    series: [{{
      type: 'pie', radius: ['40%', '70%'], center: ['35%', '50%'],
      data: [
        {{ value: 62750, name: 'AI GPU/ASIC', itemStyle: {{ color: '#38bdf8' }} }},
        {{ value: 13400, name: '先进代工/封装', itemStyle: {{ color: '#a78bfa' }} }},
        {{ value: 3400, name: '半导体设备', itemStyle: {{ color: '#c084fc' }} }},
        {{ value: 67000, name: '云/AI平台', itemStyle: {{ color: '#34d399' }} }},
        {{ value: 1000, name: '存储/HBM', itemStyle: {{ color: '#60a5fa' }} }},
        {{ value: 2150, name: '网络互连', itemStyle: {{ color: '#f97316' }} }},
        {{ value: 400, name: '电源散热', itemStyle: {{ color: '#fb923c' }} }},
        {{ value: 275, name: 'AI服务器', itemStyle: {{ color: '#fbbf24' }} }},
      ],
      label: {{ show: false }},
      emphasis: {{ label: {{ show: true, fontSize: 12, color: '#e2e8f0' }} }},
    }}],
    tooltip: {{ formatter: p => `${{p.name}}<br/>${{(p.value/1000).toFixed(0)}}B (${{p.percent}}%)` }},
  }});
  window.addEventListener('resize', () => chart.resize());
}}

// ─── 组合图表 ────────────────────────────────────────────────────────────────
function initPortfolioCharts() {{
  const conservData = [
    {{ value: 40, name: '00981 中芯国际', itemStyle: {{ color: '#38bdf8' }} }},
    {{ value: 35, name: '09988 阿里巴巴', itemStyle: {{ color: '#fbbf24' }} }},
    {{ value: 25, name: '00992 联想集团', itemStyle: {{ color: '#34d399' }} }},
  ];
  const balanceData = [
    {{ value: 30, name: '00981 中芯国际', itemStyle: {{ color: '#38bdf8' }} }},
    {{ value: 25, name: '09988 阿里巴巴', itemStyle: {{ color: '#fbbf24' }} }},
    {{ value: 20, name: '00992 联想集团', itemStyle: {{ color: '#34d399' }} }},
    {{ value: 15, name: '06809 澜起科技H', itemStyle: {{ color: '#a78bfa' }} }},
    {{ value: 10, name: '09888 百度集团', itemStyle: {{ color: '#f97316' }} }},
  ];
  const agressData = [
    {{ value: 25, name: '00981 中芯国际', itemStyle: {{ color: '#38bdf8' }} }},
    {{ value: 20, name: '09988 阿里巴巴', itemStyle: {{ color: '#fbbf24' }} }},
    {{ value: 20, name: '09903 天数智芯', itemStyle: {{ color: '#f87171' }} }},
    {{ value: 15, name: '06809 澜起科技H', itemStyle: {{ color: '#a78bfa' }} }},
    {{ value: 10, name: '00992 联想集团', itemStyle: {{ color: '#34d399' }} }},
    {{ value: 10, name: '09888 百度集团', itemStyle: {{ color: '#f97316' }} }},
  ];

  [['portfolioConserv', conservData], ['portfolioBalance', balanceData], ['portfolioAggress', agressData]].forEach(([id, data]) => {{
    const chart = getChart(id);
    if (!chart) return;
    chart.setOption({{
      backgroundColor: 'transparent',
      legend: {{ bottom: 0, textStyle: {{ color: '#94a3b8', fontSize: 10 }} }},
      series: [{{
        type: 'pie', radius: ['38%', '62%'], center: ['50%', '42%'],
        data, label: {{ show: false }},
        emphasis: {{ label: {{ show: true, fontSize: 11, color: '#e2e8f0' }} }},
      }}],
      tooltip: {{ formatter: p => `${{p.name}}: ${{p.percent}}%` }},
    }});
    window.addEventListener('resize', () => chart.resize());
  }});
}}

function initRiskMatrix() {{
  const chart = getChart('riskMatrix');
  if (!chart) return;
  const risks = [
    [80, 90, '地缘政治风险'],
    [55, 85, 'AI芯片出口管制升级'],
    [40, 70, '光模块价格战'],
    [35, 55, 'AI应用变现不及预期'],
    [25, 40, '国内消费降级'],
    [70, 60, '大基金投资节奏偏慢'],
    [50, 75, '竞争对手技术突破'],
  ];
  chart.setOption({{
    backgroundColor: 'transparent',
    grid: {{ left: 70, right: 80, top: 40, bottom: 60 }},
    xAxis: {{ name: '发生概率 →', min: 0, max: 100, nameLocation: 'end', nameTextStyle: {{ color: '#94a3b8' }},
      axisLabel: {{ color: '#94a3b8', formatter: v => v + '%' }}, splitLine: {{ lineStyle: {{ color: '#1e293b' }} }}, axisLine: {{ lineStyle: {{ color: '#334155' }} }} }},
    yAxis: {{ name: '↑ 影响程度', min: 0, max: 100, nameLocation: 'end', nameTextStyle: {{ color: '#94a3b8' }},
      axisLabel: {{ color: '#94a3b8' }}, splitLine: {{ lineStyle: {{ color: '#1e293b' }} }}, axisLine: {{ lineStyle: {{ color: '#334155' }} }} }},
    series: [{{
      type: 'scatter', symbolSize: 20,
      data: risks.map(r => ({{ value: [r[0], r[1]], name: r[2],
        itemStyle: {{ color: r[0]*r[1] > 4000 ? '#f87171' : r[0]*r[1] > 2000 ? '#fbbf24' : '#38bdf8' }} }})),
      label: {{ show: true, formatter: p => p.name, position: 'right', color: '#e2e8f0', fontSize: 11 }},
    }}],
    markArea: {{
      silent: true,
      data: [[{{ coord: [60, 60], itemStyle: {{ color: 'rgba(248,113,113,0.05)' }} }}, {{ coord: [100, 100] }}]],
    }},
    tooltip: {{ formatter: p => `${{p.name}}<br>概率: ${{p.value[0]}}%<br>影响: ${{p.value[1]}}` }},
  }});
  window.addEventListener('resize', () => chart.resize());
}}

// ─── 渲染表格 ────────────────────────────────────────────────────────────────
function renderAshareTables() {{
  const signalBadge = (s) => {{
    const map = {{ buy: ['badge-buy','买入'], hold: ['badge-hold','持有'], watch: ['badge-hold','关注'], sell: ['badge-sell','回避'] }};
    const [cls, text] = map[s] || ['badge-hold', s];
    return `<span class="badge ${{cls}}">${{text}}</span>`;
  }};
  const tbody = document.getElementById('ashare-table-body');
  if (!tbody) return;
  tbody.innerHTML = ashareData.map(s => `
    <tr>
      <td><span style="font-family:monospace;color:var(--accent);">${{s.code}}</span></td>
      <td style="font-weight:600;">${{s.name}}</td>
      <td><span style="color:var(--muted);font-size:11px;">${{s.market}}</span></td>
      <td><span style="color:var(--yellow);font-size:12px;">${{s.sector}}</span></td>
      <td style="color:var(--muted);font-size:12px;">${{s.logic}}</td>
      <td>${{signalBadge(s.signal)}}</td>
    </tr>
  `).join('');
}}

function renderUsTables() {{
  const tbody = document.getElementById('us-table-body');
  if (!tbody) return;
  tbody.innerHTML = usData.map(s => `
    <tr>
      <td><span style="font-family:monospace;font-weight:700;color:#38bdf8;">${{s.code}}</span></td>
      <td style="font-weight:600;">${{s.name}}</td>
      <td><span style="color:var(--yellow);font-size:12px;">${{s.sector}}</span></td>
      <td style="color:var(--muted);">${{(parseInt(s.mcap)/100).toFixed(0)}}B</td>
      <td style="color:var(--muted);font-size:12px;">${{s.moat}}</td>
      <td style="color:var(--green);">${{s.ai_rel}}</td>
    </tr>
  `).join('');
}}

// ─── 初始化 ───────────────────────────────────────────────────────────────────
window.addEventListener('load', () => {{
  renderAshareTables();
  setTimeout(() => {{
    initRadarMain();
    initUpsideBar();
    initBubbleChart();
  }}, 400);
}});
</script>
</body>
</html>'''

Path(output_path).parent.mkdir(parents=True, exist_ok=True)
with open(output_path, 'w', encoding='utf-8') as f:
    f.write(html)

print(f"✅ HTML报告已生成: {output_path}")
print(f"   文件大小: {len(html.encode())/1024:.0f} KB")
PYEOF

echo ""
echo "✅ 报告生成完成: $OUTPUT_FILE"
echo "   文件大小: $(du -sh "$OUTPUT_FILE" | cut -f1)"
echo ""
echo "🌐 在浏览器中打开:"
echo "   open $OUTPUT_FILE"
