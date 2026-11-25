param(
    [string]$InstallDir = ""
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Info([string]$msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)  { Write-Host "[ERR]  $msg" -ForegroundColor Red }

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-AntigravityDir([string]$override) {
    if ($override) {
        if (Test-Path (Join-Path $override "resources\app.asar")) { return (Resolve-Path $override).Path }
        throw "指定的安装目录无效（未找到 resources\app.asar）：$override"
    }
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\antigravity",
        "$env:LOCALAPPDATA\Programs\Antigravity",
        "$env:LOCALAPPDATA\Programs\Google\Antigravity",
        "C:\Program Files\Google\antigravity",
        "C:\Program Files\Google\Antigravity",
        "C:\Program Files\Antigravity"
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "resources\app.asar")) {
            return (Resolve-Path $c).Path
        }
    }
    $regPaths = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($rp in $regPaths) {
        $items = Get-ItemProperty $rp -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '^Antigravity' }
        foreach ($it in $items) {
            if ($it.UninstallString -match '"([^"]+\\)Uninstall[^"]*"') {
                $dir = $Matches[1].TrimEnd('\')
                if (Test-Path (Join-Path $dir "resources\app.asar")) { return (Resolve-Path $dir).Path }
            }
        }
    }
    throw "未检测到 Antigravity 安装目录。请使用 -InstallDir 参数手动指定。"
}

function Get-AsarVersion([string]$asarPath) {
    $fs = [System.IO.File]::OpenRead($asarPath)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $null = $br.ReadUInt32()
        $u2 = $br.ReadUInt32()
        $null = $br.ReadUInt32()
        $jsonLen = $br.ReadUInt32()
        $headerEnd = 8 + [int64]$u2
        $header = ($Utf8NoBom.GetString($br.ReadBytes([int]$jsonLen))) | ConvertFrom-Json
        $pkg = $header.files.'package.json'
        if (-not $pkg) { return "unknown" }
        $fs.Position = $headerEnd + [int64]$pkg.offset
        $pkgObj = ($Utf8NoBom.GetString($br.ReadBytes([int]$pkg.size))) | ConvertFrom-Json
        return [string]$pkgObj.version
    } finally {
        $fs.Close()
    }
}

function Test-FileWritableExclusive([string]$path) {
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $fs.Close()
        return $true
    } catch {
        return $false
    }
}

try {
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "  Google Antigravity 可逆中文界面补丁 - 一键还原" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan

    # 1. 检测安装路径
    $appDir = Find-AntigravityDir $InstallDir
    $resourcesDir = Join-Path $appDir "resources"
    $asarPath = Join-Path $resourcesDir "app.asar"
    Write-Info "检测到安装目录：$appDir"

    # 2. 涉及 Program Files 时检测管理员权限
    if ($appDir -match '(?i)\\Program Files(\s*\(x86\))?\\') {
        if (-not (Test-IsAdmin)) {
            Write-Err "目标目录位于 Program Files 下，需要管理员权限才能写入！"
            Write-Err "请右键点击本脚本（或 restore-en.bat），选择【以管理员身份运行】。"
            exit 1
        }
        Write-Info "管理员权限检查通过。"
    }

    # 3. 检查进程占用与文件锁
    $procs = Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Err "检测到 Antigravity 仍在运行（共 $($procs.Count) 个进程）！"
        Write-Err "请先完全退出 Antigravity（含系统托盘图标），然后再运行还原脚本。"
        exit 1
    }
    if (-not (Test-FileWritableExclusive $asarPath)) {
        Write-Err "目标文件被占用或无写权限，无法还原：$asarPath"
        exit 1
    }

    # 4. 查找对应版本备份
    $version = Get-AsarVersion $asarPath
    Write-Info "检测到当前版本：$version"
    $backupAsar = Join-Path (Join-Path (Join-Path $ScriptDir "backup") $version) "app.asar"

    if (-not (Test-Path $backupAsar)) {
        Write-Err "未找到版本 $version 的备份文件：$backupAsar"
        Write-Warn "如果 Antigravity 刚刚完成官方自动更新，则当前 app.asar 已自动恢复为官方纯英文版本，无需还原。"
        exit 1
    }

    # 5. 从备份恢复 app.asar
    $restoredList = New-Object System.Collections.ArrayList
    Copy-Item -Path $backupAsar -Destination $asarPath -Force
    [void]$restoredList.Add("已还原：$asarPath  (来源：$backupAsar)")

    # 清理可能残留的临时文件
    $tmpAsar = Join-Path $resourcesDir "app.asar.cn-tmp"
    if (Test-Path $tmpAsar) {
        Remove-Item -Force $tmpAsar
        [void]$restoredList.Add("已删除：$tmpAsar")
    }

    Write-Host ""
    Write-Ok "已 100% 还原至官方纯英文版本！"
    Write-Host ""
    Write-Host "本次还原/清理的文件绝对路径清单：" -ForegroundColor Yellow
    foreach ($item in $restoredList) {
        Write-Host "  - $item" -ForegroundColor White
    }
    Write-Host ""
    Write-Info "现在可以重新打开 Antigravity 验证。"
    exit 0
} catch {
    Write-Err $_.Exception.Message
    exit 1
}
