# OneDriveでローカル同期しているSharePointライブラリの情報をレジストリから取得し、
# ローカルファイルパス ⇔ SharePoint上のURLを相互変換するためのモジュール。
# 詳しい調査経緯・検証結果は ../docs/investigation.md を参照。
#
# Version: 0.1.0
# Author : Yukinori Sone <yukinori_sone@kun-world.com>
# Date   : 2026-08-16

Add-Type -AssemblyName System.Windows.Forms

function Get-OneDriveMessages {
    <#
        UI文言を Messages_<言語コード>.psd1（例: Messages_ja.psd1）から読み込む。
        -Cultureを省略した場合は、Windowsの現在のUIカルチャ
        （[System.Globalization.CultureInfo]::CurrentUICulture）から自動判定する。
        該当する言語ファイルが無い場合はMessages_en.psd1にフォールバックする。
        -Cultureはテスト・動作確認用に明示指定できる（例: "ja", "en"）。
    #>
    [CmdletBinding()]
    param(
        [string]$Culture
    )

    if (-not $Culture) {
        $Culture = ([System.Globalization.CultureInfo]::CurrentUICulture).TwoLetterISOLanguageName
    }

    $path = Join-Path $PSScriptRoot "Messages_$Culture.psd1"
    if (-not (Test-Path $path)) {
        $path = Join-Path $PSScriptRoot "Messages_en.psd1"
    }
    Import-PowerShellDataFile -Path $path
}

function Get-OneDriveVersionInfo {
    <# Version.psd1（Version/Author/Date、手動更新方式）を読み込む。 #>
    [CmdletBinding()]
    param()

    Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot "Version.psd1")
}

function ConvertTo-OneDriveDisplayDate {
    <#
        ISO形式(yyyy-MM-dd)の日付文字列を、UI表示言語に応じた表記に変換する。
        ja: "yyyy/MM/dd(曜日)" 形式（例: 2026/08/13(木)）。
        それ以外の言語はISO形式のまま返す。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DateString,
        [string]$Culture
    )

    if (-not $Culture) {
        $Culture = ([System.Globalization.CultureInfo]::CurrentUICulture).TwoLetterISOLanguageName
    }

    if ($Culture -ne 'ja') {
        return $DateString
    }

    $date = [DateTime]::ParseExact($DateString, 'yyyy-MM-dd', $null)
    return $date.ToString('yyyy/MM/dd(ddd)', [System.Globalization.CultureInfo]::GetCultureInfo('ja-JP'))
}

function Get-OneDriveSyncFolders {
    <#
        HKCU\Software\SyncEngines\Providers\OneDrive 配下から、同期中の
        ライブラリ一覧（MountPoint = ローカル同期先、UrlNamespace = ライブラリ
        ルートURL、LibraryType = teamsite/mysite等、FullRemotePath = 実際に
        同期しているフォルダの完全URL。OneDriveクライアント自身が書き込む値で、
        teamsiteでサブフォルダを同期している場合のみ存在する）を取得する。
    #>
    [CmdletBinding()]
    param()

    $basePath = "HKCU:\Software\SyncEngines\Providers\OneDrive"
    if (-not (Test-Path $basePath)) {
        return @()
    }

    Get-ChildItem $basePath | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath
        if ($props.MountPoint -and $props.UrlNamespace) {
            [PSCustomObject]@{
                Name           = $_.PSChildName
                MountPoint     = $props.MountPoint
                UrlNamespace   = $props.UrlNamespace.TrimEnd('/')
                LibraryType    = $props.LibraryType
                FullRemotePath = $props.FullRemotePath
            }
        }
    }
}

