#!/usr/bin/env python3
"""
AI浪潮产业链 — 多市场行情数据获取器
获取港股/A股/美股核心AI产业链标的的实时/收盘行情
用法: python3 fetch_stock_data.py --output /tmp/aiwave_stock.json
"""

import json
import time
import argparse
import requests
from datetime import datetime
from pathlib import Path

# ─── 标的清单 ───────────────────────────────────────────────────────────────
# 腾讯财经行情代码格式：
#   港股: hk{code}  (如 hk00981)
#   A股:  sz{code}(深) / sh{code}(沪/科创)
#   美股: us{code}  (如 usNVDA)

STOCKS = {
    "hk": [
        # (腾讯代码, 标准代码, 中文名, 板块, 等级)
        ("hk00981", "00981", "中芯国际", "先进代工", 1),
        ("hk09988", "09988", "阿里巴巴", "云/AI平台", 1),
        ("hk00992", "00992", "联想集团", "AI服务器", 1),
        ("hk00700", "00700", "腾讯控股", "云/AI平台", 1),
        ("hk09888", "09888", "百度集团", "云/AI平台", 2),
        ("hk09903", "09903", "天数智芯", "AI GPU", 2),
        ("hk00763", "00763", "中兴通讯", "AI网络", 2),
        ("hk01347", "01347", "华虹半导体", "代工", 2),
        ("hk01810", "01810", "小米集团", "AI终端", 2),
        ("hk02382", "02382", "舜宇光学", "光学组件", 2),
        ("hk00020", "00020", "商汤科技", "AI软件", 3),
        ("hk06060", "06060", "旷视科技", "AI软件", 3),
    ],
    "ashare": [
        # 科创板/创业板/深交所/上交所
        # ── AI芯片/算力 ──
        ("sh688256", "688256", "寒武纪", "AI芯片"),
        ("sh688041", "688041", "海光信息", "AI芯片"),
        ("sh688047", "688047", "龙芯中科", "AI芯片"),
        ("sh603828", "603828", "澜起科技", "HBM接口"),
        ("sz301269", "301269", "华大九天", "EDA"),
        # ── 光模块/光器件 ──
        ("sz300308", "300308", "中际旭创", "光模块"),
        ("sz300394", "300394", "天孚通信", "光器件"),
        ("sz300502", "300502", "新易盛", "光模块"),
        ("sz000988", "000988", "华工科技", "光模块"),
        ("sz002281", "002281", "光迅科技", "光器件"),
        # ── AI服务器 ──
        ("sz000977", "000977", "浪潮信息", "AI服务器"),
        ("sh601138", "601138", "工业富联", "AI服务器"),
        ("sh603019", "603019", "中科曙光", "AI服务器"),
        # ── 存储 ──
        ("sz603986", "603986", "兆易创新", "存储芯片"),
        ("sz300223", "300223", "北京君正", "存储芯片"),
        # ── 半导体设备 ──
        ("sz002371", "002371", "北方华创", "半导体设备"),
        ("sh688012", "688012", "中微公司", "半导体设备"),
        ("sh688072", "688072", "拓荆科技", "半导体设备"),
        # ── 半导体材料 ──
        ("sz002318", "002318", "雅克科技", "半导体材料"),
        ("sh688188", "688188", "南大光电", "半导体材料"),
        ("sz002106", "002106", "鼎龙股份", "半导体材料"),
        ("sh603989", "603989", "江化微", "半导体材料"),
        # ── 先进封装 ──
        ("sh601986", "601986", "长电科技", "先进封装"),
        ("sz002156", "002156", "通富微电", "先进封装"),
        ("sz002185", "002185", "华天科技", "先进封装"),
        # ── 网络互连 ──
        ("sz301165", "301165", "锐捷网络", "网络互连"),
        # ── 电源/散热 ──
        ("sz002334", "002334", "英威腾", "电源/散热"),
        ("sz301018", "301018", "申菱环境", "电源/散热"),
        # ── AI应用 ──
        ("sz002230", "002230", "科大讯飞", "AI应用"),
        ("sz300418", "300418", "昆仑万维", "AI应用"),
    ],
    "us": [
        # ── AI GPU/算力 ──
        ("usNVDA", "NVDA", "英伟达", "AI GPU"),
        ("usAMD", "AMD", "超微半导体", "AI GPU"),
        ("usAVGO", "AVGO", "博通", "ASIC/网络"),
        ("usMRVL", "MRVL", "迈威尔", "光DSP"),
        ("usCOHR", "COHR", "科锐", "光模块"),
        ("usSMCI", "SMCI", "超微电脑", "AI服务器"),
        ("usARM", "ARM", "Arm", "CPU IP"),
        ("usSNPS", "SNPS", "新思科技", "EDA"),
        ("usASML", "ASML", "阿斯麦", "光刻机"),
        ("usMSFT", "MSFT", "微软", "云/AI平台"),
        # ── 存储 ──
        ("usMU", "MU", "美光科技", "存储/HBM"),
        # ── 半导体设备 ──
        ("usAMAT", "AMAT", "应用材料", "半导体设备"),
        ("usLRCX", "LRCX", "科林研发", "半导体设备"),
        ("usKLAC", "KLAC", "科磊", "半导体设备"),
        # ── 先进封装/代工 ──
        ("usTSM", "TSM", "台积电", "先进封装/代工"),
        # ── 网络互连 ──
        ("usCSCO", "CSCO", "思科", "网络互连"),
        # ── 电源/散热 ──
        ("usVRT", "VRT", "维谛技术", "电源/散热"),
        # ── AI应用 ──
        ("usGOOG", "GOOG", "谷歌", "AI应用/云"),
        ("usMETA", "META", "Meta", "AI应用/社交"),
    ]
}

