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

## ✅ 最终一键脚本 `oneclick.sh`

从零到后台跑起来，**一条命令**搞定：装依赖 → 自动探测最佳并发 → 不限速 →
不间断 → 注册 systemd 后台 + 开机自启 → 跟随实时统计。

```bash
# 克隆
git clone https://github.com/3198137738/speedtest.git && cd speedtest

# ① 被测服务器：起下载源（生成大文件 + HTTP，打印出一个 URL）
./bench.sh serve --size 10240            # 10GiB

# ② 客户端：把上一步的 URL 传进来，一键启动后台压测
sudo ./oneclick.sh http://你的服务器IP:8080/testfile.bin
#    只想跑 24h：  sudo ./oneclick.sh http://...  86400
#    卸载服务：    sudo ./oneclick.sh --uninstall
```

管理命令：

```bash
journalctl -u speedtest -f       # 实时统计
systemctl status speedtest       # 运行状态
systemctl stop   speedtest       # 停止
```

> 无 systemd / 非 root 的环境（如容器）会自动退化为**前台运行**。
> 目标 URL 必须是你自己的服务器；公共测速端点只适合几秒~几十秒的短时测速。

## 原理

- 启动 N 个并发协程，各自循环 `GET` 同一个 URL，下载的数据**流式丢弃**（不落盘，
  避免磁盘成为瓶颈）；
- 单连接下完整个文件后自动重连，保证持续不断；
- 可选令牌桶限速，把总速率控制在目标值（默认 10Gbps），避免无意义跑飞；
- 实时打印即时速率 / 平均速率 / 累计流量。

## 🚀 systemd 后台一键版（不间断 + 不限速 + 自动探测并发 + 实时统计）

适合在 Linux 服务器上长期后台跑。**目标 URL 必须是你自己服务器上的大文件**，
可先在被测服务器用 `./bench.sh serve` 起一个下载源。

```bash
# ① 被测服务器：起下载源（生成大文件 + HTTP 服务，会打印一个 URL）
./bench.sh serve --size 10240            # 例：10GiB 文件

# ② 客户端：把该 URL 注册为 systemd 服务（自动探测并发、不限速、不间断）
sudo ./install-systemd.sh http://你的服务器IP:8080/testfile.bin
#    只想跑 24h 就退出：  sudo ./install-systemd.sh http://...  86400

sudo systemctl start  speedtest     # 启动
sudo systemctl enable speedtest     # 开机自启
journalctl -u speedtest -f          # 看实时统计（即时/平均速率、累计流量）
sudo systemctl stop   speedtest     # 停止
sudo ./install-systemd.sh --uninstall   # 卸载
```

服务特性：`--auto` 启动时自动探测最佳并发、`-r 0` 不限速、`-d 0` 不间断、
`Restart=on-failure` 崩溃/断网自动拉起、`LimitNOFILE=1048576` 放开 fd 上限。

> ⚠️ 不要把公共测速端点（如 `proof.ovh.net` 等第三方）设为 24h 不间断的下载源：
> 那会对第三方造成巨量带宽消耗、属于滥用，且测的也不是你自己的服务器。
> 公共测速文件只适合做**几秒~几十秒的短时测速**（例如下面的手动 `--auto` 探测）。

## 一体化脚本 `bench.sh` / `bench.ps1`（推荐）

把「服务器端生成文件 + 起 HTTP 服务」和「客户端压测」整合到一个脚本里，
两端都是你自己的机器，全程流量可控。三个子命令：

| 子命令 | 在哪台机器跑 | 作用 |
|--------|--------------|------|
| `serve` | 被测服务器 | 生成测试文件并起 HTTP 下载源 |
| `load`  | 客户端 | 并发下载，24h 不间断压测 |
| `all`   | 任意单机 | 本机既做源又压测（验证工具/单机自测） |

### Linux / macOS

```bash
chmod +x bench.sh

# ① 被测服务器：起下载源（默认 2GiB 文件、端口 8080）
./bench.sh serve
./bench.sh serve --size 4096 --port 9000          # 可选：4GiB、换端口

# ② 客户端：24h 压测（URL 用上一步打印出来的）
./bench.sh load http://服务器IP:8080/testfile.bin
./bench.sh load http://服务器IP:8080/testfile.bin --conns 128 --rate 10

# 单机自测（本地回环，先确认工具可用）
./bench.sh all
```

### Windows (PowerShell)

```powershell
.\bench.ps1 serve -Size 2048 -Port 8080
.\bench.ps1 load  -Url http://服务器IP:8080/testfile.bin -Conns 128 -Rate 10
.\bench.ps1 all
```

脚本会自动生成测试文件、创建 Python 虚拟环境并安装依赖。`bench.*` 的可选参数
（`--conns/--duration/--rate` 等）与下文「常用选项」一致。

## 手动准备被测文件（可选）

若不用 `serve`，也可手动在被测服务器上放一个大文件（建议 ≥ 1GiB）：

```bash
dd if=/dev/zero of=/var/www/html/testfile.bin bs=1M count=2048   # 生成 2GiB
# 再用 nginx / caddy / python -m http.server 提供下载
```

## 仅客户端一键运行

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
| `--auto` | 自动探测最佳并发（忽略 `-c`） | 关 |
| `--max-connections` | 自动探测并发上限 | 256 |
| `--probe` | 自动探测每档持续秒数 | 5 |
| `-d, --duration` | 运行秒数，`0` 为不间断 | 0 |
| `-r, --rate` | 目标总速率 Gbps，`0` 为不限速 | 0 |
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