function Resolve-OneDriveServerFolderSegment {
    <#
        teamsite（Teamsチャネル等）の場合、UrlNamespaceはライブラリルートまで
        しか示さず、実際に同期しているサブフォルダ名を含まない。

        最優先: レジストリのFullRemotePath（OneDriveクライアント自身が書き込む、
        実際に同期しているフォルダの完全URL）とUrlNamespaceの差分を、サーバー側の
        フォルダパスとしてそのまま使う。サイト表示名・フォルダ名にどれだけ" - "が
        含まれていても、実機の値を直接読むだけなので誤分解が起こらない。
        （2026-08-16、実機の同期フォルダで確認: サイト表示名自体に" - "を含む
        "サンプル案件管理PJ - Phase1納品"というチームで、ローカル同期フォルダ名が
        "サンプル案件管理PJ - Phase1納品 - Phase1納品"になるケースがあり、旧実装
        （ローカル同期フォルダ名からの推測のみ）ではURLを誤って組み立てていた。
        FullRemotePathを使うことでこのケースも正しく解決できることを確認済み）。

        フォールバック: FullRemotePathが取得できない場合（理論上は起こりうるが
        実機では teamsite で欠けているケースは未確認）のみ、ローカル同期フォルダ名の
        命名規則 "<サイト表示名> - <サーバー側フォルダ名>" から、最初の " - " より
        後ろをサーバー側フォルダ名として推測する。この場合、サイト表示名自体に
        " - " が含まれると誤分解する制約が残る。

        mysite/personal（個人用OneDrive）はサブフォルダ挿入が不要なため $null を返す。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MountPoint,
        [Parameter(Mandatory)][string]$LibraryType,
        [string]$UrlNamespace,
        [string]$FullRemotePath
    )

    if ($LibraryType -ne 'teamsite') {
        return $null
    }

    if ($FullRemotePath -and $UrlNamespace) {
        $trimmedNamespace = $UrlNamespace.TrimEnd('/')
        if ($FullRemotePath.StartsWith($trimmedNamespace, [StringComparison]::OrdinalIgnoreCase)) {
            $segment = $FullRemotePath.Substring($trimmedNamespace.Length).Trim('/')
            if ($segment) {
                return $segment
            }
            return $null
        }
    }

    $leaf = Split-Path $MountPoint -Leaf
    $idx = $leaf.IndexOf(" - ")
    if ($idx -lt 0) {
        return $null
    }
    return $leaf.Substring($idx + 3)
}