def fetch_tencent_quotes(codes: list[str]) -> dict:
    """从腾讯财经批量获取行情数据"""
    url = "https://qt.gtimg.cn/q=" + ",".join(codes)
    headers = {
        "Referer": "https://finance.qq.com",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    }

    result = {}
    try:
        resp = requests.get(url, headers=headers, timeout=15)
        resp.encoding = "gbk"

        for line in resp.text.strip().split(";"):
            line = line.strip()
            if not line or "v_" not in line:
                continue
            try:
                key_part = line.split("=")[0].strip()
                val_part = line.split('"')[1] if '"' in line else ""
                code = key_part.replace("v_", "")
                fields = val_part.split("~")

                if len(fields) < 45:
                    continue

                name = fields[1]
                price = float(fields[3]) if fields[3] else 0
                prev_close = float(fields[4]) if fields[4] else 0
                open_price = float(fields[5]) if fields[5] else 0
                high = float(fields[33]) if fields[33] else 0
                low = float(fields[34]) if fields[34] else 0
                volume = int(fields[6]) if fields[6] else 0
                amount = float(fields[37]) if fields[37] else 0
                change = price - prev_close if prev_close > 0 else 0
                change_pct = (change / prev_close * 100) if prev_close > 0 else 0

                result[code] = {
                    "name": name,
                    "price": round(price, 3),
                    "prev_close": round(prev_close, 3),
                    "open": round(open_price, 3),
                    "high": round(high, 3),
                    "low": round(low, 3),
                    "change": round(change, 3),
                    "change_pct": round(change_pct, 2),
                    "volume": volume,
                    "amount": round(amount, 0),
                }
            except (IndexError, ValueError):
                continue

    except Exception as e:
        print(f"  ⚠️ 腾讯行情接口异常: {e}")

    return result

def build_stock_list(market: str, stocks: list, quotes: dict) -> list:
    """构建标的数据列表"""
    result = []
    for item in stocks:
        tencent_code = item[0]
        std_code = item[1]
        name = item[2]
        sector = item[3]
        tier = item[4] if len(item) > 4 else 0

        quote = quotes.get(tencent_code, {})

        entry = {
            "code": std_code,
            "tencent_code": tencent_code,
            "name": name,
            "market": market,
            "sector": sector,
            "price": quote.get("price", 0),
            "prev_close": quote.get("prev_close", 0),
            "change_pct": quote.get("change_pct", 0),
            "high": quote.get("high", 0),
            "low": quote.get("low", 0),
            "volume": quote.get("volume", 0),
            "data_available": bool(quote),
        }
        if tier:
            entry["tier"] = tier

        result.append(entry)
    return result

