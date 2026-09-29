@echo off
setlocal
title New Scan Share - Install

rem Prefer PowerShell 7; fall back to Windows PowerShell 5.1.
set "PSEXE=powershell.exe"
where pwsh.exe >nul 2>nul && set "PSEXE=pwsh.exe"

rem -ExecutionPolicy Bypass keeps the script running when the machine's policy
rem would otherwise block an unsigned local script.
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ScanShare.ps1" %*

if errorlevel 1 (
    echo.
    echo The installer did not finish cleanly. Review the message above.
    pause
)
endlocal