function Find-OneDriveSyncFolderMatch {
    <#
        指定パスが配下にあるOneDrive同期フォルダのエントリを1件返す
        （MountPoint/UrlNamespace/LibraryTypeに加え、MountPointから見た
        相対パス=RelativePathを未エンコードのまま "/" 区切りで含む）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $match = Get-OneDriveSyncFolders |
        Where-Object { $Path.StartsWith($_.MountPoint, [StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object { $_.MountPoint.Length } -Descending |
        Select-Object -First 1

    if (-not $match) {
        $messages = Get-OneDriveMessages
        throw ($messages.SyncFolderNotFoundFormat -f $Path)
    }

    $relative = $Path.Substring($match.MountPoint.Length).TrimStart('\').TrimStart('/') -replace '\\', '/'

    [PSCustomObject]@{
        MountPoint     = $match.MountPoint
        UrlNamespace   = $match.UrlNamespace
        LibraryType    = $match.LibraryType
        FullRemotePath = $match.FullRemotePath
        RelativePath   = $relative
    }
}

function ConvertTo-OneDriveUrl {
    <#
        OneDrive同期フォルダ配下のローカルファイル/フォルダパスから、対応する
        SharePoint上のURLを組み立てる。
        戻り値は「開けば実ファイルに解決されるサーバー相対URL」であり、
        SharePoint UIの「リンクのコピー」で得られる共有リンク（sourcedoc=GUID形式）
        とは別物。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $match = Find-OneDriveSyncFolderMatch -Path $Path
    $encodedSegments = @()

    $folderSegment = Resolve-OneDriveServerFolderSegment -MountPoint $match.MountPoint -LibraryType $match.LibraryType -UrlNamespace $match.UrlNamespace -FullRemotePath $match.FullRemotePath
    if ($folderSegment) {
        # FullRemotePath由来の場合、フォルダが複数階層になっていることがあるため
        # "/" 区切りで分解してから各セグメントを個別にエンコードする
        $encodedSegments += ($folderSegment -split '/' | Where-Object { $_ } | ForEach-Object { [Uri]::EscapeDataString($_) })
    }

    if ($match.RelativePath) {
        $encodedSegments += ($match.RelativePath -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) })
    }

    return ($match.UrlNamespace + '/' + ($encodedSegments -join '/'))
}

function ConvertTo-OneDriveRelativePath {
    <#
        OneDrive同期フォルダ（チームサイトのライブラリ）配下のローカルパスから、
        「チーム内相対パス」（"/"区切り、未エンコード）を取得する。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    (Find-OneDriveSyncFolderMatch -Path $Path).RelativePath
}

function Get-OneDriveShareSegments {
    <#
        チーム内相対パスを階層ごとに分解し、各セグメント（各階層フォルダ名・
        末端のファイル名）ごとに「そこまでのパスに対応するURL」を対応付けて返す。
        パンくずリスト形式でリンク化する際に使う。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $match = Find-OneDriveSyncFolderMatch -Path $Path
    $cumulative = @()

    $folderSegment = Resolve-OneDriveServerFolderSegment -MountPoint $match.MountPoint -LibraryType $match.LibraryType -UrlNamespace $match.UrlNamespace -FullRemotePath $match.FullRemotePath
    if ($folderSegment) {
        $cumulative += ($folderSegment -split '/' | Where-Object { $_ } | ForEach-Object { [Uri]::EscapeDataString($_) })
    }

    $relativeSegments = @()
    if ($match.RelativePath) {
        $relativeSegments = $match.RelativePath -split '/'
    }

    foreach ($segmentName in $relativeSegments) {
        $cumulative += [Uri]::EscapeDataString($segmentName)
        [PSCustomObject]@{
            Text = $segmentName
            Url  = $match.UrlNamespace + '/' + ($cumulative -join '/')
        }
    }
}

function ConvertTo-ClipboardHtmlFragment {
    <#
        HTMLフラグメントを、Windowsクリップボードの「HTML Format」
        （CF_HTML）が要求するヘッダー付き形式に変換する。
        StartHTML等のオフセットは10桁ゼロ埋め固定長で仮置きしてから実長で
        置き換える（置き換えても文字数が変わらないようにするための定石）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Fragment
    )

    $enc = [System.Text.Encoding]::UTF8
    $headerTemplate = "Version:0.9`r`nStartHTML:{0:d10}`r`nEndHTML:{1:d10}`r`nStartFragment:{2:d10}`r`nEndFragment:{3:d10}`r`n"
    $headerLength = $enc.GetByteCount(($headerTemplate -f 0, 0, 0, 0))

    # charsetを明示しないと、貼り付け先アプリがUTF-8バイト列を別エンコーディング
    # として誤読し、日本語部分が文字化けすることがある（Teamsで実際に発生した）。
    $htmlPrefix = "<html><head><meta charset=""utf-8""></head><body>`r`n<!--StartFragment-->"
    $htmlSuffix = "<!--EndFragment-->`r`n</body></html>"

    $startHtml = $headerLength
    $startFragment = $startHtml + $enc.GetByteCount($htmlPrefix)
    $endFragment = $startFragment + $enc.GetByteCount($Fragment)
    $endHtml = $endFragment + $enc.GetByteCount($htmlSuffix)

    ($headerTemplate -f $startHtml, $endHtml, $startFragment, $endFragment) + $htmlPrefix + $Fragment + $htmlSuffix
}

function Get-OneDriveTeamChannelInfo {
    <#
        teamsite（Teamsチャネル等）の場合に、チーム名（サイト表示名）と
        チャネル名（同期対象フォルダ名）、およびそれぞれのURLを返す。
        サイトルートURLは UrlNamespace のパスが "/sites/<サイト名>/<ライブラリ名>/..."
        という構造である前提で、先頭2セグメントを取り出して組み立てる
        （SharePointチームサイトの標準的なURL構造に基づく想定）。

        チーム名/チャネル名の境界は、まずFullRemotePath由来のチャネル名
        （Resolve-OneDriveServerFolderSegment参照）を信頼し、ローカル同期
        フォルダ名の末尾がそれと一致すればそこを境界とする。これにより、
        チーム表示名自体に" - "を含む場合でも正しく分解できる。
        FullRemotePathが取得できない場合のみ、最初の" - "を境界とする
        フォールバックを使う（この場合、チーム名に" - "を含むと誤分解する）。

        mysite/personal（個人用OneDrive）の場合は $null を返す。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MountPoint,
        [Parameter(Mandatory)][string]$UrlNamespace,
        [Parameter(Mandatory)][string]$LibraryType,
        [string]$FullRemotePath
    )

    if ($LibraryType -ne 'teamsite') {
        return $null
    }

    $leaf = Split-Path $MountPoint -Leaf
    $folderSegment = Resolve-OneDriveServerFolderSegment -MountPoint $MountPoint -LibraryType $LibraryType -UrlNamespace $UrlNamespace -FullRemotePath $FullRemotePath

    if ($folderSegment -and $leaf.EndsWith(" - " + $folderSegment, [StringComparison]::OrdinalIgnoreCase)) {
        $channelName = $folderSegment
        $teamName = $leaf.Substring(0, $leaf.Length - (" - " + $folderSegment).Length)
    }
    else {
        $idx = $leaf.IndexOf(" - ")
        if ($idx -lt 0) {
            return $null
        }
        $teamName = $leaf.Substring(0, $idx)
        $channelName = $leaf.Substring($idx + 3)
    }

    $uri = [Uri]$UrlNamespace
    $pathSegments = $uri.AbsolutePath.Trim('/') -split '/'
    if ($pathSegments.Length -ge 2 -and $pathSegments[0] -eq 'sites') {
        $teamUrl = $uri.GetLeftPart([UriPartial]::Authority) + '/' + ($pathSegments[0..1] -join '/')
    }
    else {
        $teamUrl = $UrlNamespace
    }

    [PSCustomObject]@{
        TeamName    = $teamName
        TeamUrl     = $teamUrl
        ChannelName = $channelName
        ChannelUrl  = $UrlNamespace + '/' + [Uri]::EscapeDataString($channelName)
    }
}

