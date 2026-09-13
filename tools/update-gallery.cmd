@echo off
REM Double-click this file to regenerate images.json
REM (scans the images\ folder and rebuilds the gallery manifest)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0generate-manifest.ps1"
echo.
pause
