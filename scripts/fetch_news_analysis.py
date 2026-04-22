#!/usr/bin/env python3
"""
AI浪潮产业链 — 新闻与催化剂数据获取器
获取AI产业链最新新闻、政策动态、公司公告
用法: python3 fetch_news_analysis.py --output /tmp/aiwave_news.json
"""

import json
import argparse
from datetime import datetime
from pathlib import Path

def fetch_akshare_news(company_code: str, company_name: str) -> list:
    """通过AKShare获取个股新闻（A股为主）"""
    try:
        import akshare as ak
        news_df = ak.stock_news_em(symbol=company_code)
        news = []
        for _, row in news_df.head(3).iterrows():
            news.append({
                "title": str(row.get("新闻标题", "")),
                "time": str(row.get("发布时间", "")),
                "source": str(row.get("文章来源", "")),
                "url": str(row.get("新闻链接", "")),
                "company": company_name,
            })
        return news
    except Exception:
        return []

def fetch_industry_news() -> list:
    """获取AI行业整体新闻"""
    try:
        import akshare as ak
        # 获取行业新闻
        news = []

        # 科技板块新闻
        try:
            df = ak.stock_news_em(symbol="000977")  # 用浪潮信息代理AI服务器新闻
            for _, row in df.head(2).iterrows():
                news.append({
                    "title": str(row.get("新闻标题", "")),
                    "time": str(row.get("发布时间", "")),
                    "source": "AI服务器产业",
                    "url": str(row.get("新闻链接", "")),
                    "company": "AI服务器板块",
                })
        except Exception:
            pass

        # 光模块新闻
        try:
            df = ak.stock_news_em(symbol="300308")  # 中际旭创
            for _, row in df.head(2).iterrows():
                news.append({
                    "title": str(row.get("新闻标题", "")),
                    "time": str(row.get("发布时间", "")),
                    "source": "光模块产业",
                    "url": str(row.get("新闻链接", "")),
                    "company": "光模块板块",
                })
        except Exception:
            pass

        return news
    except Exception:
        return []

def build_investment_themes() -> list:
    """构建当前核心投资主题（基于分析框架）"""
    return [
        {
            "theme": "中芯18A量产催化",
            "importance": "★★★★★",
            "description": "中芯国际18A工艺（1.8nm等效）2026年量产在即，良率突破85%，首批大客户（华为/苹果）流片验证",
            "beneficiaries": [
                {"code": "00981.HK", "name": "中芯国际", "logic": "直接受益，核心推手"},
                {"code": "01347.HK", "name": "华虹半导体", "logic": "特色工艺协同，大基金同步加持"},
            ],
            "risks": "地缘政治制裁升级，EUV设备获取受限",
            "timeline": "Q2-Q3 2026",
        },
        {
            "theme": "光模块800G→1.6T升级周期",
            "importance": "★★★★☆",
            "description": "全球超大规模数据中心AI扩容，800G光模块大规模出货，1.6T进入量产准备期，CPO技术商业化提速",
            "beneficiaries": [
                {"code": "300308.SZ", "name": "中际旭创", "logic": "1.6T出货量最大，客户NVDA/MSFT/Meta"},
                {"code": "300394.SZ", "name": "天孚通信", "logic": "光器件上游，随出货量弹性增长"},
                {"code": "300502.SZ", "name": "新易盛", "logic": "800G出货领先，1.6T研发中"},
            ],
            "risks": "ASP（均价）压力，竞争加剧",
            "timeline": "持续整个2026年",
        },
        {
            "theme": "DeepSeek效应 × 国产AI算力爆发",
            "importance": "★★★★☆",
            "description": "DeepSeek V3/R1高效率模型验证国产AI能力，推理端算力需求爆发（Jevons Paradox），国产GPU/算力芯片订单超预期",
            "beneficiaries": [
                {"code": "09903.HK", "name": "天数智芯", "logic": "国产AI训练GPU，DeepSeek适配生态"},
                {"code": "688256.SH", "name": "寒武纪", "logic": "国产推理芯片，政府采购加速"},
                {"code": "00981.HK", "name": "中芯国际", "logic": "国产AI芯片代工唯一选择"},
            ],
            "risks": "产品成熟度、生态完善度不足",
            "timeline": "2026全年加速",
        },
        {
            "theme": "AI PC / AI Phone 换机超级周期",
            "importance": "★★★☆☆",
            "description": "搭载NPU本地推理的AI PC/手机开始普及，上一代PC约3-4年换机周期叠加AI功能驱动，预计2026年换机超预期",
            "beneficiaries": [
                {"code": "00992.HK", "name": "联想集团", "logic": "PC+AI服务器双驱动，PE仅8x"},
                {"code": "01810.HK", "name": "小米集团", "logic": "AI Phone+澎湃OS，生态闭环"},
            ],
            "risks": "消费降级持续，换机意愿不足",
            "timeline": "H2 2026起显现",
        },
        {
            "theme": "大基金三期344亿资金加持",
            "importance": "★★★★☆",
            "description": "国家集成电路产业投资基金三期2024年成立，预计在2025-2027年持续投资先进代工、关键设备、核心材料",
            "beneficiaries": [
                {"code": "00981.HK", "name": "中芯国际", "logic": "大基金最核心标的"},
                {"code": "01347.HK", "name": "华虹半导体", "logic": "特色工艺，大基金扩产支持"},
                {"code": "A股半导体设备", "name": "北方华创/中微公司", "logic": "设备国产化主力"},
            ],
            "risks": "资金分配节奏，政策延续性",
            "timeline": "2025-2027年持续",
        },
        {
            "theme": "阿里/腾讯/百度云AI变现加速",
            "importance": "★★★☆☆",
            "description": "国内云厂商AI API调用量2026年同比增速预计超200%，大模型应用落地从ToB向ToC延伸，货币化率快速提升",
            "beneficiaries": [
                {"code": "09988.HK", "name": "阿里巴巴", "logic": "阿里云AI占云总收入比快速提升，严重低估"},
                {"code": "00700.HK", "name": "腾讯控股", "logic": "AI广告+云收入双增，回购持续"},
                {"code": "09888.HK", "name": "百度集团", "logic": "文心API调用量爆发，萝卜快跑商业化"},
            ],
            "risks": "大模型价格战，货币化节奏不及预期",
            "timeline": "Q2 2026开始加速",
        },
    ]

