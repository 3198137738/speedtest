# speedtest —— 服务器带宽 / 吞吐量压测工具

针对**你自己拥有或已获明确授权测试**的服务器，建立多路并发 HTTP(S) 下载连接，
持续拉取指定文件，用来测量 / 压满服务器与链路的吞吐能力。可用于验证服务器是否
能在较长时间（如 24 小时）内稳定承载 10Gbps 级的出口流量。

## ⚠️ 使用授权声明

本工具会产生**大量持续的下载流量**。你**只能**把它指向：

- 你自己拥有的服务器；或
- 你已获得书面 / 明确授权进行压力测试的服务器。

严禁用于未授权的第三方目标。对他人服务器长时间满速拉流等同于流量攻击，可能
违反法律并造成真实损害。使用者自行承担全部责任。

此外请注意：从服务器下载会消耗其**出口带宽**，云服务商通常**按流量计费**，
24 小时 × 10Gbps ≈ 108 TB/天，可能产生高额费用，务必评估后再运行。

## 原理

- 启动 N 个并发协程，各自循环 `GET` 同一个 URL，下载的数据**流式丢弃**（不落盘，
  避免磁盘成为瓶颈）；
- 单连接下完整个文件后自动重连，保证持续不断；
- 可选令牌桶限速，把总速率控制在目标值（默认 10Gbps），避免无意义跑飞；
- 实时打印即时速率 / 平均速率 / 累计流量。

## 准备被测文件

在被测服务器上放一个足够大的文件（建议 ≥ 1GiB，减少重连开销），用任意 HTTP
服务暴露，例如：

```bash
# 在被测服务器上
dd if=/dev/zero of=/var/www/html/testfile.bin bs=1M count=2048   # 生成 2GiB
# 用 nginx / caddy / python -m http.server 等方式提供下载
```

## 一键运行

### Linux / macOS

```bash
chmod +x run.sh
./run.sh https://your-server.example.com/testfile.bin
# 自定义：并发128、跑24h、目标10Gbps
./run.sh https://your-server.example.com/testfile.bin 128 86400 10
```

### Windows (PowerShell)

```powershell
.\run.ps1 -Url https://your-server.example.com/testfile.bin
.\run.ps1 -Url https://your-server.example.com/testfile.bin -Conns 128 -Duration 86400 -Rate 10
```

脚本会自动创建 Python 虚拟环境、安装依赖并开始压测。

## 直接用 Python

```bash
pip install -r requirements.txt
python3 speedtest.py <URL> [选项]
```

### 常用选项

| 选项 | 说明 | 默认 |
|------|------|------|
| `-c, --connections` | 并发连接数（10Gbps 建议 32~256） | 64 |
| `-d, --duration` | 运行秒数，`0` 为无限循环 | 86400 (24h) |
| `-r, --rate` | 目标总速率 Gbps，`0` 为不限速 | 10 |
| `--chunk` | 每次读取字节数 | 1048576 (1MiB) |
| `-i, --interval` | 统计打印间隔秒 | 2 |
| `--timeout` | socket 连接 / 读取超时秒 | 30 |
| `--insecure` | 跳过 TLS 证书校验 | 否 |

示例：无限循环、不限速、128 并发：

```bash
python3 speedtest.py https://your-server.example.com/testfile.bin -c 128 -d 0 -r 0
```

## 跑满 10Gbps 的建议

- **连接数**：单连接受 TCP 窗口 / RTT 限制，往往跑不满万兆，务必用几十到上百并发；
- **客户端**：运行本工具的机器自身网卡 / CPU / 到服务器的链路必须 ≥ 10Gbps，
  否则瓶颈在客户端而非被测服务器；
- **文件要大**：小文件会让重连 / TLS 握手占比过高，拉低有效吞吐；
- **放宽 fd 上限**：`ulimit -n`（`run.sh` 已尝试自动调高）；
- **就近部署**：客户端与服务器同区域 / 低 RTT，才容易打满带宽。

## 后台长跑（24h）

```bash
# Linux：用 nohup 后台跑并记录日志
nohup ./run.sh https://your-server.example.com/testfile.bin > speedtest.log 2>&1 &
tail -f speedtest.log
```

按 `Ctrl+C` 可随时优雅停止。
