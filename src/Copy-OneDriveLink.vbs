' NOTE: WSH (VBScript) cannot reliably parse UTF-8/BOM script files, so this
' file is kept ASCII-only without Japanese comments (see ../CLAUDE.md).
' Launches Copy-OneDriveLink.ps1 hidden (no console flash) via WScript.Shell.
Option Explicit

Dim shell, fso, scriptDir, psScript, targetPath, cmd

If WScript.Arguments.Count < 1 Then
    WScript.Quit
End If
targetPath = WScript.Arguments(0)

Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = scriptDir & "\Copy-OneDriveLink.ps1"

Set shell = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & _
    Chr(34) & psScript & Chr(34) & " " & Chr(34) & targetPath & Chr(34)
shell.Run cmd, 0, False