def get_market_status() -> str:
    """判断当前市场状态"""
    now = datetime.now()
    hour = now.hour
    minute = now.minute
    weekday = now.weekday()  # 0=Monday

    status_parts = []

    if weekday >= 5:
        return "周末休市"

    # A股: 9:30-15:00
    if (hour == 9 and minute >= 30) or (10 <= hour <= 14) or (hour == 15 and minute == 0):
        status_parts.append("A股交易中")
    elif hour < 9 or (hour == 9 and minute < 30):
        status_parts.append("A股待开盘")
    else:
        status_parts.append("A股已收盘")

    # 港股: 9:30-16:00
    if (hour == 9 and minute >= 30) or (10 <= hour <= 15) or (hour == 16 and minute == 0):
        status_parts.append("港股交易中")
    else:
        status_parts.append("港股已收盘")

    # 美股: 21:30-04:00 (北京时间，冬令时22:30-05:00)
    if hour >= 21 or hour < 4:
        status_parts.append("美股交易中")
    else:
        status_parts.append("美股盘外")

    return " | ".join(status_parts)

def main():
    parser = argparse.ArgumentParser(description="AI浪潮产业链行情数据获取器")
    parser.add_argument("--output", default="/tmp/aiwave_stock.json", help="输出JSON文件路径")
    args = parser.parse_args()

    print("🌊 AI浪潮产业链 — 行情数据获取")
    print(f"   时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"   输出: {args.output}")
    print()

    # 收集所有腾讯代码
    all_codes = []
    for market_stocks in STOCKS.values():
        all_codes.extend([s[0] for s in market_stocks])

    # 分批获取（腾讯接口单次上限约40个）
    batch_size = 30
    all_quotes = {}

    for i in range(0, len(all_codes), batch_size):
        batch = all_codes[i:i + batch_size]
        print(f"  📡 获取行情批次 {i//batch_size + 1}（{len(batch)} 个标的）...")
        quotes = fetch_tencent_quotes(batch)
        all_quotes.update(quotes)
        if i + batch_size < len(all_codes):
            time.sleep(0.5)

    success = sum(1 for k in all_codes if k in all_quotes)
    print(f"  ✅ 成功获取 {success}/{len(all_codes)} 个标的行情")
    print()

    # 构建输出数据
    output = {
        "report_date": datetime.now().strftime("%Y-%m-%d"),
        "fetch_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "market_status": get_market_status(),
        "total_companies": len(all_codes),
        "data_success_count": success,
        "hk_stocks": build_stock_list("港股", STOCKS["hk"], all_quotes),
        "ashare_stocks": build_stock_list("A股", STOCKS["ashare"], all_quotes),
        "us_stocks": build_stock_list("美股", STOCKS["us"], all_quotes),
    }

    # 统计涨跌概况
    all_stocks = output["hk_stocks"] + output["ashare_stocks"] + output["us_stocks"]
    with_data = [s for s in all_stocks if s["data_available"] and s["change_pct"] != 0]
    gainers = [s for s in with_data if s["change_pct"] > 0]
    losers = [s for s in with_data if s["change_pct"] < 0]

    output["market_breadth"] = {
        "gainers": len(gainers),
        "losers": len(losers),
        "unchanged": len(with_data) - len(gainers) - len(losers),
        "top_gainer": max(with_data, key=lambda x: x["change_pct"], default={}).get("name", "N/A"),
        "top_gainer_pct": max((s["change_pct"] for s in with_data), default=0),
        "top_loser": min(with_data, key=lambda x: x["change_pct"], default={}).get("name", "N/A"),
        "top_loser_pct": min((s["change_pct"] for s in with_data), default=0),
    }

    # 写入文件
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"📊 市场概况:")
    print(f"   上涨: {output['market_breadth']['gainers']} 家")
    print(f"   下跌: {output['market_breadth']['losers']} 家")
    if with_data:
        print(f"   最强: {output['market_breadth']['top_gainer']} ({output['market_breadth']['top_gainer_pct']:+.2f}%)")
        print(f"   最弱: {output['market_breadth']['top_loser']} ({output['market_breadth']['top_loser_pct']:+.2f}%)")
    print()
    print(f"✅ 数据已保存到: {args.output}")


if __name__ == "__main__":
    main()
