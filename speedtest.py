#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
speedtest.py —— 服务器带宽/吞吐量压测工具

用途：针对【你自己拥有或已获明确授权测试】的服务器，建立多路并发 HTTP(S)
下载连接，持续拉取指定文件，用来测量/压满服务器与链路的吞吐能力。

特性：
  - 多连接并发，尽量压满 10Gbps 级链路
  - 下载数据流式丢弃，不落盘（避免磁盘成为瓶颈）
  - 实时打印即时速率、平均速率、累计流量
  - 可限制总时长（默认 24 小时）或无限循环
  - 可设定目标总速率（令牌桶限速，避免跑飞）
  - 单个连接下载完整个文件后自动重连，循环不止

⚠️ 仅用于授权测试。请勿对未授权的第三方服务器长时间满速拉流。
"""

import argparse
import asyncio
import signal
import sys
import time

try:
    import aiohttp
except ImportError:
    sys.exit("缺少依赖 aiohttp，请先执行：pip install aiohttp")


class Stats:
    """全局统计：累计字节数 + 滑动窗口即时速率。"""

    def __init__(self):
        self.total_bytes = 0
        self.start = time.monotonic()
        self._win_bytes = 0
        self._win_start = self.start

    def add(self, n: int):
        self.total_bytes += n
        self._win_bytes += n

    def snapshot(self):
        now = time.monotonic()
        win_dt = max(now - self._win_start, 1e-9)
        inst = self._win_bytes / win_dt           # 窗口即时速率 B/s
        avg = self.total_bytes / max(now - self.start, 1e-9)
        self._win_bytes = 0
        self._win_start = now
        return inst, avg, self.total_bytes, now - self.start


class RateLimiter:
    """简单令牌桶，按字节限速；rate<=0 表示不限速。"""

    def __init__(self, rate_bytes_per_s: float):
        self.rate = rate_bytes_per_s
        self.allowance = rate_bytes_per_s
        self.last = time.monotonic()
        self.lock = asyncio.Lock()

    async def consume(self, n: int):
        if self.rate <= 0:
            return
        async with self.lock:
            now = time.monotonic()
            self.allowance += (now - self.last) * self.rate
            self.last = now
            if self.allowance > self.rate:
                self.allowance = self.rate
            if self.allowance < n:
                deficit = n - self.allowance
                wait = deficit / self.rate
                self.allowance = 0
                await asyncio.sleep(wait)
            else:
                self.allowance -= n


async def worker(idx, url, stats, limiter, stop_evt, chunk_size, timeout, verify_ssl):
    """单个下载协程：循环拉取 url，流式丢弃数据。"""
    sess_timeout = aiohttp.ClientTimeout(total=None, sock_connect=timeout, sock_read=timeout)
    connector = aiohttp.TCPConnector(ssl=verify_ssl, limit=0)
    async with aiohttp.ClientSession(timeout=sess_timeout, connector=connector) as session:
        while not stop_evt.is_set():
            try:
                async with session.get(url) as resp:
                    if resp.status >= 400:
                        await asyncio.sleep(1)
                        continue
                    async for chunk in resp.content.iter_chunked(chunk_size):
                        if stop_evt.is_set():
                            break
                        stats.add(len(chunk))
                        await limiter.consume(len(chunk))
            except asyncio.CancelledError:
                raise
            except Exception:
                # 连接出错时短暂退避后重连，保证 24h 持续运行
                if not stop_evt.is_set():
                    await asyncio.sleep(0.5)


def human(bps: float) -> str:
    """B/s -> 人类可读（bit 口径，网络习惯用 bps）。"""
    bits = bps * 8
    for unit in ("bps", "Kbps", "Mbps", "Gbps", "Tbps"):
        if bits < 1000:
            return f"{bits:6.2f} {unit}"
        bits /= 1000
    return f"{bits:.2f} Pbps"


def human_bytes(n: float) -> str:
    for unit in ("B", "KiB", "MiB", "GiB", "TiB", "PiB"):
        if n < 1024:
            return f"{n:6.2f} {unit}"
        n /= 1024
    return f"{n:.2f} EiB"


async def reporter(stats, stop_evt, interval):
    while not stop_evt.is_set():
        await asyncio.sleep(interval)
        inst, avg, total, elapsed = stats.snapshot()
        print(
            f"[{int(elapsed):>7}s] 即时 {human(inst)} | 平均 {human(avg)} | "
            f"累计 {human_bytes(total)}",
            flush=True,
        )


async def probe_best_connections(args, verify_ssl):
    """自动探测最佳并发：逐级(8→16→…)各跑 probe 秒，测平均吞吐，
    当再翻倍提升 < 10% 或达上限时停止，返回吞吐最高的并发数。"""
    levels = [8, 16, 32, 64, 128, 256, 512]
    levels = [n for n in levels if n <= args.max_connections]
    if not levels:
        levels = [args.max_connections]
    print(f"自动探测并发中（每档 {args.probe}s，不限速）...", flush=True)
    best_bps, best_n, prev_bps = 0.0, levels[0], 0.0
    for n in levels:
        stats = Stats()
        stop_evt = asyncio.Event()
        limiter = RateLimiter(0)
        tasks = [
            asyncio.create_task(
                worker(i, args.url, stats, limiter, stop_evt,
                       args.chunk, args.timeout, verify_ssl)
            )
            for i in range(n)
        ]
        await asyncio.sleep(args.probe)
        stop_evt.set()
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        _, avg, _, _ = stats.snapshot()
        print(f"  并发 {n:>4} -> {human(avg)}", flush=True)
        if avg > best_bps:
            best_bps, best_n = avg, n
        # 再翻倍提升不足 10%，认为已到拐点，停止探测
        if prev_bps > 0 and avg < prev_bps * 1.10:
            break
        prev_bps = avg
    print(f"选定并发：{best_n}（探测峰值 {human(best_bps)}）", flush=True)
    return best_n


async def main_async(args):
    verify_ssl = not args.insecure

    # 自动探测并发（--auto）：覆盖 -c
    if args.auto:
        args.connections = await probe_best_connections(args, verify_ssl)

    stats = Stats()
    stop_evt = asyncio.Event()

    # 目标总速率（Gbps）-> 字节/秒
    rate_bps = args.rate * 1e9 / 8 if args.rate > 0 else 0
    limiter = RateLimiter(rate_bps)

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop_evt.set)
        except NotImplementedError:
            pass  # Windows 下部分信号不支持

    print(f"目标 URL   : {args.url}")
    print(f"并发连接   : {args.connections}")
    print(f"目标速率   : {'不限速' if args.rate <= 0 else str(args.rate) + ' Gbps'}")
    print(f"运行时长   : {'无限' if args.duration <= 0 else str(args.duration) + ' 秒'}")
    print(f"数据块大小 : {args.chunk} 字节")
    print("-" * 60, flush=True)

    tasks = [
        asyncio.create_task(
            worker(i, args.url, stats, limiter, stop_evt,
                   args.chunk, args.timeout, verify_ssl)
        )
        for i in range(args.connections)
    ]
    tasks.append(asyncio.create_task(reporter(stats, stop_evt, args.interval)))

    if args.duration > 0:
        try:
            await asyncio.wait_for(stop_evt.wait(), timeout=args.duration)
        except asyncio.TimeoutError:
            stop_evt.set()
    else:
        await stop_evt.wait()

    stop_evt.set()
    for t in tasks:
        t.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)

    _, avg, total, elapsed = stats.snapshot()
    print("-" * 60)
    print(f"结束：运行 {int(elapsed)} 秒，累计 {human_bytes(total)}，平均 {human(avg)}")


def parse_args():
    p = argparse.ArgumentParser(
        description="服务器带宽/吞吐量压测工具（仅限授权测试）"
    )
    p.add_argument("url", help="被测文件的 HTTP(S) URL（需为你有权测试的服务器）")
    p.add_argument("-c", "--connections", type=int, default=64,
                   help="并发连接数，默认 64（10Gbps 建议 32~256）")
    p.add_argument("--auto", action="store_true",
                   help="自动探测最佳并发（忽略 -c）")
    p.add_argument("--max-connections", type=int, default=256,
                   help="自动探测时的并发上限，默认 256")
    p.add_argument("--probe", type=float, default=5.0,
                   help="自动探测每档持续秒数，默认 5")
    p.add_argument("-d", "--duration", type=int, default=0,
                   help="运行秒数，默认 0=不间断；如需 24h 填 86400")
    p.add_argument("-r", "--rate", type=float, default=0.0,
                   help="目标总速率 Gbps，默认 0=不限速；如需限速填如 10")
    p.add_argument("--chunk", type=int, default=1 << 20,
                   help="每次读取字节数，默认 1048576(1MiB)")
    p.add_argument("-i", "--interval", type=float, default=2.0,
                   help="统计打印间隔秒，默认 2")
    p.add_argument("--timeout", type=float, default=30.0,
                   help="socket 连接/读取超时秒，默认 30")
    p.add_argument("--insecure", action="store_true",
                   help="跳过 TLS 证书校验")
    return p.parse_args()


if __name__ == "__main__":
    try:
        asyncio.run(main_async(parse_args()))
    except KeyboardInterrupt:
        pass
