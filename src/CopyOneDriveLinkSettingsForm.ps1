# OneDriveTrayAppのタスクトレイ右クリックメニュー「設定...」から呼び出す設定GUI。
# ホットキーのテスト登録・復元には、呼び出し元（常駐アプリ）が保持している
# OneDriveHotkeyWindowインスタンスをそのまま使う（新規ウィンドウでの競合誤検知を防ぐため）。
#
# Version: 0.1.0
# Author : Yukinori Sone <yukinori_sone@kun-world.com>
# Date   : 2026-08-16
#
# 複数のイベントハンドラ間で共有・更新する状態（確定前のホットキー候補、
# ダイアログの戻り値）は $script: スコープの変数で持つ
# （スクリプトブロックを .GetNewClosure() すると呼び出し時点のスナップショットに
# なり、他のハンドラでの変更が反映されなくなるため使わない）。
#
# ただし例外あり: New-OneDriveIntegrationCheckBox のように「呼び出しが
# 終わった後（イベント発火時）まで生き残るスクリプトブロックを、ヘルパー関数の
# 中で作って返す/コントロールに仕込む」場合は、逆に.GetNewClosure()が必須
# （無いとそのヘルパー関数自身のローカルパラメータが呼び出し時点で解決できず
# "&"の実行が失敗する）。かつ、.GetNewClosure()は「そのスクリプトブロックを
# 直接囲んでいる関数自身のローカルスコープ」しか捕まえず、さらに外側
# （祖先関数）のローカル変数・$script:スコープ変数・兄弟関数の定義までは
# 一切辿ってくれない（実機検証済み）。そのため祖先スコープにある値
# （$integrationStatusLabel・$script:messages等）が必要な場合は、
# ヘルパー関数自身のパラメータとして明示的に受け取る必要がある。
# 詳細は New-OneDriveIntegrationCheckBox 内のコメントを参照。

# キー入力の捕捉にForm.KeyDownイベントを使わない理由: WinFormsのKeyDownは
# Altキーを含む組み合わせ（WM_SYSKEYDOWN。Alt+F4等と同じ系統のメッセージ）を
# 拾えないことがある。IMessageFilterでWM_KEYDOWN/WM_SYSKEYDOWN両方を
# アプリ全体のメッセージループレベルで捕捉する。
$OneDriveKeyCaptureFilterSource = @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class OneDriveKeyCaptureFilter : IMessageFilter
{
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int VK_CONTROL = 0x11;
    private const int VK_MENU = 0x12;
    private const int VK_SHIFT = 0x10;

    [DllImport("user32.dll")]
    private static extern short GetKeyState(int nVirtKey);

    public bool Enabled;
    public Action<int, bool, bool, bool> OnKeyCaptured;

    public bool PreFilterMessage(ref Message m)
    {
        if (!Enabled) return false;
        if (m.Msg != WM_KEYDOWN && m.Msg != WM_SYSKEYDOWN) return false;

        int vk = m.WParam.ToInt32();
        if (vk == VK_CONTROL || vk == VK_MENU || vk == VK_SHIFT) return false;

        bool ctrl = GetKeyState(VK_CONTROL) < 0;
        bool alt = GetKeyState(VK_MENU) < 0;
        bool shift = GetKeyState(VK_SHIFT) < 0;

        if (OnKeyCaptured != null)
        {
            OnKeyCaptured(vk, ctrl, alt, shift);
        }
        return true;
    }
}
"@

if (-not ("OneDriveKeyCaptureFilter" -as [type])) {
    Add-Type -TypeDefinition $OneDriveKeyCaptureFilterSource -ReferencedAssemblies System.Windows.Forms
}

function New-OneDriveSettingsVarLabel {
    param(
        [string]$Text,
        [bool]$IsHeader
    )
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.AutoSize = $false
    $lbl.Dock = [System.Windows.Forms.DockStyle]::Fill
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    if ($IsHeader) {
        $lbl.ForeColor = [System.Drawing.Color]::Gray
        $lbl.Font = New-Object System.Drawing.Font($lbl.Font, [System.Drawing.FontStyle]::Bold)
    }
    return $lbl
}

