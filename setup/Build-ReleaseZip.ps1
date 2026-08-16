<#
.SYNOPSIS
    GitHub Releaseに添付する配布用zip（CopyOneDriveLink-<バージョン>.zip）を作成する。
.DESCRIPTION
    配布に必要なファイルのみを対象にzipを作成する。
    対象: README.md・LICENSE・src・assets・setup（Install.ps1/.bat）
    対象外: CLAUDE.md・docs等の開発用ドキュメント、
    src/Config.json・src/tray_app_error.log等のユーザー環境固有ファイル、
    このビルドスクリプト自身。

    出力先は distフォルダ（gitignore対象）。バージョン番号はsrc/Version.psd1から
    読み取る。
.NOTES
    Version: 0.1.0
    Author : Yukinori Sone <yukinori_sone@kun-world.com>
    Date   : 2026-08-19
#>

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$versionInfo = Import-PowerShellDataFile (Join-Path $repoRoot "src\Version.psd1")
$version = $versionInfo.Version

$distDir = Join-Path $repoRoot "dist"
$stagingDir = Join-Path $distDir "staging_CopyOneDriveLink"
$zipPath = Join-Path $distDir ("CopyOneDriveLink-{0}.zip" -f $version)

if (Test-Path $stagingDir) {
    Remove-Item -Path $stagingDir -Recurse -Force
}
New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null

Write-Output "バージョン: $version"
Write-Output "作業フォルダ: $stagingDir"
Write-Output ""

Copy-Item -Path (Join-Path $repoRoot "README.md") -Destination $stagingDir
Copy-Item -Path (Join-Path $repoRoot "LICENSE") -Destination $stagingDir

Copy-Item -Path (Join-Path $repoRoot "src") -Destination (Join-Path $stagingDir "src") -Recurse
# ユーザー環境固有のファイル（実行時に生成されるもの）は配布物に含めない
foreach ($excludeName in @('Config.json', 'tray_app_error.log')) {
    $excludePath = Join-Path $stagingDir "src\$excludeName"
    if (Test-Path $excludePath) {
        Remove-Item -Path $excludePath -Force
        Write-Output "除外しました: src\$excludeName"
    }
}

Copy-Item -Path (Join-Path $repoRoot "assets") -Destination (Join-Path $stagingDir "assets") -Recurse

# setupフォルダはInstall.ps1/.batのみ対象（このビルドスクリプト自身は含めない）
New-Item -Path (Join-Path $stagingDir "setup") -ItemType Directory -Force | Out-Null
Copy-Item -Path (Join-Path $repoRoot "setup\Install.ps1") -Destination (Join-Path $stagingDir "setup")
Copy-Item -Path (Join-Path $repoRoot "setup\Install.bat") -Destination (Join-Path $stagingDir "setup")

if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}
Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath

Remove-Item -Path $stagingDir -Recurse -Force

Write-Output ""
Write-Output "作成しました: $zipPath"