function Get-OneDriveConfigPath {
    <# 設定ファイル(Config.json)の保存場所。スクリプトファイルと同じフォルダ。 #>
    [CmdletBinding()]
    param()
    Join-Path $PSScriptRoot "Config.json"
}

function Get-OneDriveDefaultConfig {
    <#
        設定ファイルが無い場合・項目が欠けている場合に使う既定値。
        文言テンプレートはTeams/SharePoint用（Team*）と個人用OneDrive用
        （Personal*）で分かれている（個人用OneDriveには「チーム」「チャネル」の
        概念が無く、$SiteName/$ChannelNameが常に空文字になるため、同じ
        テンプレートを共用すると固定文言だけが残って不自然になるため）。
        Cultureに応じてMessages_<言語コード>.psd1のDefaultTeam*/DefaultPersonal*
        から取得する（テンプレートの中身はUI表示言語ではなく「その時点での
        ユーザーの既定値」という位置づけのため、Config.json自体は言語別に
        分けず単一のまま）。
    #>
    [CmdletBinding()]
    param(
        [string]$Culture
    )

    $messages = Get-OneDriveMessages -Culture $Culture

    [PSCustomObject]@{
        HotkeyModifiers      = @('Control', 'Alt')
        HotkeyKeyCode        = 76  # System.Windows.Forms.Keys.L
        TeamTextTemplate     = $messages.DefaultTeamTextTemplate
        TeamHtmlTemplate     = $messages.DefaultTeamHtmlTemplate
        PersonalTextTemplate = $messages.DefaultPersonalTextTemplate
        PersonalHtmlTemplate = $messages.DefaultPersonalHtmlTemplate
    }
}

function Get-OneDriveConfig {
    <#
        Config.jsonを読み込む。ファイルが無い場合・壊れている場合は既定値を
        返すと同時に、その既定値でConfig.jsonを新規作成する（削除・破損しても
        次回起動時に既定値で復元されるようにするため）。
        項目が一部欠けている場合（設定ファイルのバージョン差異）は、
        欠けている項目のみ既定値で補う（この場合はファイルを上書きしない）。
        旧形式（TextTemplate/HtmlTemplateのみを持つ、Team/Personal分割前の
        設定ファイル）はTeamTextTemplate/TeamHtmlTemplateとして引き継ぐ
        （Personal側は新規に既定値が入る）。
    #>
    [CmdletBinding()]
    param(
        [string]$Culture
    )

    $defaults = Get-OneDriveDefaultConfig -Culture $Culture
    $path = Get-OneDriveConfigPath

    if (-not (Test-Path $path)) {
        Save-OneDriveConfig -Config $defaults
        return $defaults
    }

    try {
        $loaded = Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Warning "設定ファイルの読み込みに失敗したため既定値で復元します: $($_.Exception.Message)"
        Save-OneDriveConfig -Config $defaults
        return $defaults
    }

    if ($loaded.PSObject.Properties.Name -contains 'TextTemplate' -and $loaded.PSObject.Properties.Name -notcontains 'TeamTextTemplate') {
        $loaded | Add-Member -MemberType NoteProperty -Name 'TeamTextTemplate' -Value $loaded.TextTemplate
        $loaded.PSObject.Properties.Remove('TextTemplate')
    }
    if ($loaded.PSObject.Properties.Name -contains 'HtmlTemplate' -and $loaded.PSObject.Properties.Name -notcontains 'TeamHtmlTemplate') {
        $loaded | Add-Member -MemberType NoteProperty -Name 'TeamHtmlTemplate' -Value $loaded.HtmlTemplate
        $loaded.PSObject.Properties.Remove('HtmlTemplate')
    }

    foreach ($propName in $defaults.PSObject.Properties.Name) {
        if ($loaded.PSObject.Properties.Name -notcontains $propName) {
            $loaded | Add-Member -MemberType NoteProperty -Name $propName -Value $defaults.$propName
        }
    }
    return $loaded
}

function Save-OneDriveConfig {
    <# 設定をConfig.jsonへ保存する（コメントは書けないため、項目の意味は
       このモジュール・設定GUI側のラベルで説明する運用とする）。 #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    $path = Get-OneDriveConfigPath
    ($Config | ConvertTo-Json -Depth 5) | Set-Content -Path $path -Encoding UTF8
}

function ConvertTo-OneDriveHotkeyModifierFlags {
    <# "Control"/"Alt"/"Shift"の配列から、RegisterHotKey用のMOD_*ビットフラグを組み立てる。 #>
    [CmdletBinding()]
    param(
        [string[]]$ModifierNames
    )

    $flags = 0
    foreach ($name in $ModifierNames) {
        switch ($name) {
            'Alt' { $flags = $flags -bor 0x1 }
            'Control' { $flags = $flags -bor 0x2 }
            'Shift' { $flags = $flags -bor 0x4 }
        }
    }
    return [uint32]$flags
}

