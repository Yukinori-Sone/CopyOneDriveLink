<#
.SYNOPSIS
    選択したファイル/フォルダのOneDrive共有リンクをクリップボードにコピーする。
.DESCRIPTION
    エクスプローラの「送る」から、選択したファイル/フォルダのパスを受け取り、
    「チーム内相対パス + SharePoint上のURL」をクリップボードにコピーするツール。
    「送る」経由での起動時、選択パスは自動的に最初の引数として渡される。
.PARAMETER Path
    OneDrive同期フォルダ配下のファイル/フォルダのパス。
.PARAMETER Culture
    UI表示言語のテスト用（例: -Culture en）。省略時はWindowsの現在の
    UIカルチャから自動判定する。
.NOTES
    Version: 0.1.0
    Author : Yukinori Sone <yukinori_sone@kun-world.com>
    Date   : 2026-08-16
#>

param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Path,

    [string]$Culture
)

Add-Type -AssemblyName System.Windows.Forms

function Show-Balloon {
    param([string]$Title, [string]$Text, [System.Windows.Forms.ToolTipIcon]$Icon)

    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
    $notifyIcon.Visible = $true
    $notifyIcon.BalloonTipTitle = $Title
    $notifyIcon.BalloonTipText = $Text
    $notifyIcon.BalloonTipIcon = $Icon
    $notifyIcon.ShowBalloonTip(3000)
    Start-Sleep -Milliseconds 3000
    $notifyIcon.Dispose()
}

try {
    Import-Module (Join-Path $PSScriptRoot "CopyOneDriveLink.psm1") -Force
    $messages = Get-OneDriveMessages -Culture $Culture

    $text = Format-OneDriveShareText -Path $Path
    $htmlFragment = Format-OneDriveShareHtml -Path $Path

    # プレーンテキスト・HTMLの両方を同時にクリップボードへ載せる。
    # 貼り付け先がリッチテキスト対応ならHTML（各階層がリンク化された形）、
    # 非対応ならプレーンテキスト（相対パス+URLの2行）が自動的に使われる。
    Set-OneDriveClipboardContent -PlainText $text -HtmlFragment $htmlFragment

    # 個人用OneDrive領域は既定で本人しかアクセスできず、本ツールが組み立てる
    # URLはOneDriveの「リンクのコピー」のようなアクセス権付与トークンを含まない
    # （単なるサーバー相対URL）ため、相手に既にアクセス権が無いと開けない
    # 可能性がある。teamsite（Teamsチーム/SharePointサイトのライブラリ）は
    # サイトメンバーシップ単位でアクセス権が付くため、この制約を受けない。
    $libraryType = (Find-OneDriveSyncFolderMatch -Path $Path).LibraryType
    if ($libraryType -ne 'teamsite') {
        Show-Balloon -Title $messages.CopiedBalloonTitle -Text "$text`r`n`r`n$($messages.PersonalLibraryWarning)" -Icon Warning
    }
    else {
        Show-Balloon -Title $messages.CopiedBalloonTitle -Text $text -Icon Info
    }
}
catch {
    $messages = Get-OneDriveMessages -Culture $Culture
    [System.Windows.Forms.MessageBox]::Show(
        ($messages.CopyFailedMessageFormat -f $_.Exception.Message),
        $messages.AppName,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}
