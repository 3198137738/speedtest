#!/usr/bin/env bash
# 一键压测脚本（Linux/macOS）
# 用法：  ./run.sh <目标URL> [并发数] [时长秒] [目标Gbps]
# 示例：  ./run.sh https://your-server.example.com/testfile.bin
#         ./run.sh https://your-server.example.com/testfile.bin 128 86400 10
#
# ⚠️ 仅对你自己拥有或已获授权测试的服务器运行。
set -euo pipefail
cd "$(dirname "$0")"

URL="${1:-}"
CONNS="${2:-64}"
DURATION="${3:-86400}"   # 默认 24h
RATE="${4:-10}"          # 默认 10 Gbps，设 0 为不限速

if [[ -z "$URL" ]]; then
  echo "用法: $0 <目标URL> [并发数=64] [时长秒=86400] [目标Gbps=10]"
  exit 1
fi

# 准备虚拟环境与依赖
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
pip install -q --disable-pip-version-check -r requirements.txt

# 尽量放宽文件描述符上限（高并发需要）
ulimit -n 1048576 2>/dev/null || true

echo "开始压测 -> $URL  并发=$CONNS 时长=${DURATION}s 目标=${RATE}Gbps"
exec python3 speedtest.py "$URL" -c "$CONNS" -d "$DURATION" -r "$RATE"
