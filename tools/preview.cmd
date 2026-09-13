@echo off
REM Double-click this file to preview the gallery locally
REM (starts a small local web server and opens your browser)

REM Node writes UTF-8; switch the console to UTF-8 so Chinese text isn't garbled
chcp 65001 >nul

where node >nul 2>nul
if errorlevel 1 (
    echo.
    echo   Node.js not found.
    echo   Install it from https://nodejs.org/  then run this file again.
    echo.
    pause
    exit /b 1
)

node "%~dp0preview.mjs"
pause
