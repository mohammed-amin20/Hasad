@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mock_supabase.ps1" %*
exit /b %errorlevel%
