@{
    AppName                          = 'OneDrive共有リンクをコピー'
    AlreadyRunningMessage             = 'OneDrive共有リンクコピーは既にタスクトレイで起動中です。'
    TrayTooltipFormat                 = 'OneDrive共有リンクをコピー ({0})'
    MenuSettings                      = '設定...'
    MenuAbout                         = 'バージョン情報'
    MenuExit                          = '終了'
    AboutMessageFormat                = "{0}`r`nバージョン: {1} ({2})`r`n{3}"
    WarnMultipleSelected              = '複数のファイルが選択されています。1つだけ選択してから実行してください。'
    WarnNoSelection                   = 'アクティブなExplorerウィンドウでファイルが1つ選択されている状態で実行してください（デスクトップは非対応）。'
    CopiedBalloonTitle                = 'OneDrive共有リンクをコピーしました'
    PersonalLibraryWarning            = '※ 個人用OneDrive領域のファイルです。共有相手が既にアクセス権を持っていない場合、リンクを開けない可能性があります。'
    HotkeyRegisterFailedMessage       = 'ホットキーの登録に失敗しました（他のアプリと競合している可能性があります）。トレイアイコンを右クリック→設定 から変更してください。'
    StartupErrorMessageFormat         = "起動中にエラーが発生したため終了します。`r`n`r`n{0}`r`n`r`n詳細: {1}"

    SettingsTitle                     = 'OneDrive共有リンクコピー - 設定'
    TabGeneral                        = '全般'
    TabFormat                         = 'フォーマット'
    FormatSubTabTeam                  = 'Teams/SharePoint'
    FormatSubTabPersonal              = '個人用OneDrive'
    HotkeyGroupLabel                  = 'ホットキー（Ctrl/Alt/Shiftのいずれかを押しながら、確定したいキーを押してください）'
    HotkeyHint                        = '※ このチェックは既知の定番ショートカット一覧との照合のみです。Ctrl+Altなど2つ以上の修飾キーの組み合わせの方が、他アプリと重複しにくく安全です。'
    CaptureButtonIdle                 = 'キーを押して変更...'
    CaptureButtonWaiting              = 'キーを押してください...'
    ConflictLabelCurrent              = '現在このアプリで使用中のホットキーです。'
    ConflictLabelPrompt               = 'キーを入力してください（Ctrl/Alt/Shiftのいずれか＋任意のキー）'
    ConflictLabelNeedModifier         = 'Ctrl/Alt/Shiftのいずれかを押しながら指定してください。'
    ConflictLabelConflictFormat       = '他のアプリがグローバルホットキーとして登録済みのため使用できません（{0}）。別のキーを指定してください。'
    ConflictLabelCommonShortcutFormat = 'OS上は登録できますが、多くのアプリで一般的に使われるショートカットです（{0}）。使用中、他アプリでこのキーが効かなくなります。Ctrl+Altなど2つ以上の修飾キーの組み合わせを推奨します。'
    ConflictLabelAvailableFormat      = '利用可能です（{0}）。'
    IntegrationSectionLabel           = '連携設定（クリックで即座に有効/無効を切り替えます。保存ボタンは不要です）'
    IntegrationEnabledFormat          = '「{0}」を有効にしました。'
    IntegrationDisabledFormat         = '「{0}」を無効にしました。'
    IntegrationErrorFormat            = 'エラー: {0}'
    SendToCheckboxLabel               = 'エクスプローラの「送る」に登録する'
    StartupCheckboxLabel              = 'ログオン時に自動起動する（タスクトレイ常駐）'
    ContextMenuCheckboxLabel          = '右クリックメニューに直接登録する（すべてのファイル種別が対象になります）'
    VarSectionLabel                   = '使用できる変数:'
    VarHeaderPlain                    = 'プレーンテキスト/HTML共通'
    VarHeaderHtml                     = 'HTML用（リンク付き）'
    VarSiteNameDesc                   = 'サイト名'
    VarSiteLinkDesc                   = 'サイト名・リンク'
    VarChannelNameDesc                = 'チャネル名'
    VarChannelLinkDesc                = 'チャネル名・リンク'
    VarRelativeDirDesc                = '相対パスのフォルダ部分'
    VarRelativeDirLinkDesc            = 'フォルダ部分・リンク'
    VarFileNameDesc                   = 'ファイル名'
    VarFileLinkDesc                   = 'ファイル名・リンク'
    VarRelativePathDesc               = '=RelativeDir+FileName'
    VarRelativePathLinkDesc           = '相対パス全体・リンク'
    VarUrlDesc                        = '完全URL'
    VarUrlLinkDesc                    = '完全URL・リンク'
    TextTemplateLabel                 = 'プレーンテキスト貼り付け時'
    HtmlTemplateLabel                 = 'HTML/リッチテキスト貼り付け時'
    HtmlHint                          = "※ Enterキーの改行は自動的に<br>に変換されます。装飾用の生HTMLタグもそのまま書けます。`r`n※ フォルダ部分は非リンクでファイル名だけリンクにしたい場合は、`$RelativePathLinkの代わりに `$RelativeDir`$FileLink のように組み合わせてください。"
    SaveButton                        = '保存'
    CancelButton                      = 'キャンセル'
    ResetButton                       = '既定値に戻す'

    SyncFolderNotFoundFormat          = 'OneDrive同期対象フォルダではありません: {0}'
    CopyFailedMessageFormat           = "OneDrive共有リンクのコピーに失敗しました。`n`n{0}"

    DefaultTeamTextTemplate           = "チーム   : `$SiteName`r`nチャネル : `$ChannelName`r`nファイル : `$RelativePath`r`n直接URL  : `$Url"
    DefaultTeamHtmlTemplate           = "チーム   : `$SiteLink`r`nチャネル : `$ChannelLink`r`nフォルダ : `$RelativeDirLink`r`nファイル : `$FileLink"
    DefaultPersonalTextTemplate       = "ファイル : `$RelativePath`r`n直接URL  : `$Url"
    DefaultPersonalHtmlTemplate       = "フォルダ : `$RelativeDirLink`r`nファイル : `$FileLink"
}
