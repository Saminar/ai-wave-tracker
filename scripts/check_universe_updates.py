#!/usr/bin/env python3
"""
AI浪潮产业链 — 标的池更新检查器 (Phase 0)

运行机制：
1. 维护一份"已知候选池"（PENDING_CANDIDATES），记录已发现但尚未纳入追踪的标的
2. 对候选池中的每只标的，通过腾讯财经 API 验证其是否已上市、能获取行情
3. 与当前 STOCKS 追踪池对比，输出差异供用户确认
4. 通过 WebSearch/新闻发现新标的后，手动追加到 PENDING_CANDIDATES

用法:
    python3 check_universe_updates.py [--output /tmp/aiwave_universe_update.json]
    python3 check_universe_updates.py --silent   # 无新标的时静默
    python3 check_universe_updates.py --verify-all  # 重新验证所有候选（含已跳过）
"""

import json
import time
import argparse
import requests
from datetime import datetime
from pathlib import Path
from typing import Optional

# ─── 当前追踪池（与 fetch_stock_data.py 保持同步）───────────────────────────
# ⚠️ 每次更新 fetch_stock_data.py 后必须同步更新这里
CURRENT_HK = {
    "00981", "09988", "00992", "00700", "09888", "09903",
    "00763", "01347", "01810", "02382", "00020", "06060",
    "00068", "00100", "03896", "06082",
}

CURRENT_ASHARE = {
    "688256", "688041", "688047", "603828", "301269",
    "300308", "300394", "300502", "000988", "002281",
    "000977", "601138", "603019", "603986", "300223",
    "002371", "688012", "688072", "002318", "688188",
    "002106", "603989", "601986", "002156", "002185",
    "301165", "002334", "301018", "002230", "300418",
    "601360",
}

CURRENT_US = {
    "NVDA", "AMD", "AVGO", "MRVL", "COHR", "SMCI", "ARM",
    "SNPS", "ASML", "MSFT", "MU", "AMAT", "LRCX", "KLAC",
    "TSM", "CSCO", "VRT", "GOOG", "META", "DELL", "AMZN", "CDNS",
}

# ─── 已知候选池 ─────────────────────────────────────────────────────────────
# 发现新 AI 产业链标的后，在这里追加，下次运行时自动验证并提示
# 格式: {"tencent_code": "hk00001", "code": "00001", "name": "XXX",
#         "market": "港股", "sector": "AI软件", "reason": "发现原因",
#         "discovered": "YYYY-MM-DD", "skip": False}
PENDING_CANDIDATES = [
    # ── 港股 ──────────────────────────────────────────────────────────────
    {
        "tencent_code": "hk01810",
        "code": "01810",
        "name": "小米集团（已纳入，仅作示例）",
        "market": "港股",
        "sector": "AI终端",
        "reason": "示例条目，已在追踪池中",
        "discovered": "2026-04-24",
        "skip": True,
    },
    # 在此添加新发现的候选标的 ↓
    # {
    #     "tencent_code": "hk01234",
    #     "code": "01234",
    #     "name": "示例科技",
    #     "market": "港股",
    #     "sector": "AI芯片",
    #     "reason": "2026年新IPO，空间AI方向",
    #     "discovered": "2026-04-24",
    #     "skip": False,
    # },
]

# ─── AI 产业链关键词（名称/板块匹配用）───────────────────────────────────────
AI_KEYWORDS = [
    "AI", "人工智能", "大模型", "算力", "智算", "GPU", "芯片",
    "光模块", "光器件", "数据中心", "云计算",
    "半导体", "存储", "HBM", "封装", "先进制程",
    "机器人", "自动驾驶", "边缘计算", "空间智能", "具身智能",
    "SaaS", "大数据", "数字化",
]

API_HEADERS = {
    "Referer": "https://finance.qq.com",
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
}


def verify_quote(tencent_code: str) -> Optional[dict]:
    """
    通过腾讯财经 API 验证标的是否可获取行情数据
    成功返回 {"name", "price", "change_pct"}，失败返回 None
    """
    try:
        url = f"https://qt.gtimg.cn/q={tencent_code}"
        resp = requests.get(url, headers=API_HEADERS, timeout=10)
        resp.encoding = "gbk"
        for line in resp.text.strip().split(";"):
            line = line.strip()
            if not line or "v_" not in line or '"' not in line:
                continue
            val = line.split('"')[1] if '"' in line else ""
            fields = val.split("~")
            if len(fields) >= 5 and fields[1] and float(fields[3] or 0) > 0:
                return {
                    "name": fields[1],
                    "price": float(fields[3]),
                    "change_pct": round(
                        (float(fields[3]) - float(fields[4])) / float(fields[4]) * 100
                        if float(fields[4]) > 0 else 0, 2
                    )
                }
    except Exception:
        pass
    return None


