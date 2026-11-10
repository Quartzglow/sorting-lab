@echo off
setlocal
cd /d "%~dp0"
mode con: cols=120 lines=40 >nul 2>nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SortingLab.ps1"
if errorlevel 1 pause