function ConvertTo-OneDriveHotkeyDisplayText {
    <# ホットキー設定を "Control + Alt + L" のような表示用文字列に変換する。 #>
    [CmdletBinding()]
    param(
        [string[]]$ModifierNames,
        [int]$KeyCode
    )

    $parts = @()
    foreach ($name in @('Control', 'Alt', 'Shift')) {
        if ($ModifierNames -contains $name) {
            $parts += $name
        }
    }
    $parts += ([System.Windows.Forms.Keys]$KeyCode).ToString()
    $parts -join ' + '
}

# よく知られたアプリ内ショートカット（コピー等）の一覧。"修飾キー(アルファベット順):キー名"
# の形式。RegisterHotKeyは「他アプリがグローバルホットキーとして登録済みか」しか
# 判定できず、各アプリがウィンドウ内で処理しているだけのローカルショートカット
# （Ctrl+C等）との重複は検出できないため、既知のものだけ別途ブロックリストで警告する。
$script:OneDriveCommonShortcuts = @(
    'Control:A', 'Control:C', 'Control:V', 'Control:X', 'Control:Z', 'Control:Y',
    'Control:S', 'Control:N', 'Control:O', 'Control:P', 'Control:F', 'Control:W',
    'Control:Tab', 'Control:Escape',
    'Alt:Tab', 'Alt:F4', 'Alt:Escape', 'Alt:Space',
    'Shift:Delete', 'Shift:Insert',
    'Control+Shift:Escape'
)

function ConvertTo-OneDriveHotkeyComboKey {
    <# ブロックリスト照合用に、修飾キーを固定順(Control,Alt,Shift)で正規化したキー文字列を作る。 #>
    [CmdletBinding()]
    param(
        [string[]]$ModifierNames,
        [int]$KeyCode
    )

    $ordered = @('Control', 'Alt', 'Shift') | Where-Object { $ModifierNames -contains $_ }
    $keyName = ([System.Windows.Forms.Keys]$KeyCode).ToString()
    ($ordered -join '+') + ':' + $keyName
}

function Test-OneDriveHotkeyIsCommonShortcut {
    <#
        指定の組み合わせが、多くのアプリでローカルショートカットとして
        使われている定番の組み合わせ（Ctrl+C等）かどうかを判定する。
        あくまで既知のものだけを対象とした簡易チェックであり、これに
        該当しないからといって他アプリと衝突しないことを保証するものではない。
    #>
    [CmdletBinding()]
    param(
        [string[]]$ModifierNames,
        [int]$KeyCode
    )

    $comboKey = ConvertTo-OneDriveHotkeyComboKey -ModifierNames $ModifierNames -KeyCode $KeyCode
    return $script:OneDriveCommonShortcuts -contains $comboKey
}

