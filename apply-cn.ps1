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

function Get-AsarHeaderAndOffset([string]$asarPath) {
    $fs = [System.IO.File]::OpenRead($asarPath)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $u1 = $br.ReadUInt32()
        $u2 = $br.ReadUInt32()
        $u3 = $br.ReadUInt32()
        $jsonLen = $br.ReadUInt32()
        $headerEnd = 8 + [int64]$u2
        $jsonBytes = $br.ReadBytes([int]$jsonLen)
        $headerJson = $Utf8NoBom.GetString($jsonBytes)
        $header = $headerJson | ConvertFrom-Json
        return @{
            Header    = $header
            HeaderEnd = $headerEnd
            FileSize  = $fs.Length
        }
    } finally {
        $fs.Close()
    }
}

function Read-AsarEntryText([string]$asarPath, $meta, [string[]]$segments) {
    $node = $meta.Header
    foreach ($s in $segments) { $node = $node.files.$s }
    if (-not $node) { throw "app.asar 中未找到目标文件：$($segments -join '/')" }
    $fs = [System.IO.File]::OpenRead($asarPath)
    try {
        $fs.Position = $meta.HeaderEnd + [int64]$node.offset
        $buf = New-Object byte[] ([int]$node.size)
        $read = $fs.Read($buf, 0, $buf.Length)
        if ($read -ne $buf.Length) { throw "读取 app.asar 条目不完整：$($segments -join '/')" }
        return $Utf8NoBom.GetString($buf)
    } finally {
        $fs.Close()
    }
}

