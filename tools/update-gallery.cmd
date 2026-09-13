@echo off
REM Double-click this file to regenerate images.json + thumbnails.
REM Scans the images\ folder and rebuilds the gallery manifest and thumbs\.

REM Windows PowerShell 5.1 reads a BOM-less UTF-8 .ps1 as ANSI, which garbles
REM the Chinese text inside it and makes it fail to parse. Re-add the BOM
REM automatically if some editor stripped it.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path '%~dp0' 'generate-manifest.ps1'; $b = [System.IO.File]::ReadAllBytes($p); if (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) { $t = [System.IO.File]::ReadAllText($p, (New-Object System.Text.UTF8Encoding($false))); [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($true))); Write-Host '[fix] re-added UTF-8 BOM to generate-manifest.ps1' -ForegroundColor Yellow }"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0generate-manifest.ps1"
echo.
pause
