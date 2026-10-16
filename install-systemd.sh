#!/usr/bin/env bash
# install-systemd.sh —— 把压测注册为 systemd 后台服务（不间断 + 不限速 + 自动探测并发）
#
# 用法：
#   sudo ./install-systemd.sh <目标URL> [时长秒]
#     <目标URL>  必填，指向【你自己的服务器】上的大文件下载地址
#                （可先在被测服务器上 `./bench.sh serve` 起一个源）
#     [时长秒]    可选，默认 0=不间断；如只想跑 24h 填 86400
#
# 安装后：
#   启动   : sudo systemctl start  speedtest
#   开机自启: sudo systemctl enable speedtest
#   看实时 : journalctl -u speedtest -f
#   停止   : sudo systemctl stop   speedtest
#   卸载   : sudo ./install-systemd.sh --uninstall
#
# ⚠️ 目标必须是你自己拥有或已获授权测试的服务器。请勿把公共测速端点
#    （如 proof.ovh.net 等第三方）设为 24h 不间断的下载源——那是流量滥用。
set -euo pipefail

SERVICE="speedtest"
UNIT="/etc/systemd/system/${SERVICE}.service"
WORKDIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "${1:-}" == "--uninstall" ]]; then
  systemctl stop "$SERVICE" 2>/dev/null || true
  systemctl disable "$SERVICE" 2>/dev/null || true
  rm -f "$UNIT"
  systemctl daemon-reload
  echo "已卸载 $SERVICE 服务。"
  exit 0
fi

URL="${1:-}"
DURATION="${2:-0}"   # 0 = 不间断
[[ -n "$URL" ]] || { echo "用法: sudo $0 <目标URL> [时长秒=0]"; exit 1; }
[[ $EUID -eq 0 ]] || { echo "请用 sudo 运行。"; exit 1; }

# 识别真正的调用用户（非 root），避免服务以 root 身份跑
RUN_USER="${SUDO_USER:-root}"

# 准备 venv 与依赖（装到仓库目录，服务直接用解释器绝对路径）
if [[ ! -d "$WORKDIR/.venv" ]]; then
  sudo -u "$RUN_USER" python3 -m venv "$WORKDIR/.venv"
fi
sudo -u "$RUN_USER" "$WORKDIR/.venv/bin/pip" install -q --disable-pip-version-check -r "$WORKDIR/requirements.txt"
PY="$WORKDIR/.venv/bin/python"

echo "生成 systemd 单元: $UNIT"
cat > "$UNIT" <<EOF
[Unit]
Description=speedtest 带宽压测（自动探测并发 + 不限速 + 实时统计）
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${WORKDIR}
# --auto 自动探测并发；-r 0 不限速；-d ${DURATION} (0=不间断)
ExecStart=${PY} ${WORKDIR}/speedtest.py ${URL} --auto -r 0 -d ${DURATION} -i 5
# 高并发需要大量文件描述符
LimitNOFILE=1048576
# 崩溃/网络抖动后自动拉起，保证长期不间断
Restart=on-failure
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
echo "------------------------------------------------------------"
echo "已安装服务 ${SERVICE}。目标 URL: ${URL}"
echo "时长: $([[ "$DURATION" == "0" ]] && echo '不间断' || echo "${DURATION}s")"
echo
echo "现在启动:   sudo systemctl start  ${SERVICE}"
echo "开机自启:   sudo systemctl enable ${SERVICE}"
echo "实时统计:   journalctl -u ${SERVICE} -f"
echo "停止服务:   sudo systemctl stop   ${SERVICE}"
echo "------------------------------------------------------------"
