# bench.ps1 —— 服务器带宽压测一体化脚本（Windows PowerShell）
#
# 子命令:
#   serve   在【被测服务器】上生成测试文件并起 HTTP 服务（下载源）
#   load    在【客户端】上并发下载, 24h 不间断压测
#   all     本机既做源又做压测（单机自测）
#
# 两端都必须是你自己拥有或已获授权的机器。
#
# 用法示例:
#   .\bench.ps1 serve -Size 2048 -Port 8080
#   .\bench.ps1 load -Url http://服务器IP:8080/testfile.bin -Conns 128 -Rate 10
#   .\bench.ps1 all
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("serve", "load", "all")]
    [string]$Cmd,

    [string]$Url = "",
    [int]$Size = 2048,        # 测试文件 MiB
    [int]$Port = 8080,
    [int]$Conns = 64,
    [int]$Duration = 86400,   # 24h
    [double]$Rate = 10,       # 目标 Gbps, 0 为不限速
    [string]$Dir = "."
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot
$FileName = "testfile.bin"

function Ensure-File([string]$Path, [int]$SizeMb) {
    $needBytes = [int64]$SizeMb * 1MB
    if ((Test-Path $Path) -and ((Get-Item $Path).Length -eq $needBytes)) {
        Write-Host "测试文件已存在且大小正确: $Path ($SizeMb MiB)"
        return
    }
    Write-Host "生成测试文件: $Path ($SizeMb MiB) ..."
    $fs = [System.IO.File]::Create($Path)
    try { $fs.SetLength($needBytes) } finally { $fs.Close() }
}

function Setup-Venv {
    if (-not (Test-Path ".venv")) { python -m venv .venv }
    & ".venv\Scripts\python.exe" -m pip install -q --disable-pip-version-check -r requirements.txt
}

switch ($Cmd) {
    "serve" {
        if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir | Out-Null }
        Ensure-File (Join-Path $Dir $FileName) $Size
        $ip = (Get-NetIPAddress -AddressFamily IPv4 |
               Where-Object { $_.IPAddress -notlike "127.*" } |
               Select-Object -First 1 -ExpandProperty IPAddress)
        Write-Host "------------------------------------------------------------"
        Write-Host "HTTP 下载源已就绪, 端口 $Port, 目录 $Dir"
        Write-Host "客户端压测 URL:  http://${ip}:${Port}/${FileName}"
        Write-Host "(按 Ctrl+C 停止)"
        Write-Host "------------------------------------------------------------"
        python -m http.server $Port --directory $Dir
    }
    "load" {
        if (-not $Url) { throw "load 需要 -Url, 例如: -Url http://服务器IP:8080/testfile.bin" }
        Setup-Venv
        Write-Host "开始压测 -> $Url  并发=$Conns 时长=${Duration}s 目标=${Rate}Gbps"
        & ".venv\Scripts\python.exe" speedtest.py $Url -c $Conns -d $Duration -r $Rate
    }
    "all" {
        $tmp = ".serve_tmp"
        if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp | Out-Null }
        Ensure-File (Join-Path $tmp $FileName) $Size
        Setup-Venv
        Write-Host "启动本地下载源(端口 $Port) ..."
        $srv = Start-Process -FilePath "python" `
            -ArgumentList "-m", "http.server", "$Port", "--directory", "$tmp" `
            -PassThru -WindowStyle Hidden
        try {
            Start-Sleep -Seconds 1
            $u = "http://127.0.0.1:$Port/$FileName"
            Write-Host "开始本机自测 -> $u  并发=$Conns 时长=${Duration}s 目标=${Rate}Gbps"
            & ".venv\Scripts\python.exe" speedtest.py $u -c $Conns -d $Duration -r $Rate
        }
        finally {
            if ($srv -and -not $srv.HasExited) { Stop-Process -Id $srv.Id -Force }
        }
    }
}
