<#
.SYNOPSIS
    CopyOneDriveLinkを%LOCALAPPDATA%配下へインストールし、常駐アプリを起動する。
.DESCRIPTION
    ダウンロード/展開したフォルダ（Downloadsフォルダ等の一時的な場所）から
    実行することを想定したセットアップスクリプト。SendTo・スタートアップ・
    右クリックメニューはいずれも登録時点の絶対パスをレジストリに書き込むため、
    ダウンロードフォルダのような一時的な場所から直接運用すると、後でフォルダが
    移動・削除された際に登録が壊れてしまう。これを避けるため、
    %LOCALAPPDATA%\CopyOneDriveLink\ へ本体一式（src・assets）をコピーしてから
    運用する。既にインストール済みの場所に既存のConfig.json等があれば
    上書きせず温存する（再インストール・アップグレード時にユーザー設定を
    失わないため）。

    SendTo・スタートアップ・右クリックメニューへの登録自体はこのスクリプトでは
    行わない。常駐アプリのタスクトレイアイコンを右クリック→「設定」から、
    必要なものだけ選んで有効化できる。

    既に常駐アプリが起動中の場合（インストール元・インストール先のどちらから
    起動されたものでも）、停止してよいかY/N確認したうえで、Yなら停止して
    ファイルを差し替え、Nなら何もせず終了する。
.NOTES
    Version: 0.1.0
    Author : Yukinori Sone <yukinori_sone@kun-world.com>
    Date   : 2026-08-16
#>

$ErrorActionPreference = 'Stop'

$sourceRoot = Split-Path $PSScriptRoot -Parent
$installRoot = Join-Path $env:LOCALAPPDATA "CopyOneDriveLink"

# 常駐アプリが（インストール元・インストール先のどちらのコピーであれ）既に
# 起動中かどうかを、常駐アプリ自身が保持するMutex名で判定する。
# プロセスの特定は、複数存在しうるpowershell.exeの中からコマンドラインに
# 常駐アプリのスクリプト名を含むものを探す方式（PIDを別途記録していないため）。
$mutexName = "OneDrive_TrayApp_SingleInstance"
$existingMutexHandle = $null
$isRunning = [System.Threading.Mutex]::TryOpenExisting($mutexName, [ref]$existingMutexHandle)
if ($existingMutexHandle) {
    $existingMutexHandle.Close()
}

if ($isRunning) {
    $answer = Read-Host "常駐アプリが起動中です。停止してファイルを差し替えますか？ (Y/N)"
    if ($answer -notmatch '^[Yy]') {
        Write-Output "中断しました。常駐アプリは起動したままです。"
        exit
    }

    $targetProcesses = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like '*CopyOneDriveLinkTrayApp.ps1*' }
    foreach ($proc in $targetProcesses) {
        Stop-Process -Id $proc.ProcessId -Force
    }
    Write-Output "常駐アプリを停止しました。"
    # 停止直後はファイルハンドルの解放にわずかにラグがあることがあるため一呼吸置く
    Start-Sleep -Milliseconds 500
}

Write-Output "インストール元: $sourceRoot"
Write-Output "インストール先: $installRoot"
Write-Output ""

$resolvedSource = (Resolve-Path $sourceRoot).Path
$resolvedInstall = if (Test-Path $installRoot) { (Resolve-Path $installRoot).Path } else { $null }

if ($resolvedSource -eq $resolvedInstall) {
    Write-Output "既にインストール済みの場所から実行されています。コピーをスキップします。"
}
else {
    New-Item -Path $installRoot -ItemType Directory -Force | Out-Null

    # 再インストール時にConfig.json（ユーザー設定）を上書きしないよう、
    # コピー前に一時退避しておき、コピー完了後に書き戻す。
    $configDest = Join-Path $installRoot "src\Config.json"
    $configBackupPath = $null
    if (Test-Path $configDest) {
        $configBackupPath = Join-Path $env:TEMP ("CopyOneDriveLink_Config_backup_{0}.json" -f ([guid]::NewGuid()))
        Copy-Item -Path $configDest -Destination $configBackupPath -Force
    }

    foreach ($folderName in @('src', 'assets')) {
        $sourceFolder = Join-Path $sourceRoot $folderName
        $destFolder = Join-Path $installRoot $folderName
        if (Test-Path $sourceFolder) {
            # コピー先フォルダが既に存在する状態で
            # `Copy-Item -Path $sourceFolder -Destination $destFolder -Recurse` を行うと、
            # 中身が上書きされるのではなく "$destFolder\<フォルダ名>\..." という
            # 入れ子コピーになってしまう（PowerShellの既知の挙動）。これを避けるため、
            # コピー先を明示的に作成したうえで、末尾に "\*" を付けて「中身」を
            # コピー先直下に展開する。
            New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $sourceFolder '*') -Destination $destFolder -Recurse -Force
            Write-Output "コピーしました: $folderName"
        }
    }

    if ($configBackupPath) {
        Copy-Item -Path $configBackupPath -Destination $configDest -Force
        Remove-Item -Path $configBackupPath -Force
        Write-Output "既存のConfig.jsonを温存しました。"
    }

    Write-Output ""
    Write-Output "コピーが完了しました。"
}

$trayAppVbs = Join-Path $installRoot "src\CopyOneDriveLinkTrayApp.vbs"
if (-not (Test-Path $trayAppVbs)) {
    throw "常駐アプリが見つかりません: $trayAppVbs"
}

Write-Output ""
Write-Output "常駐アプリを起動します..."
Start-Process -FilePath "$env:WINDIR\System32\wscript.exe" -ArgumentList "`"$trayAppVbs`""

Write-Output ""
Write-Output "インストール先: $installRoot"
Write-Output "タスクトレイのアイコンを右クリック→「設定」から、SendTo/スタートアップ/"
Write-Output "右クリックメニューへの登録など、必要な機能を有効にしてください。"

if ($resolvedSource -ne $resolvedInstall) {
    Write-Output ""
    Write-Output "「$installRoot」にインストールしました。"
    Write-Output "ダウンロードフォルダ等にある元のフォルダ（$resolvedSource）は"
    Write-Output "削除しても問題ありません。"
}