function Get-OneDriveShareVariables {
    <#
        テンプレート内で使える変数一式を組み立てる。
        プレーンテキスト/HTML共通（HTMLタグを含まない）: SiteName, ChannelName,
        RelativeDir, FileName, RelativePath, Url
        HTML用（<a>タグ込み、常に全階層をリンク化）: SiteLink, ChannelLink,
        RelativeDirLink, FileLink, RelativePathLink, UrlLink
        「フォルダ部分は非リンクでファイル名だけリンクしたい」等、部分的な
        リンク化はテンプレート側で変数を組み合わせて表現する
        （例: "$RelativeDir$FileLink"）。
        teamsiteでない（mysite等）場合、SiteName/ChannelName関連は空文字になる。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $match = Find-OneDriveSyncFolderMatch -Path $Path
    $segments = @(Get-OneDriveShareSegments -Path $Path)
    $url = ConvertTo-OneDriveUrl -Path $Path
    $teamChannel = Get-OneDriveTeamChannelInfo -MountPoint $match.MountPoint -UrlNamespace $match.UrlNamespace -LibraryType $match.LibraryType -FullRemotePath $match.FullRemotePath

    $fileName = if ($segments.Count -gt 0) { $segments[-1].Text } else { Split-Path $Path -Leaf }
    $fileEncoded = [System.Net.WebUtility]::HtmlEncode($fileName)

    # RelativePath = RelativeDir + FileName となるよう、RelativeDirは
    # 末尾に"/"を含む形（フォルダが無い場合は空文字）にしておく。
    $dirSegments = @()
    if ($segments.Count -gt 1) {
        $dirSegments = $segments[0..($segments.Count - 2)]
    }
    $relativeDir = if ($dirSegments.Count -gt 0) { (($dirSegments | ForEach-Object { $_.Text }) -join '/') + '/' } else { '' }

    if ($segments.Count -gt 0) {
        $relativePathLink = ($segments | ForEach-Object {
            $t = [System.Net.WebUtility]::HtmlEncode($_.Text)
            "<a href=""$($_.Url)"">$t</a>"
        }) -join '/'
        $relativeDirLink = if ($dirSegments.Count -gt 0) {
            (($dirSegments | ForEach-Object {
                $t = [System.Net.WebUtility]::HtmlEncode($_.Text)
                "<a href=""$($_.Url)"">$t</a>"
            }) -join '/') + '/'
        } else { '' }
    }
    elseif ($teamChannel) {
        # チーム/チャネル行が既にファイルそのものを指しているため、パンくずは不要
        $relativePathLink = ''
        $relativeDirLink = ''
    }
    else {
        $relativePathLink = "<a href=""$url"">$url</a>"
        $relativeDirLink = ''
    }

    $siteName = ''
    $channelName = ''
    $siteLink = ''
    $channelLink = ''
    if ($teamChannel) {
        $siteName = $teamChannel.TeamName
        $channelName = $teamChannel.ChannelName
        $siteLink = "<a href=""$($teamChannel.TeamUrl)"">$([System.Net.WebUtility]::HtmlEncode($teamChannel.TeamName))</a>"
        $channelLink = "<a href=""$($teamChannel.ChannelUrl)"">$([System.Net.WebUtility]::HtmlEncode($teamChannel.ChannelName))</a>"
    }

    @{
        SiteName         = $siteName
        ChannelName      = $channelName
        RelativeDir      = $relativeDir
        FileName         = $fileName
        RelativePath     = $match.RelativePath
        Url              = $url
        SiteLink         = $siteLink
        ChannelLink      = $channelLink
        RelativeDirLink  = $relativeDirLink
        FileLink         = "<a href=""$url"">$fileEncoded</a>"
        RelativePathLink = $relativePathLink
        UrlLink          = "<a href=""$url"">$url</a>"
    }
}

function Expand-OneDriveShareTemplate {
    <#
        テンプレート文字列内の $VarName トークンを、対応する値へ単純置換する。
        変数名が他の変数名の前方一致になっているケース（例: $Url と $UrlLink）
        で誤置換しないよう、変数名の長い方から順に置換する。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][hashtable]$Variables
    )

    $result = $Template
    foreach ($key in ($Variables.Keys | Sort-Object { $_.Length } -Descending)) {
        $result = $result.Replace('$' + $key, [string]$Variables[$key])
    }
    return $result
}

function Format-OneDriveShareText {
    <#
        チームメンバー共有用のプレーンテキストを、設定済みテンプレートで組み立てる。
        対象がteamsite（Teams/SharePointライブラリ）かpersonal（個人用OneDrive）かで
        別々のテンプレート（Team*/Personal*）を使う（個人用OneDriveには
        「チーム」「チャネル」の概念が無いため）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [PSCustomObject]$Config
    )

    if (-not $Config) {
        $Config = Get-OneDriveConfig
    }
    $vars = Get-OneDriveShareVariables -Path $Path
    $libraryType = (Find-OneDriveSyncFolderMatch -Path $Path).LibraryType
    $template = if ($libraryType -eq 'teamsite') { $Config.TeamTextTemplate } else { $Config.PersonalTextTemplate }
    Expand-OneDriveShareTemplate -Template $template -Variables $vars
}

function Format-OneDriveShareHtml {
    <#
        チームメンバー共有用のHTMLフラグメントを、設定済みテンプレートで組み立てる。
        テンプレート中の実改行（設定GUIのテキストボックスでEnterを押して
        入力したもの）は自動的に<br>に変換される。装飾用に<b>や<span>等の
        生HTMLタグをテンプレートに直接書くこともできる（そちらは素通しする）。
        プレーンテキスト用の変数（$SiteName等）もHTMLテンプレート内で使える
        （例: サイト名だけリンク化せずテキストのまま出したい場合、$SiteLinkの
        代わりに$SiteNameを使う）。その場合、値自体はHTMLエスケープしてから
        埋め込む（ファイル名等に"&"が含まれるケースがあるため）。
        対象がteamsite（Teams/SharePointライブラリ）かpersonal（個人用OneDrive）かで
        別々のテンプレート（Team*/Personal*）を使う。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [PSCustomObject]$Config
    )

    if (-not $Config) {
        $Config = Get-OneDriveConfig
    }
    $vars = Get-OneDriveShareVariables -Path $Path
    foreach ($plainKey in @('SiteName', 'ChannelName', 'RelativeDir', 'FileName', 'RelativePath')) {
        $vars[$plainKey] = [System.Net.WebUtility]::HtmlEncode([string]$vars[$plainKey])
    }
    $libraryType = (Find-OneDriveSyncFolderMatch -Path $Path).LibraryType
    $rawTemplate = if ($libraryType -eq 'teamsite') { $Config.TeamHtmlTemplate } else { $Config.PersonalHtmlTemplate }
    $template = ($rawTemplate -replace "`r`n", "`n") -replace "`n", '<br>'
    Expand-OneDriveShareTemplate -Template $template -Variables $vars
}

