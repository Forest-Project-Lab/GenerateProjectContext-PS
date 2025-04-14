@echo off

rem --- (1) chcp の出力から数字だけを取り出して OLDCP に代入 ---
for /f "tokens=* delims=" %%I in ('chcp ^| findstr /r "[0-9][0-9]*"') do (
    for %%J in (%%I) do set "OLDCP=%%J"
)

rem --- (2) とりあえず UTF-8 に変更 ---
chcp 65001 >nul

rem --- (3) PowerShell の実行 ---
powershell -NoProfile -ExecutionPolicy RemoteSigned -Command ^
  "try { $oldEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); & '%~dp0GenerateProjectContext.ps1' %* } finally { [Console]::OutputEncoding = $oldEnc }"

rem --- (4) 終わったら元のコードページへ戻す ---
chcp %OLDCP% >nul

exit /b %errorlevel%