function New-OneDriveFormatSubTab {
    <#
        「フォーマット」タブ内の子タブ（Teams/SharePoint用・個人用OneDrive用）を
        1つ作る。変数一覧・文言テンプレート欄（プレーンテキスト/HTML）・
        ヒントラベルをまとめて配置する。
        IncludeSiteChannel: $falseの場合、$SiteName/$ChannelName系の行を
        変数一覧から除く（個人用OneDriveにはその概念が無いため）。
        戻り値: 生成したテキストボックス2つ（TextBox/HtmlBox）。
    #>
    param(
        [System.Windows.Forms.TabControl]$ParentTabControl,
        [string]$TabTitle,
        [bool]$IncludeSiteChannel,
        [string]$TextTemplateValue,
        [string]$HtmlTemplateValue
    )

    $subTab = New-Object System.Windows.Forms.TabPage
    $subTab.Text = $TabTitle
    $subTab.AutoScroll = $true
    $ParentTabControl.TabPages.Add($subTab)

    $y = 10

    $varSectionLabel = New-Object System.Windows.Forms.Label
    $varSectionLabel.Text = $script:messages.VarSectionLabel
    $varSectionLabel.Location = New-Object System.Drawing.Point(10, $y)
    $varSectionLabel.Size = New-Object System.Drawing.Size(555, 18)
    $subTab.Controls.Add($varSectionLabel)
    $y += 20

    $allVarPairs = @(
        @("`$SiteName  ($($script:messages.VarSiteNameDesc))", "`$SiteLink  ($($script:messages.VarSiteLinkDesc))"),
        @("`$ChannelName  ($($script:messages.VarChannelNameDesc))", "`$ChannelLink  ($($script:messages.VarChannelLinkDesc))"),
        @("`$RelativeDir  ($($script:messages.VarRelativeDirDesc))", "`$RelativeDirLink  ($($script:messages.VarRelativeDirLinkDesc))"),
        @("`$FileName  ($($script:messages.VarFileNameDesc))", "`$FileLink  ($($script:messages.VarFileLinkDesc))"),
        @("`$RelativePath  ($($script:messages.VarRelativePathDesc))", "`$RelativePathLink  ($($script:messages.VarRelativePathLinkDesc))"),
        @("`$Url  ($($script:messages.VarUrlDesc))", "`$UrlLink  ($($script:messages.VarUrlLinkDesc))")
    )
    $varPairs = if ($IncludeSiteChannel) { $allVarPairs } else { $allVarPairs[2..5] }

    $varRowHeight = 20
    $variableTable = New-Object System.Windows.Forms.TableLayoutPanel
    $variableTable.Location = New-Object System.Drawing.Point(10, $y)
    $variableTable.Size = New-Object System.Drawing.Size(555, ($varRowHeight * ($varPairs.Count + 1)))
    $variableTable.ColumnCount = 2
    $variableTable.RowCount = $varPairs.Count + 1
    [void]$variableTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$variableTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    for ($r = 0; $r -lt ($varPairs.Count + 1); $r++) {
        [void]$variableTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $varRowHeight)))
    }

    $variableTable.Controls.Add((New-OneDriveSettingsVarLabel $script:messages.VarHeaderPlain $true), 0, 0)
    $variableTable.Controls.Add((New-OneDriveSettingsVarLabel $script:messages.VarHeaderHtml $true), 1, 0)
    for ($i = 0; $i -lt $varPairs.Count; $i++) {
        $variableTable.Controls.Add((New-OneDriveSettingsVarLabel $varPairs[$i][0] $false), 0, ($i + 1))
        $variableTable.Controls.Add((New-OneDriveSettingsVarLabel $varPairs[$i][1] $false), 1, ($i + 1))
    }
    $subTab.Controls.Add($variableTable)
    $y += $variableTable.Height + 8

    $textLabel = New-Object System.Windows.Forms.Label
    $textLabel.Text = $script:messages.TextTemplateLabel
    $textLabel.Location = New-Object System.Drawing.Point(10, $y)
    $textLabel.Size = New-Object System.Drawing.Size(400, 18)
    $subTab.Controls.Add($textLabel)
    $y += 18

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Multiline = $true
    $textBox.ScrollBars = "Vertical"
    $textBox.Location = New-Object System.Drawing.Point(10, $y)
    $textBox.Size = New-Object System.Drawing.Size(555, 60)
    $textBox.Text = $TextTemplateValue
    $subTab.Controls.Add($textBox)
    $y += 68

    $htmlLabel = New-Object System.Windows.Forms.Label
    $htmlLabel.Text = $script:messages.HtmlTemplateLabel
    $htmlLabel.Location = New-Object System.Drawing.Point(10, $y)
    $htmlLabel.Size = New-Object System.Drawing.Size(400, 18)
    $subTab.Controls.Add($htmlLabel)
    $y += 18

    $htmlBox = New-Object System.Windows.Forms.TextBox
    $htmlBox.Multiline = $true
    $htmlBox.ScrollBars = "Vertical"
    $htmlBox.Location = New-Object System.Drawing.Point(10, $y)
    $htmlBox.Size = New-Object System.Drawing.Size(555, 60)
    $htmlBox.Text = $HtmlTemplateValue
    $subTab.Controls.Add($htmlBox)
    $y += 68

    $hintLabel = New-Object System.Windows.Forms.Label
    $hintLabel.Text = $script:messages.HtmlHint
    $hintLabel.Location = New-Object System.Drawing.Point(10, $y)
    $hintLabel.Size = New-Object System.Drawing.Size(555, 36)
    $hintLabel.ForeColor = [System.Drawing.Color]::Gray
    $subTab.Controls.Add($hintLabel)

    return [PSCustomObject]@{
        TextBox = $textBox
        HtmlBox = $htmlBox
    }
}