$Win32ClipboardHelperSource = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class OneDriveClipboardHelper
{
    private const uint CF_UNICODETEXT = 13;
    private const uint GMEM_MOVEABLE = 0x0002;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool OpenClipboard(IntPtr hWndNewOwner);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EmptyClipboard();
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseClipboard();
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint RegisterClipboardFormat(string lpszFormat);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr hMem);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalUnlock(IntPtr hMem);

    private static IntPtr AllocAndCopy(byte[] bytes)
    {
        IntPtr hMem = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes.Length);
        IntPtr ptr = GlobalLock(hMem);
        Marshal.Copy(bytes, 0, ptr, bytes.Length);
        GlobalUnlock(hMem);
        return hMem;
    }

    // .NETのDataObject/Clipboardクラス経由だと、"HTML Format"の文字列は
    // システム既定のANSIコードページで変換されてしまい、UTF-8前提で計算した
    // StartFragment/EndFragment等のバイトオフセットとずれて文字化けする。
    // それを避けるため、UTF-8バイト列をWin32 APIで直接クリップボードに書き込む。
    public static void SetTextAndHtml(string plainText, string htmlUtf8Fragment)
    {
        byte[] textBytes = Encoding.Unicode.GetBytes(plainText + "\0");
        byte[] htmlBytes = Encoding.UTF8.GetBytes(htmlUtf8Fragment + "\0");
        uint htmlFormat = RegisterClipboardFormat("HTML Format");

        if (!OpenClipboard(IntPtr.Zero))
        {
            throw new InvalidOperationException("クリップボードを開けませんでした。");
        }
        try
        {
            EmptyClipboard();
            SetClipboardData(CF_UNICODETEXT, AllocAndCopy(textBytes));
            SetClipboardData(htmlFormat, AllocAndCopy(htmlBytes));
        }
        finally
        {
            CloseClipboard();
        }
    }
}
"@

if (-not ("OneDriveClipboardHelper" -as [type])) {
    Add-Type -TypeDefinition $Win32ClipboardHelperSource -Language CSharp
}

function Set-OneDriveClipboardContent {
    <#
        プレーンテキストとHTML(CF_HTML)を、Win32 API経由でUTF-8バイト列の
        まま同時にクリップボードへ書き込む。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlainText,
        [Parameter(Mandatory)][string]$HtmlFragment
    )

    $cfHtml = ConvertTo-ClipboardHtmlFragment -Fragment $HtmlFragment
    [OneDriveClipboardHelper]::SetTextAndHtml($PlainText, $cfHtml)
}

# ---- 「送る」メニュー登録 ----

function Get-OneDriveSendToShortcutPath {
    Join-Path ([Environment]::GetFolderPath('SendTo')) "OneDrive共有リンクをコピー.lnk"
}

function Test-OneDriveSendToRegistered {
    [CmdletBinding()]
    param()
    Test-Path (Get-OneDriveSendToShortcutPath)
}

function Install-OneDriveSendTo {
    [CmdletBinding()]
    param()
    $vbsPath = Join-Path $PSScriptRoot "Copy-OneDriveLink.vbs"
    $shortcutPath = Get-OneDriveSendToShortcutPath
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $shortcut.Arguments = "`"$vbsPath`""
    $shortcut.WorkingDirectory = Split-Path $vbsPath
    $shortcut.Description = "選択したファイルのOneDrive共有リンクをクリップボードにコピー"
    $shortcut.Save()
}

function Uninstall-OneDriveSendTo {
    [CmdletBinding()]
    param()
    $path = Get-OneDriveSendToShortcutPath
    if (Test-Path $path) {
        Remove-Item -Path $path -Force
    }
}

# ---- スタートアップ（ログオン時自動起動）登録 ----

function Get-OneDriveStartupShortcutPath {
    Join-Path ([Environment]::GetFolderPath('Startup')) "OneDrive共有リンクコピー(常駐).lnk"
}

function Test-OneDriveStartupRegistered {
    [CmdletBinding()]
    param()
    Test-Path (Get-OneDriveStartupShortcutPath)
}

function Install-OneDriveStartup {
    [CmdletBinding()]
    param()
    $vbsPath = Join-Path $PSScriptRoot "CopyOneDriveLinkTrayApp.vbs"
    $shortcutPath = Get-OneDriveStartupShortcutPath
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $shortcut.Arguments = "`"$vbsPath`""
    $shortcut.WorkingDirectory = Split-Path $vbsPath
    $shortcut.Description = "OneDrive共有リンクコピー常駐アプリ（ホットキーでコピー）"
    $shortcut.Save()
}

