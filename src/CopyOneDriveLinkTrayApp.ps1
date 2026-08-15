<#
.SYNOPSIS
    タスクトレイに常駐し、ホットキーでOneDrive共有リンクをコピーする。
.DESCRIPTION
    タスクトレイに常駐し、グローバルホットキー(既定: Ctrl+Alt+L、設定GUIで変更可)を
    押すと、その時アクティブなExplorerウィンドウで選択中のファイルについて、
    Copy-OneDriveLink.ps1と同じ内容（チーム内相対パス+URL）をクリップボードへ
    コピーする。複数選択・デスクトップ上のアイコン選択には対応しない
    （アクティブなExplorerフォルダウィンドウで単一ファイル選択時のみ動作）。
.PARAMETER Culture
    UI表示言語のテスト用（例: -Culture en）。省略時はWindowsの現在の
    UIカルチャから自動判定する。
.NOTES
    Version: 0.1.0
    Author : Yukinori Sone <yukinori_sone@kun-world.com>
    Date   : 2026-08-16
#>

param(
    [string]$Culture
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Import-Module (Join-Path $PSScriptRoot "CopyOneDriveLink.psm1") -Force
$script:messages = Get-OneDriveMessages -Culture $Culture

# 多重起動防止。SendTo・ホットキー・.bat/.vbsダブルクリック等、起動経路が
# 複数あるため、Mutexで「このユーザーセッションで既に1つ起動しているか」を
# 判定する（他ユーザー・他セッションには影響しないローカル名前空間）。
# [ref]に渡す変数は事前に初期化しておく必要がある（未初期化のまま
# $script:スコープ変数を[ref]に渡すと"NonExistingVariableReference"で
# 失敗し、常に「既に起動中」と誤判定される不具合があったため修正）。
$script:isFirstInstance = $false
$script:singleInstanceMutex = New-Object System.Threading.Mutex($true, "OneDrive_TrayApp_SingleInstance", [ref]$script:isFirstInstance)
if (-not $script:isFirstInstance) {
    [System.Windows.Forms.MessageBox]::Show(
        $script:messages.AlreadyRunningMessage,
        $script:messages.AppName,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    exit
}

try {

# 既定(Continue)だと非終了エラーがtry/catchで捕まらず、静かに後続処理へ
# 進んでしまうことがある。起動処理中の問題は必ず検知したいためStopにする。
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot "CopyOneDriveLinkSettingsForm.ps1")

$csharpSource = @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class OneDriveHotkeyWindow : Form
{
    private const int WM_HOTKEY = 0x0312;
    private const int HOTKEY_ID = 1;
    private const uint MOD_NOREPEAT = 0x4000;

    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public Action Callback;

    protected override void SetVisibleCore(bool value)
    {
        base.SetVisibleCore(false);
    }

    // 既存の登録を解除してから、指定の組み合わせで登録し直す。
    // 戻り値は登録の成否（falseの場合、他アプリと競合している可能性が高い）。
    public bool TryRegisterHotkey(uint modifiers, uint vk)
    {
        UnregisterHotKey(this.Handle, HOTKEY_ID);
        return RegisterHotKey(this.Handle, HOTKEY_ID, modifiers | MOD_NOREPEAT, vk);
    }

    // 現在の登録を完全に解除するだけ（再登録しない）。
    // RegisterHotKeyで登録済みの組み合わせは、押した瞬間に通常のキー入力
    // メッセージとしては配信されずWM_HOTKEYへ完全に振り替えられるため、
    // 「現在ライブ登録中の組み合わせそのもの」を新しい設定として再度キャプチャ
    // したい場合、キャプチャ中だけ一時的にこれで解除しておく必要がある。
    public void UnregisterCurrentHotkey()
    {
        UnregisterHotKey(this.Handle, HOTKEY_ID);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ID && Callback != null)
        {
            Callback();
        }
        base.WndProc(ref m);
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        UnregisterHotKey(this.Handle, HOTKEY_ID);
        base.OnFormClosing(e);
    }
}
"@

Add-Type -TypeDefinition $csharpSource -ReferencedAssemblies System.Windows.Forms, System.Drawing

$script:config = Get-OneDriveConfig -Culture $Culture

function New-OneDriveTrayIconBitmap {
    <#
        タスクトレイ用のアイコンをその場で描画する。assets/icon.ico
        （PNG圧縮フレームを含む形式）をSystem.Drawing.Icon経由で読み込むと、
        コンテキストメニュー（Explorer自身のアイコン抽出）では問題なくても
        NotifyIconでは透過・ピクセルデータが正しく変換されず空白表示になる
        現象を確認したため、.icoファイルを経由せず直接描画する。
    #>
    param([int]$Size = 32)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $scale = $Size / 256.0
    $blue = [System.Drawing.Color]::FromArgb(255, 3, 100, 184)
    $badgeMargin = 8 * $scale
    $badgeRect = New-Object System.Drawing.RectangleF($badgeMargin, $badgeMargin, ($Size - $badgeMargin * 2), ($Size - $badgeMargin * 2))
    $radius = 56 * $scale
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc($badgeRect.X, $badgeRect.Y, $d, $d, 180, 90)
    $path.AddArc($badgeRect.Right - $d, $badgeRect.Y, $d, $d, 270, 90)
    $path.AddArc($badgeRect.Right - $d, $badgeRect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($badgeRect.X, $badgeRect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $brush = New-Object System.Drawing.SolidBrush($blue)
    $g.FillPath($brush, $path)

    $cx = $Size / 2.0
    $cy = $Size / 2.0
    $angle = -40
    $len = 118 * $scale
    $width = 62 * $scale
    $penW = [Math]::Max(1.5, 16 * $scale)
    $offset = 26 * $scale

    foreach ($sign in @(-1, 1)) {
        $ringPath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $r = $width / 2
        $dd = $width
        $rect = New-Object System.Drawing.RectangleF((-$len / 2), (-$r), $len, $width)
        $ringPath.AddArc($rect.X, $rect.Y, $dd, $dd, 90, 180)
        $ringPath.AddArc(($rect.Right - $dd), $rect.Y, $dd, $dd, 270, 180)
        $ringPath.CloseFigure()

        $g.TranslateTransform(($cx + $sign * $offset), ($cy - $sign * $offset * 0.4))
        $g.RotateTransform($angle)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, $penW)
        $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $g.DrawPath($pen, $ringPath)
        $g.ResetTransform()
    }
    $g.Dispose()
    return $bmp
}

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIconBitmap = New-OneDriveTrayIconBitmap -Size 32
$notifyIcon.Icon = [System.Drawing.Icon]::FromHandle($trayIconBitmap.GetHicon())
$notifyIcon.Visible = $true

function Update-OneDriveTrayIconText {
    $displayText = ConvertTo-OneDriveHotkeyDisplayText -ModifierNames $script:config.HotkeyModifiers -KeyCode $script:config.HotkeyKeyCode
    $notifyIcon.Text = $script:messages.TrayTooltipFormat -f $displayText
}
Update-OneDriveTrayIconText

$hotkeyWindow = New-Object OneDriveHotkeyWindow

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$settingsMenuItem = $contextMenu.Items.Add($script:messages.MenuSettings)
$aboutMenuItem = $contextMenu.Items.Add($script:messages.MenuAbout)
[void]$contextMenu.Items.Add("-")
$exitMenuItem = $contextMenu.Items.Add($script:messages.MenuExit)
$notifyIcon.ContextMenuStrip = $contextMenu

$aboutMenuItem.Add_Click({
    $versionInfo = Get-OneDriveVersionInfo
    $displayDate = ConvertTo-OneDriveDisplayDate -DateString $versionInfo.Date -Culture $Culture
    $text = $script:messages.AboutMessageFormat -f $script:messages.AppName, $versionInfo.Version, $displayDate, $versionInfo.Author
    [System.Windows.Forms.MessageBox]::Show(
        $text,
        $script:messages.MenuAbout,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
})

function Invoke-OneDriveHotkeyAction {
    try {
        $foregroundHandle = [OneDriveHotkeyWindow]::GetForegroundWindow()

        # 設定ダイアログでホットキーをテスト登録している最中にWM_HOTKEYが
        # 発火した場合（登録操作自体が発火要因になることがある）、
        # 誤ってURL取得処理が走らないようスキップする。
        if ($script:OneDriveSettingsFormHandle -and $foregroundHandle -eq $script:OneDriveSettingsFormHandle) {
            return
        }

        $shellApp = New-Object -ComObject Shell.Application
        $selectedPath = $null
        $selectedCount = 0

        foreach ($window in $shellApp.Windows()) {
            try {
                if ([IntPtr]$window.HWND -eq $foregroundHandle) {
                    $items = $window.Document.SelectedItems()
                    $selectedCount = $items.Count
                    if ($selectedCount -eq 1) {
                        $selectedPath = $items.Item(0).Path
                    }
                    break
                }
            }
            catch {
                # Explorer以外（IE等）のウィンドウはDocumentプロパティが無く例外になるためスキップ
            }
        }

        if (-not $selectedPath) {
            $message = if ($selectedCount -gt 1) {
                $script:messages.WarnMultipleSelected
            }
            else {
                $script:messages.WarnNoSelection
            }
            $notifyIcon.ShowBalloonTip(3000, $script:messages.AppName, $message, [System.Windows.Forms.ToolTipIcon]::Warning)
            return
        }

        $text = Format-OneDriveShareText -Path $selectedPath -Config $script:config
        $htmlFragment = Format-OneDriveShareHtml -Path $selectedPath -Config $script:config
        Set-OneDriveClipboardContent -PlainText $text -HtmlFragment $htmlFragment

        # 個人用OneDrive領域は既定で本人しかアクセスできず、本ツールが組み立てる
        # URLはOneDriveの「リンクのコピー」のようなアクセス権付与トークンを含まない
        # （単なるサーバー相対URL）ため、相手に既にアクセス権が無いと開けない
        # 可能性がある。teamsite（Teamsチーム/SharePointサイトのライブラリ）は
        # サイトメンバーシップ単位でアクセス権が付くため、この制約を受けない。
        $libraryType = (Find-OneDriveSyncFolderMatch -Path $selectedPath).LibraryType
        if ($libraryType -ne 'teamsite') {
            $notifyIcon.ShowBalloonTip(3000, $script:messages.CopiedBalloonTitle, "$text`r`n`r`n$($script:messages.PersonalLibraryWarning)", [System.Windows.Forms.ToolTipIcon]::Warning)
        }
        else {
            $notifyIcon.ShowBalloonTip(3000, $script:messages.CopiedBalloonTitle, $text, [System.Windows.Forms.ToolTipIcon]::Info)
        }
    }
    catch {
        $notifyIcon.ShowBalloonTip(3000, $script:messages.AppName, $_.Exception.Message, [System.Windows.Forms.ToolTipIcon]::Error)
    }
}

$hotkeyWindow.Callback = [Action]{ Invoke-OneDriveHotkeyAction }

$settingsMenuItem.Add_Click({
    # 設定ウィンドウの多重起動防止。即時反映系（連携設定チェックボックス・
    # ホットキー登録）は複数ウィンドウ間で状態を奪い合い、保存系
    # （文言テンプレート）は後勝ちで前の変更が消えてしまう。さらに
    # $script:OneDriveSettingsFormHandle（ホットキー実行中に設定画面へ
    # フォーカスがあるかを見る単一変数）も2つ目が開くと壊れるため、既に
    # 開いている場合は新規に開かず、既存のウィンドウを前面に出すだけにする。
    if ($script:OneDriveSettingsFormHandle) {
        [OneDriveHotkeyWindow]::ShowWindow($script:OneDriveSettingsFormHandle, 9) | Out-Null  # SW_RESTORE
        [OneDriveHotkeyWindow]::SetForegroundWindow($script:OneDriveSettingsFormHandle) | Out-Null
        return
    }

    $updated = Show-OneDriveSettingsForm -HotkeyWindow $hotkeyWindow -Culture $Culture
    if ($updated) {
        $script:config = $updated
        Update-OneDriveTrayIconText
    }
})

$exitMenuItem.Add_Click({
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $hotkeyWindow.Close()
    [System.Windows.Forms.Application]::Exit()
})

# ハンドル生成をトリガーしてから、設定済みの組み合わせでホットキーを登録する
[void]$hotkeyWindow.Handle
$initialFlags = ConvertTo-OneDriveHotkeyModifierFlags -ModifierNames $script:config.HotkeyModifiers
$registered = $hotkeyWindow.TryRegisterHotkey($initialFlags, [int]$script:config.HotkeyKeyCode)
if (-not $registered) {
    $notifyIcon.ShowBalloonTip(
        5000,
        $script:messages.AppName,
        $script:messages.HotkeyRegisterFailedMessage,
        [System.Windows.Forms.ToolTipIcon]::Warning
    )
}

[System.Windows.Forms.Application]::Run()

}
catch {
    # 起動処理中（NotifyIcon生成・アイコン読み込み等）に例外が起きても、
    # 既定のエラー処理では非表示のまま静かに終了してしまうことがあるため、
    # ログファイルとダイアログの両方に必ず残す。
    $errorLogPath = Join-Path $PSScriptRoot "tray_app_error.log"
    $logLine = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $($_.Exception.GetType().FullName): $($_.Exception.Message)`r`n$($_.ScriptStackTrace)`r`n"
    Add-Content -Path $errorLogPath -Value $logLine -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show(
        ($script:messages.StartupErrorMessageFormat -f $_.Exception.Message, $errorLogPath),
        $script:messages.AppName,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}
finally {
    $script:singleInstanceMutex.ReleaseMutex()
    $script:singleInstanceMutex.Dispose()
}
