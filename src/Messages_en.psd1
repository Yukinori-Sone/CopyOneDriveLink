@{
    AppName                          = 'Copy OneDrive Share Link'
    AlreadyRunningMessage             = 'Copy OneDrive Share Link is already running in the system tray.'
    TrayTooltipFormat                 = 'Copy OneDrive Share Link ({0})'
    MenuSettings                      = 'Settings...'
    MenuAbout                         = 'About'
    MenuExit                          = 'Exit'
    AboutMessageFormat                = "{0}`r`nVersion: {1} ({2})`r`n{3}"
    WarnMultipleSelected              = 'Multiple files are selected. Please select only one file and try again.'
    WarnNoSelection                   = 'Please select a single file in the active Explorer window and try again (the desktop is not supported).'
    CopiedBalloonTitle                = 'OneDrive share link copied'
    PersonalLibraryWarning            = 'Note: this file is in your personal OneDrive area. The link may not open for the recipient unless they already have access.'
    HotkeyRegisterFailedMessage       = 'Failed to register the hotkey (it may conflict with another application). Right-click the tray icon and choose Settings to change it.'
    StartupErrorMessageFormat         = "An error occurred during startup and the app will exit.`r`n`r`n{0}`r`n`r`nDetails: {1}"

    SettingsTitle                     = 'Copy OneDrive Share Link - Settings'
    TabGeneral                        = 'General'
    TabFormat                         = 'Format'
    FormatSubTabTeam                  = 'Teams / SharePoint'
    FormatSubTabPersonal              = 'Personal OneDrive'
    HotkeyGroupLabel                  = 'Hotkey (hold Ctrl/Alt/Shift and press the key you want to assign)'
    HotkeyHint                        = 'Note: this check only compares against a list of well-known common shortcuts. A combination of two or more modifier keys, such as Ctrl+Alt, is less likely to collide with other apps.'
    CaptureButtonIdle                 = 'Change key...'
    CaptureButtonWaiting              = 'Press a key...'
    ConflictLabelCurrent              = 'This is the hotkey currently used by this app.'
    ConflictLabelPrompt               = 'Press a key combination (Ctrl/Alt/Shift plus any key).'
    ConflictLabelNeedModifier         = 'Please hold Ctrl, Alt, or Shift while pressing the key.'
    ConflictLabelConflictFormat       = 'This combination is already registered as a global hotkey by another app ({0}). Please choose a different key.'
    ConflictLabelCommonShortcutFormat = 'This can be registered at the OS level, but it is a shortcut commonly used by many applications ({0}). While in use, that shortcut will stop working in other apps. A combination of two or more modifier keys, such as Ctrl+Alt, is recommended.'
    ConflictLabelAvailableFormat      = 'Available ({0}).'
    IntegrationSectionLabel           = 'Integrations (changes take effect immediately; no need to click Save)'
    IntegrationEnabledFormat          = 'Enabled "{0}".'
    IntegrationDisabledFormat         = 'Disabled "{0}".'
    IntegrationErrorFormat            = 'Error: {0}'
    SendToCheckboxLabel               = 'Add to the Explorer "Send to" menu'
    StartupCheckboxLabel              = 'Start automatically at logon (tray app)'
    ContextMenuCheckboxLabel          = 'Add directly to the right-click menu (applies to all file types)'
    VarSectionLabel                   = 'Available variables:'
    VarHeaderPlain                    = 'Plain text / HTML (shared)'
    VarHeaderHtml                     = 'HTML (linked)'
    VarSiteNameDesc                   = 'Site name'
    VarSiteLinkDesc                   = 'Site name, linked'
    VarChannelNameDesc                = 'Channel name'
    VarChannelLinkDesc                = 'Channel name, linked'
    VarRelativeDirDesc                = 'Folder part of the relative path'
    VarRelativeDirLinkDesc            = 'Folder part, linked'
    VarFileNameDesc                   = 'File name'
    VarFileLinkDesc                   = 'File name, linked'
    VarRelativePathDesc               = '= RelativeDir + FileName'
    VarRelativePathLinkDesc           = 'Full relative path, linked'
    VarUrlDesc                        = 'Full URL'
    VarUrlLinkDesc                    = 'Full URL, linked'
    TextTemplateLabel                 = 'When pasting as plain text'
    HtmlTemplateLabel                 = 'When pasting as HTML / rich text'
    HtmlHint                          = "Note: line breaks (Enter) are automatically converted to <br>. You can also write raw HTML tags directly for extra styling.`r`nNote: to keep the folder part unlinked and link only the file name, combine `$RelativeDir`$FileLink instead of using `$RelativePathLink."
    SaveButton                        = 'Save'
    CancelButton                      = 'Cancel'
    ResetButton                       = 'Reset to Defaults'

    SyncFolderNotFoundFormat          = 'This is not inside a OneDrive sync folder: {0}'
    CopyFailedMessageFormat           = "Failed to copy the OneDrive share link.`n`n{0}"

    DefaultTeamTextTemplate           = "Team       : `$SiteName`r`nChannel    : `$ChannelName`r`nFile       : `$RelativePath`r`nDirect URL : `$Url"
    DefaultTeamHtmlTemplate           = "Team    : `$SiteLink`r`nChannel : `$ChannelLink`r`nFolder  : `$RelativeDirLink`r`nFile    : `$FileLink"
    DefaultPersonalTextTemplate       = "File       : `$RelativePath`r`nDirect URL : `$Url"
    DefaultPersonalHtmlTemplate       = "Folder  : `$RelativeDirLink`r`nFile    : `$FileLink"
}