function Compute-AsarIntegrity([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fullHash = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
        $blockSize = 4194304
        $blocks = New-Object System.Collections.ArrayList
        if ($bytes.Length -eq 0) {
            [void]$blocks.Add($fullHash)
        } else {
            for ($pos = 0; $pos -lt $bytes.Length; $pos += $blockSize) {
                $len = [Math]::Min($blockSize, $bytes.Length - $pos)
                $slice = New-Object byte[] $len
                [Array]::Copy($bytes, $pos, $slice, 0, $len)
                $bh = ([BitConverter]::ToString($sha.ComputeHash($slice)) -replace '-', '').ToLowerInvariant()
                [void]$blocks.Add($bh)
            }
        }
        return [ordered]@{
            algorithm = "SHA256"
            hash      = $fullHash
            blockSize = $blockSize
            blocks    = @($blocks)
        }
    } finally {
        $sha.Dispose()
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
    Write-Host "  Google Antigravity 可逆中文界面补丁 - 应用工具" -ForegroundColor Cyan
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
            Write-Err "请右键点击本脚本（或 apply-cn.bat），选择【以管理员身份运行】。"
            exit 1
        }
        Write-Info "管理员权限检查通过。"
    }

    # 3. 检查补丁源文件
    $cnPatchPath = Join-Path $ScriptDir "cn-patch.js"
    $menuPatchPath = Join-Path $ScriptDir "menu-patch.js"
    if (-not (Test-Path $cnPatchPath))   { throw "缺少渲染层补丁文件：$cnPatchPath" }
    if (-not (Test-Path $menuPatchPath)) { throw "缺少菜单栏补丁文件：$menuPatchPath" }

    # 4. 检查进程占用与文件锁
    $procs = Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Err "检测到 Antigravity 仍在运行（共 $($procs.Count) 个进程）！"
        Write-Err "请先完全退出 Antigravity（注意检查右下角系统托盘图标并右键退出），然后再运行本脚本。"
        exit 1
    }
    if (-not (Test-FileWritableExclusive $asarPath)) {
        Write-Err "目标文件被占用或无写权限，无法安全修改：$asarPath"
        Write-Err "请确认 Antigravity 已完全退出且没有杀毒软件锁定该文件后重试。"
        exit 1
    }
    Write-Ok "文件占用检查通过（无进程锁定）。"

    # 5. 读取版本号
    $meta = Get-AsarHeaderAndOffset $asarPath
    $pkgJson = Read-AsarEntryText $asarPath $meta @("package.json") | ConvertFrom-Json
    $version = if ($pkgJson.version) { [string]$pkgJson.version } else { "unknown" }
    Write-Info "检测到 Antigravity 版本：$version"

    # 6. 备份原始 app.asar 到 D:\antigravity-cn\backup\<版本号>\
    $backupDir = Join-Path (Join-Path $ScriptDir "backup") $version
    $backupAsar = Join-Path $backupDir "app.asar"
    $createdOrModified = New-Object System.Collections.ArrayList

    $currentPreload = Read-AsarEntryText $asarPath $meta @("dist", "preload.js")
    $alreadyPatched = $currentPreload -match '__AGY_CN_PATCH_START__'

    if (-not (Test-Path $backupAsar)) {
        if ($alreadyPatched) {
            throw "当前 app.asar 已包含补丁标记，但未找到对应版本的原始备份（$backupAsar）。为防止覆盖纯净备份，已中止操作。"
        }
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        Copy-Item -Path $asarPath -Destination $backupAsar -Force
        [void]$createdOrModified.Add($backupAsar)
        Write-Ok "已备份原始 app.asar：$backupAsar"
    } else {
        Write-Info "已存在版本 $version 的纯净备份，将基于纯净备份重新生成补丁：$backupAsar"
    }

    # 7. 基于纯净备份构建新版 app.asar（仅追加修改后的 dist/preload.js 与 dist/main.js）
    $srcMeta = Get-AsarHeaderAndOffset $backupAsar
    $origPreload = Read-AsarEntryText $backupAsar $srcMeta @("dist", "preload.js")
    $origMain    = Read-AsarEntryText $backupAsar $srcMeta @("dist", "main.js")

    $cnPatchCode   = [System.IO.File]::ReadAllText($cnPatchPath, $Utf8NoBom)
    $menuPatchCode = [System.IO.File]::ReadAllText($menuPatchPath, $Utf8NoBom)

    $newPreloadText = $origPreload + "`n/* __AGY_CN_PATCH_START__ */`n" + $cnPatchCode + "`n/* __AGY_CN_PATCH_END__ */`n"

    $menuBlock = "`n/* __AGY_CN_MENU_PATCH_START__ */`n" + $menuPatchCode + "`n/* __AGY_CN_MENU_PATCH_END__ */`n"
    if ($origMain -match '^\s*"use strict";') {
        $newMainText = [regex]::Replace($origMain, '^(\s*"use strict";)', ('$1' + $menuBlock), 1)
    } else {
        $newMainText = $menuBlock + $origMain
    }

    $newPreloadBytes = $Utf8NoBom.GetBytes($newPreloadText)
    $newMainBytes    = $Utf8NoBom.GetBytes($newMainText)

    $origPayloadLen = $srcMeta.FileSize - $srcMeta.HeaderEnd
    $preloadOffset  = $origPayloadLen
    $mainOffset     = $origPayloadLen + [int64]$newPreloadBytes.Length

    # 更新 header 中的 preload.js 与 main.js 元数据
    $preloadEntry = $srcMeta.Header.files.dist.files.'preload.js'
    $preloadEntry.size = $newPreloadBytes.Length
    $preloadEntry.offset = [string]$preloadOffset
    if ($preloadEntry.PSObject.Properties.Name -contains 'integrity') {
        $preloadEntry.integrity = Compute-AsarIntegrity $newPreloadBytes
    }

    $mainEntry = $srcMeta.Header.files.dist.files.'main.js'
    $mainEntry.size = $newMainBytes.Length
    $mainEntry.offset = [string]$mainOffset
    if ($mainEntry.PSObject.Properties.Name -contains 'integrity') {
        $mainEntry.integrity = Compute-AsarIntegrity $newMainBytes
    }

    $newHeaderJson = $srcMeta.Header | ConvertTo-Json -Depth 100 -Compress
    $newHeaderBytes = $Utf8NoBom.GetBytes($newHeaderJson)
    $jsonLen = $newHeaderBytes.Length
    $padLen = (4 - ($jsonLen % 4)) % 4
    $u3 = [uint32]($jsonLen + 4 + $padLen)
    $u2 = [uint32]($u3 + 4)
    $u1 = [uint32]4

    $tmpAsar = Join-Path $resourcesDir "app.asar.cn-tmp"
    if (Test-Path $tmpAsar) { Remove-Item -Force $tmpAsar }

    $outFs = [System.IO.File]::Create($tmpAsar)
    try {
        $bw = New-Object System.IO.BinaryWriter($outFs)
        $bw.Write($u1)
        $bw.Write($u2)
        $bw.Write($u3)
        $bw.Write([uint32]$jsonLen)
        $bw.Write($newHeaderBytes)
        if ($padLen -gt 0) {
            $bw.Write((New-Object byte[] $padLen))
        }
        $bw.Flush()

        # 复制原始数据段
        $inFs = [System.IO.File]::OpenRead($backupAsar)
        try {
            $inFs.Position = $srcMeta.HeaderEnd
            $inFs.CopyTo($outFs)
        } finally {
            $inFs.Close()
        }

        # 追加新 preload.js 与 main.js
        $outFs.Write($newPreloadBytes, 0, $newPreloadBytes.Length)
        $outFs.Write($newMainBytes, 0, $newMainBytes.Length)
        $outFs.Flush()
    } finally {
        $outFs.Close()
    }

    # 8. 校验临时 ASAR 可正确解析
    $verifyMeta = Get-AsarHeaderAndOffset $tmpAsar
    $verifyPreload = Read-AsarEntryText $tmpAsar $verifyMeta @("dist", "preload.js")
    $verifyMain    = Read-AsarEntryText $tmpAsar $verifyMeta @("dist", "main.js")
    if ($verifyPreload -notmatch '__AGY_CN_PATCH_START__' -or $verifyMain -notmatch '__AGY_CN_MENU_PATCH_START__') {
        Remove-Item -Force $tmpAsar -ErrorAction SilentlyContinue
        throw "生成的临时 app.asar 校验失败，已中止并保持原文件不变。"
    }

    # 9. 原子替换目标 app.asar
    Move-Item -Path $tmpAsar -Destination $asarPath -Force
    [void]$createdOrModified.Add($asarPath)

    Write-Host ""
    Write-Ok "中文界面补丁已成功应用（渲染层 UI + 原生菜单栏/托盘）！"
    Write-Host ""
    Write-Host "本次改动/创建的文件绝对路径清单：" -ForegroundColor Yellow
    foreach ($p in $createdOrModified) {
        Write-Host "  - $p" -ForegroundColor White
    }
    Write-Host ""
    Write-Info "现在可以重新打开 Antigravity 验证中文界面。如需还原，请运行 restore-en.bat。"
    exit 0
} catch {
    Write-Err $_.Exception.Message
    exit 1
}
