Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
root = files.GetParentFolderName(WScript.ScriptFullName)
shell.Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & root & "\install.ps1""", 1, False
