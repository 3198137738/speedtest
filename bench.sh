#!/usr/bin/env bash
# bench.sh —— 服务器带宽压测一体化脚本（Linux/macOS）
#
# 子命令：
#   serve   在【被测服务器】上生成测试文件并起 HTTP 服务（提供下载源）
#   load    在【客户端】上并发下载，24h 不间断压测
#   all     本机既做源又做压测（单机自测/本地回环，验证工具用）
#
# ⚠️ 两端都必须是你自己拥有或已获授权的机器。全程流量只在你可控范围内。
#
# 用法示例：
#   在被测服务器：  ./bench.sh serve                      # 默认 2GiB 文件, 端口 8080
#                   ./bench.sh serve --size 4096 --port 9000
#   在客户端：      ./bench.sh load http://服务器IP:8080/testfile.bin
#                   ./bench.sh load http://服务器IP:8080/testfile.bin --conns 128 --rate 10
#   单机自测：      ./bench.sh all
set -euo pipefail
cd "$(dirname "$0")"

# ---------- 默认参数 ----------
FILE_NAME="testfile.bin"
SIZE_MB=2048          # 测试文件大小(MiB)，默认 2GiB
PORT=8080
CONNS=64
DURATION=86400        # 24h
RATE=10               # 目标 Gbps，0 为不限速

# ---------- 工具函数 ----------
die() { echo "错误: $*" >&2; exit 1; }

ensure_file() {
  local path="$1" size_mb="$2"
  local need_bytes=$(( size_mb * 1024 * 1024 ))
  if [[ -f "$path" ]]; then
    local have
    have=$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null || echo 0)
    if [[ "$have" == "$need_bytes" ]]; then
      echo "测试文件已存在且大小正确: $path ($size_mb MiB)"
      return
    fi
  fi
  echo "生成测试文件: $path (${size_mb} MiB) ..."
  if command -v fallocate >/dev/null 2>&1; then
    fallocate -l "${size_mb}MiB" "$path"
  else
    dd if=/dev/zero of="$path" bs=1048576 count="$size_mb" status=progress
  fi
}

setup_venv() {
  if [[ ! -d .venv ]]; then
    python3 -m venv .venv
  fi
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install -q --disable-pip-version-check -r requirements.txt
}

# ---------- 子命令实现 ----------
cmd_serve() {
  local dir="${SERVE_DIR:-.}"
  mkdir -p "$dir"
  ensure_file "$dir/$FILE_NAME" "$SIZE_MB"
  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "<本机IP>")
  echo "------------------------------------------------------------"
  echo "HTTP 下载源已就绪，监听端口 $PORT，目录 $dir"
  echo "客户端请用此 URL 压测："
  echo "    http://${ip}:${PORT}/${FILE_NAME}"
  echo "（按 Ctrl+C 停止服务）"
  echo "------------------------------------------------------------"
  # 用 python 自带 http.server 提供下载；--directory 指定根目录
  exec python3 -m http.server "$PORT" --directory "$dir"
}

cmd_load() {
  local url="${1:-}"
  [[ -n "$url" ]] || die "load 需要目标 URL，例如: ./bench.sh load http://服务器IP:8080/testfile.bin"
  setup_venv
  ulimit -n 1048576 2>/dev/null || true
  echo "开始压测 -> $url  并发=$CONNS 时长=${DURATION}s 目标=${RATE}Gbps"
  exec python3 speedtest.py "$url" -c "$CONNS" -d "$DURATION" -r "$RATE"
}

cmd_all() {
  # 本机自测：后台起源，前台跑压测，结束时清理
  mkdir -p .serve_tmp
  ensure_file ".serve_tmp/$FILE_NAME" "$SIZE_MB"
  setup_venv
  echo "启动本地下载源(端口 $PORT) ..."
  python3 -m http.server "$PORT" --directory .serve_tmp >/dev/null 2>&1 &
  local server_pid=$!
  trap 'kill "$server_pid" 2>/dev/null || true' EXIT
  sleep 1
  ulimit -n 1048576 2>/dev/null || true
  local url="http://127.0.0.1:${PORT}/${FILE_NAME}"
  echo "开始本机自测 -> $url  并发=$CONNS 时长=${DURATION}s 目标=${RATE}Gbps"
  python3 speedtest.py "$url" -c "$CONNS" -d "$DURATION" -r "$RATE"
}

usage() {
  sed -n '2,25p' "$0"
  exit 1
}

# ---------- 参数解析 ----------
[[ $# -ge 1 ]] || usage
SUB="$1"; shift || true

# 位置参数(URL)与可选项混合解析
URL_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --size)     SIZE_MB="$2"; shift 2 ;;
    --port)     PORT="$2"; shift 2 ;;
    --conns|-c) CONNS="$2"; shift 2 ;;
    --duration|-d) DURATION="$2"; shift 2 ;;
    --rate|-r)  RATE="$2"; shift 2 ;;
    --dir)      SERVE_DIR="$2"; shift 2 ;;
    -h|--help)  usage ;;
    -*)         die "未知选项: $1" ;;
    *)          URL_ARG="$1"; shift ;;
  esac
done

case "$SUB" in
  serve) cmd_serve ;;
  load)  cmd_load "$URL_ARG" ;;
  all)   cmd_all ;;
  *)     usage ;;
esac
