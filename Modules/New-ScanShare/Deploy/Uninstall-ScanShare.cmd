@echo off
setlocal
title New Scan Share - Uninstall

rem Prefer PowerShell 7; fall back to Windows PowerShell 5.1.
set "PSEXE=powershell.exe"
where pwsh.exe >nul 2>nul && set "PSEXE=pwsh.exe"

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-ScanShare.ps1" %*

if errorlevel 1 (
    echo.
    echo Uninstall failed. Review the message above.
    pause
)
endlocal
