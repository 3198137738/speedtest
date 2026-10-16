# 一键压测脚本（Windows PowerShell）
# 用法:  .\run.ps1 -Url <目标URL> [-Conns 64] [-Duration 86400] [-Rate 10]
# 示例:  .\run.ps1 -Url https://your-server.example.com/testfile.bin
#
# 仅对你自己拥有或已获授权测试的服务器运行。
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$Conns = 64,
    [int]$Duration = 86400,   # 默认 24h
    [double]$Rate = 10        # 默认 10 Gbps，设 0 为不限速
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

if (-not (Test-Path ".venv")) {
    python -m venv .venv
}
& ".venv\Scripts\python.exe" -m pip install -q --disable-pip-version-check -r requirements.txt

Write-Host "开始压测 -> $Url  并发=$Conns 时长=${Duration}s 目标=${Rate}Gbps"
& ".venv\Scripts\python.exe" speedtest.py $Url -c $Conns -d $Duration -r $Rate
