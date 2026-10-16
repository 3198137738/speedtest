#!/usr/bin/env bash
# oneclick.sh —— 最终一键脚本（Linux）
#
# 一条命令完成：装依赖 → 自动探测最佳并发 → 不限速 → 不间断 →
#              注册 systemd 后台服务 + 开机自启 → 跟随实时统计
# 无 systemd 的环境（容器等）自动退化为前台运行。
#
# 用法：
#   sudo ./oneclick.sh <目标URL> [时长秒]
#     <目标URL>  指向【你自己服务器】上的大文件（可先 `./bench.sh serve` 起源）
#     [时长秒]   可选，默认 0=不间断；只跑 24h 填 86400
#
#   卸载：  sudo ./oneclick.sh --uninstall
#
# ⚠️ 目标必须是你自己拥有或已获授权测试的服务器；勿将公共测速端点
#    （如 proof.ovh.net 等第三方）设为不间断源——属流量滥用，且测不到你的服务器。
set -euo pipefail
cd "$(dirname "$0")"
SERVICE="speedtest"

# ---- 卸载 ----
if [[ "${1:-}" == "--uninstall" ]]; then
  exec ./install-systemd.sh --uninstall
fi

URL="${1:-}"
DURATION="${2:-0}"
if [[ -z "$URL" ]]; then
  cat <<'EOF'
用法: sudo ./oneclick.sh <目标URL> [时长秒=0]

还没有下载源？先在【被测服务器】上执行：
    ./bench.sh serve --size 10240       # 生成 10GiB 文件并起 HTTP 源
它会打印一个形如 http://服务器IP:8080/testfile.bin 的 URL，
再把该 URL 传给本脚本即可。
EOF
  exit 1
fi

# ---- 有 systemd 且有 root：注册后台服务（推荐）----
if command -v systemctl >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
  ./install-systemd.sh "$URL" "$DURATION"
  systemctl enable "$SERVICE" >/dev/null 2>&1 || true
  systemctl restart "$SERVICE"
  echo
  echo ">>> 服务已启动并设为开机自启。以下为实时统计（Ctrl+C 退出查看，服务继续后台运行）："
  echo
  exec journalctl -u "$SERVICE" -f -n 20
fi

# ---- 无 systemd 或非 root：前台直接跑 ----
echo "未检测到 systemd/root 权限，改为前台运行（Ctrl+C 停止）。"
if [[ ! -d .venv ]]; then python3 -m venv .venv; fi
# shellcheck disable=SC1091
source .venv/bin/activate
pip install -q --disable-pip-version-check -r requirements.txt
ulimit -n 1048576 2>/dev/null || true
exec python3 speedtest.py "$URL" --auto -r 0 -d "$DURATION" -i 5
