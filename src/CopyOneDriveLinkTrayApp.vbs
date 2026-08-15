' NOTE: WSH (VBScript) cannot reliably parse UTF-8/BOM script files, so this
' file is kept ASCII-only without Japanese comments (see ../CLAUDE.md).
' Launches CopyOneDriveLinkTrayApp.ps1 hidden (no console flash) via WScript.Shell.
Option Explicit

Dim shell, fso, scriptDir, psScript, cmd

Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = scriptDir & "\CopyOneDriveLinkTrayApp.ps1"

Set shell = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & _
    Chr(34) & psScript & Chr(34)
shell.Run cmd, 0, False