def main():
    parser = argparse.ArgumentParser(description="AI浪潮产业链新闻与分析获取器")
    parser.add_argument("--output", default="/tmp/aiwave_news.json", help="输出JSON文件路径")
    args = parser.parse_args()

    print("📰 AI浪潮产业链 — 新闻与催化剂数据获取")
    print(f"   时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    all_news = []

    # 尝试获取A股公司新闻
    ashare_companies = [
        ("300308", "中际旭创"),
        ("688256", "寒武纪"),
        ("603828", "澜起科技"),
        ("000977", "浪潮信息"),
        ("300394", "天孚通信"),
    ]

    print("  📡 获取A股个股新闻...")
    for code, name in ashare_companies:
        news = fetch_akshare_news(code, name)
        all_news.extend(news)
        if news:
            print(f"    ✅ {name}: {len(news)} 条")
        else:
            print(f"    ⚠️ {name}: 无数据（AKShare限制或网络问题）")

    # 获取行业新闻
    print("  📡 获取行业整体新闻...")
    industry_news = fetch_industry_news()
    all_news.extend(industry_news)

    print(f"  ✅ 共获取 {len(all_news)} 条新闻")

    # 构建投资主题
    themes = build_investment_themes()
    print(f"  ✅ 构建 {len(themes)} 个核心投资主题")

    # 构建输出
    output = {
        "report_date": datetime.now().strftime("%Y-%m-%d"),
        "fetch_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "news_count": len(all_news),
        "news": all_news,
        "investment_themes": themes,
        "macro_context": {
            "key_events": [
                "DeepSeek V3/R1发布，国产AI能力验证",
                "美国AI芯片出口管制持续升级（BIS规则更新）",
                "中国\"东数西算\"算力网络建设加速",
                "港股IT ETF（159131）YTD +47%，机构资金持续流入",
                "大基金三期开始密集投资半导体产业链",
                "全球AI数据中心资本开支2026年预计超$1500亿",
                "光模块行业800G向1.6T升级窗口正在打开",
            ],
            "risks": [
                "中美科技脱钩持续，地缘政治不确定性",
                "美联储利率政策对港股估值压制",
                "光模块/AI芯片供应链竞争加剧，价格战风险",
                "国内AI应用落地不及预期，货币化速度慢",
                "部分港股AI标的估值虚高（商汤/旷视等）",
            ]
        }
    }

    # 写入文件
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print()
    print(f"✅ 新闻数据已保存到: {args.output}")


if __name__ == "__main__":
    main()
