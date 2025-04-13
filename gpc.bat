@echo off
REM このバッチファイルは GenerateProjectContext.ps1 を簡単に実行するためのラッパーです。
REM PowerShellスクリプトと同じディレクトリに配置することを想定しています。

REM PowerShellスクリプトのパスを取得 (%~dp0 はこのバッチファイル自身のディレクトリ)
set SCRIPT_PATH="%~dp0GenerateProjectContext.ps1"

REM PowerShellを実行し、スクリプトに引数をすべて渡す (%*)
REM ExecutionPolicy を RemoteSigned に設定して実行 (環境によっては Bypass が必要かも)
powershell -ExecutionPolicy RemoteSigned -File %SCRIPT_PATH% %*

REM エラーレベルを保持して終了 (オプション)
exit /b %errorlevel%