function Show-OneDriveSettingsForm {
    <#
        設定ダイアログを表示する。
        HotkeyWindow: CopyOneDriveLinkTrayApp.ps1で生成済みのOneDriveHotkeyWindowインスタンス
        （ホットキーのテスト登録・本登録・復元に使う）。
        戻り値: 保存された場合は更新後のConfig、キャンセルされた場合は $null。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$HotkeyWindow,
        [string]$Culture
    )

    $originalConfig = Get-OneDriveConfig -Culture $Culture
    $originalModifiers = @($originalConfig.HotkeyModifiers)
    $originalKeyCode = [int]$originalConfig.HotkeyKeyCode

    $script:sfPendingModifiers = $originalModifiers
    $script:sfPendingKeyCode = $originalKeyCode
    $script:sfResultConfig = $null

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $script:messages.SettingsTitle
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Width = 640
    $form.Height = 600

    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Location = New-Object System.Drawing.Point(10, 10)
    $tabControl.Size = New-Object System.Drawing.Size(605, 480)
    $form.Controls.Add($tabControl)

    $tabGeneral = New-Object System.Windows.Forms.TabPage
    $tabGeneral.Text = $script:messages.TabGeneral
    $tabGeneral.AutoScroll = $true
    $tabControl.TabPages.Add($tabGeneral)

    $tabFormat = New-Object System.Windows.Forms.TabPage
    $tabFormat.Text = $script:messages.TabFormat
    $tabFormat.AutoScroll = $true
    $tabControl.TabPages.Add($tabFormat)

    # ---- 「全般」タブ：ホットキー設定 ----
    $y = 15

    $hotkeyGroupLabel = New-Object System.Windows.Forms.Label
    $hotkeyGroupLabel.Text = $script:messages.HotkeyGroupLabel
    $hotkeyGroupLabel.Location = New-Object System.Drawing.Point(15, $y)
    $hotkeyGroupLabel.Size = New-Object System.Drawing.Size(560, 18)
    $tabGeneral.Controls.Add($hotkeyGroupLabel)
    $y += 20

    $hotkeyHintLabel = New-Object System.Windows.Forms.Label
    $hotkeyHintLabel.Text = $script:messages.HotkeyHint
    $hotkeyHintLabel.Location = New-Object System.Drawing.Point(15, $y)
    $hotkeyHintLabel.Size = New-Object System.Drawing.Size(560, 30)
    $hotkeyHintLabel.ForeColor = [System.Drawing.Color]::Gray
    $tabGeneral.Controls.Add($hotkeyHintLabel)
    $y += 32

    $hotkeyDisplayBox = New-Object System.Windows.Forms.TextBox
    $hotkeyDisplayBox.ReadOnly = $true
    $hotkeyDisplayBox.Location = New-Object System.Drawing.Point(15, $y)
    $hotkeyDisplayBox.Size = New-Object System.Drawing.Size(200, 24)
    $hotkeyDisplayBox.Text = ConvertTo-OneDriveHotkeyDisplayText -ModifierNames $script:sfPendingModifiers -KeyCode $script:sfPendingKeyCode
    $tabGeneral.Controls.Add($hotkeyDisplayBox)

    $captureButton = New-Object System.Windows.Forms.Button
    $captureButton.Text = $script:messages.CaptureButtonIdle
    $captureButton.Location = New-Object System.Drawing.Point(225, ($y - 1))
    $captureButton.Size = New-Object System.Drawing.Size(140, 26)
    $tabGeneral.Controls.Add($captureButton)

    $conflictLabel = New-Object System.Windows.Forms.Label
    $conflictLabel.Location = New-Object System.Drawing.Point(15, ($y + 30))
    $conflictLabel.Size = New-Object System.Drawing.Size(560, 44)
    $conflictLabel.Text = $script:messages.ConflictLabelCurrent
    $conflictLabel.ForeColor = [System.Drawing.Color]::Gray
    $tabGeneral.Controls.Add($conflictLabel)

    # ---- 「全般」タブ：連携設定（SendTo・スタートアップ・右クリックメニュー） ----
    $y2 = 210

    $integrationSectionLabel = New-Object System.Windows.Forms.Label
    $integrationSectionLabel.Text = $script:messages.IntegrationSectionLabel
    $integrationSectionLabel.Location = New-Object System.Drawing.Point(15, $y2)
    $integrationSectionLabel.Size = New-Object System.Drawing.Size(560, 18)
    $tabGeneral.Controls.Add($integrationSectionLabel)
    $y2 += 24

    $integrationStatusLabel = New-Object System.Windows.Forms.Label
    $integrationStatusLabel.Location = New-Object System.Drawing.Point(15, ($y2 + 100))
    $integrationStatusLabel.Size = New-Object System.Drawing.Size(560, 36)
    $integrationStatusLabel.ForeColor = [System.Drawing.Color]::Gray

    function New-OneDriveIntegrationCheckBox {
        param(
            [string]$Text,
            [int]$Y,
            [bool]$InitialChecked,
            [scriptblock]$OnInstall,
            [scriptblock]$OnUninstall,
            [System.Windows.Forms.Label]$StatusLabel,
            [hashtable]$Messages
        )
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $Text
        $cb.Location = New-Object System.Drawing.Point(15, $Y)
        $cb.Size = New-Object System.Drawing.Size(560, 22)
        $cb.Checked = $InitialChecked
        $tabGeneral.Controls.Add($cb)

        # 注意: .Add_CheckedChanged({...})形式では$thisは自動的にセンダーへ
        # バインドされない（Register-ObjectEventとは異なる）。代わりに、この
        # 関数呼び出し単位でクロージャ経由で参照できる$cb/$Textを直接使う。
        # $OnInstall/$OnUninstall/$Text等はこの関数(New-OneDriveIntegrationCheckBox)
        # 自身のローカルパラメータであり、関数呼び出しが終わるとスコープごと
        # 消える。イベント発火はその後（ShowDialog中）に起こるため、
        # .GetNewClosure()で呼び出し時点の値をスナップショットしておく必要がある
        # （無いと"&"の呼び出しが失敗する）。
        # ただし.GetNewClosure()は「この関数自身のローカルスコープ」しか
        # スナップショットせず、さらに外側（呼び出し元のShow-OneDriveSettingsForm）
        # のローカル変数や$script:スコープ変数までは辿ってくれない
        # （実機検証済み）。そのため$integrationStatusLabel・$script:messagesも
        # $StatusLabel・$Messagesという「この関数自身のパラメータ」として
        # 明示的に受け取ることで、GetNewClosure()のスナップショット対象に含める。
        $cb.Add_CheckedChanged({
            try {
                if ($cb.Checked) {
                    & $OnInstall
                    $StatusLabel.Text = $Messages.IntegrationEnabledFormat -f $Text
                }
                else {
                    & $OnUninstall
                    $StatusLabel.Text = $Messages.IntegrationDisabledFormat -f $Text
                }
                $StatusLabel.ForeColor = [System.Drawing.Color]::Green
            }
            catch {
                $StatusLabel.Text = $Messages.IntegrationErrorFormat -f $_.Exception.Message
                $StatusLabel.ForeColor = [System.Drawing.Color]::Red
            }
        }.GetNewClosure())

        return $cb
    }

    $sendToCheckBox = New-OneDriveIntegrationCheckBox `
        -Text $script:messages.SendToCheckboxLabel `
        -Y $y2 `
        -InitialChecked (Test-OneDriveSendToRegistered) `
        -OnInstall { Install-OneDriveSendTo } `
        -OnUninstall { Uninstall-OneDriveSendTo } `
        -StatusLabel $integrationStatusLabel `
        -Messages $script:messages
    $y2 += 26

    $startupCheckBox = New-OneDriveIntegrationCheckBox `
        -Text $script:messages.StartupCheckboxLabel `
        -Y $y2 `
        -InitialChecked (Test-OneDriveStartupRegistered) `
        -OnInstall { Install-OneDriveStartup } `
        -OnUninstall { Uninstall-OneDriveStartup } `
        -StatusLabel $integrationStatusLabel `
        -Messages $script:messages
    $y2 += 26

    $contextMenuCheckBox = New-OneDriveIntegrationCheckBox `
        -Text $script:messages.ContextMenuCheckboxLabel `
        -Y $y2 `
        -InitialChecked (Test-OneDriveContextMenuRegistered) `
        -OnInstall { Install-OneDriveContextMenu } `
        -OnUninstall { Uninstall-OneDriveContextMenu } `
        -StatusLabel $integrationStatusLabel `
        -Messages $script:messages
    $y2 += 26

    $tabGeneral.Controls.Add($integrationStatusLabel)

    # ---- 「フォーマット」タブ：Teams/SharePoint用・個人用OneDrive用の子タブ ----
    # 個人用OneDriveには「チーム」「チャネル」の概念が無く$SiteName/$ChannelNameが
    # 常に空文字になるため、同じテンプレートを共用すると固定文言だけが残って
    # 不自然になる。テンプレートを完全に分け、個人用側は変数一覧も
    # $SiteName/$ChannelName系を除いた表示にする。
    $formatSubTabControl = New-Object System.Windows.Forms.TabControl
    $formatSubTabControl.Location = New-Object System.Drawing.Point(5, 5)
    $formatSubTabControl.Size = New-Object System.Drawing.Size(585, 440)
    $tabFormat.Controls.Add($formatSubTabControl)

    $teamFormatControls = New-OneDriveFormatSubTab -ParentTabControl $formatSubTabControl `
        -TabTitle $script:messages.FormatSubTabTeam -IncludeSiteChannel $true `
        -TextTemplateValue $originalConfig.TeamTextTemplate -HtmlTemplateValue $originalConfig.TeamHtmlTemplate

    $personalFormatControls = New-OneDriveFormatSubTab -ParentTabControl $formatSubTabControl `
        -TabTitle $script:messages.FormatSubTabPersonal -IncludeSiteChannel $false `
        -TextTemplateValue $originalConfig.PersonalTextTemplate -HtmlTemplateValue $originalConfig.PersonalHtmlTemplate

    $teamTextTemplateBox = $teamFormatControls.TextBox
    $teamHtmlTemplateBox = $teamFormatControls.HtmlBox
    $personalTextTemplateBox = $personalFormatControls.TextBox
    $personalHtmlTemplateBox = $personalFormatControls.HtmlBox

    # ---- 共通：既定値に戻す/保存/キャンセルボタン ----
    $resetButton = New-Object System.Windows.Forms.Button
    $resetButton.Text = $script:messages.ResetButton
    $resetButton.Location = New-Object System.Drawing.Point(15, ($form.Height - 90))
    $resetButton.Size = New-Object System.Drawing.Size(140, 28)
    $form.Controls.Add($resetButton)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = $script:messages.SaveButton
    $okButton.Location = New-Object System.Drawing.Point(440, ($form.Height - 90))
    $okButton.Size = New-Object System.Drawing.Size(80, 28)
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = $script:messages.CancelButton
    $cancelButton.Location = New-Object System.Drawing.Point(530, ($form.Height - 90))
    $cancelButton.Size = New-Object System.Drawing.Size(85, 28)
    $form.Controls.Add($cancelButton)

    $captureFilter = New-Object OneDriveKeyCaptureFilter
    $captureFilter.Enabled = $false

    $modifierOnlyVkCodes = @(
        [int][System.Windows.Forms.Keys]::ControlKey,
        [int][System.Windows.Forms.Keys]::Menu,
        [int][System.Windows.Forms.Keys]::ShiftKey,
        [int][System.Windows.Forms.Keys]::LWin,
        [int][System.Windows.Forms.Keys]::RWin
    )

    function Set-OneDriveHotkeyCandidate {
        <#
            候補のホットキー組み合わせを評価し、表示欄・判定ラベルを更新する
            （キー入力キャプチャ時・既定値リセット時の両方で共通利用）。
            元の（ダイアログを開いた時点の）組み合わせと同じ場合は判定テストを
            省略し「現在使用中」と表示する。
        #>
        param(
            [string[]]$Modifiers,
            [int]$KeyCode
        )

        $displayText = ConvertTo-OneDriveHotkeyDisplayText -ModifierNames $Modifiers -KeyCode $KeyCode
        $hotkeyDisplayBox.Text = $displayText

        $sameAsOriginal = ($Modifiers.Count -eq $originalModifiers.Count) -and
            (-not (Compare-Object $Modifiers $originalModifiers))  -and
            ($KeyCode -eq $originalKeyCode)
        if ($sameAsOriginal) {
            $script:sfPendingModifiers = $Modifiers
            $script:sfPendingKeyCode = $KeyCode
            $conflictLabel.Text = $script:messages.ConflictLabelCurrent
            $conflictLabel.ForeColor = [System.Drawing.Color]::Gray
            return
        }

        # 実際に一時的に登録を試みて、他アプリと競合していないか確認する。
        # 確定（保存）するまでは、元のホットキーへ必ず戻す。
        $flags = ConvertTo-OneDriveHotkeyModifierFlags -ModifierNames $Modifiers
        $succeeded = $HotkeyWindow.TryRegisterHotkey($flags, $KeyCode)
        $originalFlags = ConvertTo-OneDriveHotkeyModifierFlags -ModifierNames $originalModifiers
        [void]$HotkeyWindow.TryRegisterHotkey($originalFlags, $originalKeyCode)

        if (-not $succeeded) {
            $conflictLabel.Text = $script:messages.ConflictLabelConflictFormat -f $displayText
            $conflictLabel.ForeColor = [System.Drawing.Color]::Red
        }
        elseif (Test-OneDriveHotkeyIsCommonShortcut -ModifierNames $Modifiers -KeyCode $KeyCode) {
            $script:sfPendingModifiers = $Modifiers
            $script:sfPendingKeyCode = $KeyCode
            $conflictLabel.Text = $script:messages.ConflictLabelCommonShortcutFormat -f $displayText
            $conflictLabel.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        else {
            $script:sfPendingModifiers = $Modifiers
            $script:sfPendingKeyCode = $KeyCode
            $conflictLabel.Text = $script:messages.ConflictLabelAvailableFormat -f $displayText
            $conflictLabel.ForeColor = [System.Drawing.Color]::Green
        }
    }

    $captureFilter.OnKeyCaptured = [Action[int, bool, bool, bool]]{
        param($vk, $ctrl, $alt, $shift)

        if ($modifierOnlyVkCodes -contains $vk) {
            return
        }

        $candidateModifiers = @()
        if ($ctrl) { $candidateModifiers += 'Control' }
        if ($alt) { $candidateModifiers += 'Alt' }
        if ($shift) { $candidateModifiers += 'Shift' }

        if ($candidateModifiers.Count -eq 0) {
            $conflictLabel.Text = $script:messages.ConflictLabelNeedModifier
            $conflictLabel.ForeColor = [System.Drawing.Color]::Red
            return
        }

        $captureFilter.Enabled = $false
        $captureButton.Text = $script:messages.CaptureButtonIdle

        Set-OneDriveHotkeyCandidate -Modifiers $candidateModifiers -KeyCode $vk
    }

    $captureButton.Add_Click({
        # RegisterHotKeyで登録済みの組み合わせ（＝現在の元のホットキー）は、
        # 押しても通常のキー入力メッセージとしては配信されずWM_HOTKEYへ
        # 完全に振り替えられてしまう。「元の組み合わせそのもの」を新しい
        # 候補として押し直せるよう、キャプチャ中は一旦完全に解除しておく。
        $HotkeyWindow.UnregisterCurrentHotkey()
        $captureFilter.Enabled = $true
        $captureButton.Text = $script:messages.CaptureButtonWaiting
        $conflictLabel.Text = $script:messages.ConflictLabelPrompt
        $conflictLabel.ForeColor = [System.Drawing.Color]::Gray
    })

    $resetButton.Add_Click({
        # フィールドを既定値で埋めるだけで、保存ボタンを押すまでConfig.jsonには
        # 反映しない（キャンセルすればテンプレート・ホットキーとも元に戻る）。
        $resetDefaults = Get-OneDriveDefaultConfig -Culture $Culture
        $teamTextTemplateBox.Text = $resetDefaults.TeamTextTemplate
        $teamHtmlTemplateBox.Text = $resetDefaults.TeamHtmlTemplate
        $personalTextTemplateBox.Text = $resetDefaults.PersonalTextTemplate
        $personalHtmlTemplateBox.Text = $resetDefaults.PersonalHtmlTemplate

        Set-OneDriveHotkeyCandidate -Modifiers @($resetDefaults.HotkeyModifiers) -KeyCode ([int]$resetDefaults.HotkeyKeyCode)
    })

    $okButton.Add_Click({
        $newConfig = [PSCustomObject]@{
            HotkeyModifiers      = $script:sfPendingModifiers
            HotkeyKeyCode        = $script:sfPendingKeyCode
            TeamTextTemplate     = $teamTextTemplateBox.Text
            TeamHtmlTemplate     = $teamHtmlTemplateBox.Text
            PersonalTextTemplate = $personalTextTemplateBox.Text
            PersonalHtmlTemplate = $personalHtmlTemplateBox.Text
        }

        # 変更後の組み合わせを本登録する
        $flags = ConvertTo-OneDriveHotkeyModifierFlags -ModifierNames $newConfig.HotkeyModifiers
        [void]$HotkeyWindow.TryRegisterHotkey($flags, [int]$newConfig.HotkeyKeyCode)

        Save-OneDriveConfig -Config $newConfig
        $script:sfResultConfig = $newConfig
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $cancelButton.Add_Click({
        # テスト登録・キャプチャ用の解除で変わっている可能性があるため、元のホットキーへ戻す
        $originalFlags = ConvertTo-OneDriveHotkeyModifierFlags -ModifierNames $originalModifiers
        [void]$HotkeyWindow.TryRegisterHotkey($originalFlags, $originalKeyCode)
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
    })

    $form.Add_FormClosing({
        if ($form.DialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
            $originalFlags = ConvertTo-OneDriveHotkeyModifierFlags -ModifierNames $originalModifiers
            [void]$HotkeyWindow.TryRegisterHotkey($originalFlags, $originalKeyCode)
        }
    })

    # 設定ダイアログ表示中は、グローバルホットキーのテスト登録・本登録操作
    # （TryRegisterHotkey）自体がその場でWM_HOTKEYを発火させることがあり、
    # そのままだとURL取得処理（Invoke-OneDriveHotkeyAction）が誤って走って
    # しまう。呼び出し元（CopyOneDriveLinkTrayApp.ps1）がこのハンドルを見て、
    # フォアグラウンドウィンドウがこの設定ダイアログ自身の場合は
    # URL取得処理をスキップできるよう、ハンドルを共有しておく。
    [void]$form.Handle
    $script:OneDriveSettingsFormHandle = $form.Handle
    [System.Windows.Forms.Application]::AddMessageFilter($captureFilter)
    try {
        [void]$form.ShowDialog()
    }
    finally {
        [System.Windows.Forms.Application]::RemoveMessageFilter($captureFilter)
        $script:OneDriveSettingsFormHandle = $null
    }
    return $script:sfResultConfig
}