def get_all_current_codes() -> set:
    """返回所有当前追踪池的标准代码集合"""
    return CURRENT_HK | CURRENT_ASHARE | CURRENT_US


def main():
    parser = argparse.ArgumentParser(description="AI浪潮产业链标的池更新检查器 (Phase 0)")
    parser.add_argument("--output", default="/tmp/aiwave_universe_update.json")
    parser.add_argument("--silent", action="store_true", help="无新标的时静默")
    parser.add_argument("--verify-all", action="store_true", help="重新验证所有候选（含已跳过）")
    args = parser.parse_args()

    total_current = len(CURRENT_HK) + len(CURRENT_ASHARE) + len(CURRENT_US)

    print("🔍 Phase 0: AI浪潮标的池更新检查")
    print(f"   当前追踪池: 港股 {len(CURRENT_HK)} + A股 {len(CURRENT_ASHARE)} + 美股 {len(CURRENT_US)} = {total_current} 家")

    all_current_codes = get_all_current_codes()

    # 筛选需要处理的候选
    candidates_to_check = [
        c for c in PENDING_CANDIDATES
        if (not c.get("skip") or args.verify_all)
        and c["code"] not in all_current_codes
    ]

    print(f"   候选池: {len(PENDING_CANDIDATES)} 条记录，待核查 {len(candidates_to_check)} 条")
    print()

    new_additions = []  # 可新增（行情可获取）
    not_yet_listed = []  # 未上市/行情不可用

    if candidates_to_check:
        print("  📡 验证候选标的行情...")
        for c in candidates_to_check:
            quote = verify_quote(c["tencent_code"])
            if quote:
                entry = {**c, "current_price": quote["price"], "change_pct": quote["change_pct"],
                         "verified_name": quote["name"], "verified": True}
                new_additions.append(entry)
                print(f"     ✅ {c['code']} {quote['name']} — {quote['price']} ({quote['change_pct']:+.2f}%)")
            else:
                entry = {**c, "verified": False}
                not_yet_listed.append(entry)
                print(f"     ⏳ {c['code']} {c['name']} — 行情不可用（未上市或代码有误）")
            time.sleep(0.2)
        print()

    # 输出结果
    output = {
        "check_date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "current_universe": {
            "hk": len(CURRENT_HK),
            "ashare": len(CURRENT_ASHARE),
            "us": len(CURRENT_US),
            "total": total_current,
        },
        "pending_candidates_total": len(PENDING_CANDIDATES),
        "new_additions_available": len(new_additions),
        "not_yet_listed": len(not_yet_listed),
        "candidates_ready_to_add": new_additions,
        "candidates_not_yet_available": not_yet_listed,
        "has_updates": len(new_additions) > 0,
    }

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    if new_additions:
        print(f"🆕 发现 {len(new_additions)} 个可新增到追踪池的标的：")
        print()
        for c in new_additions:
            print(f"   [{c['market']}] {c['code']} {c.get('verified_name') or c['name']}")
            print(f"          板块: {c['sector']}  最新价: {c.get('current_price', 'N/A')}"
                  f"  涨跌幅: {c.get('change_pct', 0):+.2f}%")
            print(f"          发现原因: {c.get('reason', '-')}")
            print()

        print("💡 操作指引：")
        print("   1. 在 fetch_stock_data.py 的 STOCKS 对应市场列表中添加条目")
        print("   2. 在 check_universe_updates.py 的 CURRENT_HK/ASHARE/US 集合中添加代码")
        print("   3. 将上述候选条目的 skip 字段改为 True 或删除")
    elif not args.silent:
        print("✅ 标的池已是最新，候选池中无新增标的可纳入。")
        print()
        if not_yet_listed:
            print(f"⏳ {len(not_yet_listed)} 个候选标的行情暂不可用（待上市）：")
            for c in not_yet_listed:
                print(f"   [{c['market']}] {c['code']} {c['name']} — {c.get('reason', '')}")

    print()
    print(f"📝 检查报告已保存: {args.output}")

    return output


if __name__ == "__main__":
    main()
