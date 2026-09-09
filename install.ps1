# Windows 部署：把各包目录的文件复制到 $env:USERPROFILE 对应位置
# 语义与 install.sh 不同：Linux 用 symlink（仓库即真身），Windows 用复制
# （原生 symlink 需开发者模式，不值当）——所以 Windows 端改完记得 commit。
#
# 用法（cmd 或开始菜单）：
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# 已知降级：herd.lua 目前 Linux 专用（notify-send / .local/state 等），
# 在 Windows 上经 pcall 静默降级——tab 灯可能部分工作，通知/落盘无。
# 适配等真用上 Windows 再做。

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$homeDir = $env:USERPROFILE

# Bash 历史是 state，不进入 dotfiles。若用户通过 Git Bash 使用本仓库，
# 首次部署时迁到 XDG state 目录；已有目标绝不覆盖。
$bashStateHome = if ($env:XDG_STATE_HOME) {
    $env:XDG_STATE_HOME
} else {
    Join-Path $homeDir '.local/state'
}
$bashStateDir = Join-Path $bashStateHome 'bash'
$legacyBashHistory = Join-Path $homeDir '.bash_history'
$xdgBashHistory = Join-Path $bashStateDir 'history'
if ((Test-Path -LiteralPath $legacyBashHistory) -and -not (Test-Path -LiteralPath $xdgBashHistory)) {
    New-Item -ItemType Directory -Path $bashStateDir -Force | Out-Null
    Move-Item -LiteralPath $legacyBashHistory -Destination $xdgBashHistory
    Write-Host "迁移 Bash 历史: $legacyBashHistory -> $xdgBashHistory"
} elseif ((Test-Path -LiteralPath $legacyBashHistory) -and (Test-Path -LiteralPath $xdgBashHistory)) {
    Write-Warning "保留旧 Bash 历史；XDG 目标已存在，请手动合并: $legacyBashHistory"
}

Get-ChildItem -Path $repo -Directory | Where-Object { $_.Name -ne '.git' } | ForEach-Object {
    $pkg = $_.FullName
    Get-ChildItem -Path $pkg -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($pkg.Length + 1)
        $dst = Join-Path $homeDir $rel
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        Copy-Item -Path $_.FullName -Destination $dst -Force
        Write-Host "部署: $dst"
    }
}

Write-Host ""
Write-Host "完成。复制语义：Linux 端改了配置，Windows 端 git pull 后重跑本脚本即可。"