function Uninstall-OneDriveStartup {
    [CmdletBinding()]
    param()
    $path = Get-OneDriveStartupShortcutPath
    if (Test-Path $path) {
        Remove-Item -Path $path -Force
    }
}

# ---- エクスプローラ右クリックメニューへの直接登録（全ファイル種別対象、HKCUのみ） ----

function Get-OneDriveContextMenuRegistrySubPath {
    <# HKEY_CURRENT_USERからの相対パス。"*"は「全ファイル種別」を表す実在のサブキー名。 #>
    "Software\Classes\*\shell\OneDriveShareLink"
}

function Test-OneDriveContextMenuRegistered {
    <#
        PowerShellのレジストリプロバイダー経由のcmdlet（Test-Path/New-Item等）は
        パス中の"*"をワイルドカードとして解釈しようとし、-LiteralPathを付けても
        New-Itemでは効かない（cmdlet側が非対応）。HKCU:\Software\Classes配下を
        丸ごと列挙しようとして事実上固まるため、.NETのMicrosoft.Win32.Registry
        APIを直接使い、ワイルドカード解釈を完全に回避する。
    #>
    [CmdletBinding()]
    param()
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey((Get-OneDriveContextMenuRegistrySubPath))
    if ($key) {
        $key.Close()
        return $true
    }
    return $false
}

function Install-OneDriveContextMenu {
    <#
        本家OneDriveのように「OneDrive同期フォルダ配下のみメニュー表示」を
        AppliesTo (AQS) で試したが、System.ItemFolderPathDisplayでのパス
        前方一致が実機で期待通り動作しなかった（マッチするはずのファイルでも
        メニュー自体が消える＝条件評価が失敗している挙動）。ドキュメントが薄く
        挙動が不安定な機能に依存するリスクが高いと判断し撤退。すべてのファイル
        種別を対象に常時表示する（OneDrive外のファイルではクリック時に警告）。
    #>
    [CmdletBinding()]
    param()
    $vbsPath = Join-Path $PSScriptRoot "Copy-OneDriveLink.vbs"

    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey((Get-OneDriveContextMenuRegistrySubPath))
    try {
        $key.SetValue("", "OneDrive共有リンクをコピー")

        $iconPath = Join-Path $PSScriptRoot "..\assets\icon.ico" | Resolve-Path -ErrorAction SilentlyContinue
        if ($iconPath) {
            $key.SetValue("Icon", $iconPath.Path)
        }

        $commandKey = $key.CreateSubKey("command")
        try {
            $cmd = "`"$env:WINDIR\System32\wscript.exe`" `"$vbsPath`" `"%1`""
            $commandKey.SetValue("", $cmd)
        }
        finally {
            $commandKey.Close()
        }
    }
    finally {
        $key.Close()
    }
}

function Uninstall-OneDriveContextMenu {
    [CmdletBinding()]
    param()
    $shellKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Classes\*\shell", $true)
    if ($shellKey) {
        try {
            $shellKey.DeleteSubKeyTree("OneDriveShareLink", $false)
        }
        finally {
            $shellKey.Close()
        }
    }
}

Export-ModuleMember -Function Get-OneDriveMessages, Get-OneDriveVersionInfo, ConvertTo-OneDriveDisplayDate, Get-OneDriveSyncFolders, Resolve-OneDriveServerFolderSegment, `
    Find-OneDriveSyncFolderMatch, ConvertTo-OneDriveUrl, ConvertTo-OneDriveRelativePath, `
    Format-OneDriveShareText, Get-OneDriveShareSegments, ConvertTo-ClipboardHtmlFragment, `
    Format-OneDriveShareHtml, Set-OneDriveClipboardContent, Get-OneDriveTeamChannelInfo, `
    Get-OneDriveConfigPath, Get-OneDriveDefaultConfig, Get-OneDriveConfig, `
    Save-OneDriveConfig, ConvertTo-OneDriveHotkeyModifierFlags, ConvertTo-OneDriveHotkeyDisplayText, `
    Get-OneDriveShareVariables, Expand-OneDriveShareTemplate, ConvertTo-OneDriveHotkeyComboKey, `
    Test-OneDriveHotkeyIsCommonShortcut, `
    Test-OneDriveSendToRegistered, Install-OneDriveSendTo, Uninstall-OneDriveSendTo, `
    Test-OneDriveStartupRegistered, Install-OneDriveStartup, Uninstall-OneDriveStartup, `
    Test-OneDriveContextMenuRegistered, Install-OneDriveContextMenu, Uninstall-OneDriveContextMenu
