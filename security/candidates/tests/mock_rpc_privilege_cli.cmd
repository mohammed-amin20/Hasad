@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mock_rpc_privilege_cli.ps1" %*
exit /b %errorlevel%
