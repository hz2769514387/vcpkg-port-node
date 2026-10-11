@ECHO off
REM 由 node vcpkg port 提供：运行与本 node 一起装出来的那份 npx。
REM 布局与 node 官方发行版一致（可执行 + node_modules/{npm,corepack} + 垫片）。
REM 用 %~dp0（本脚本所在目录，末尾自带反斜杠）相对定位，不依赖 PATH 上的 node/npm。
SETLOCAL
IF EXIST "%~dp0node.exe" (
  "%~dp0node.exe" "%~dp0node_modules\npm\bin\npx-cli.js" %*
) ELSE (
  node "%~dp0node_modules\npm\bin\npx-cli.js" %*
)
EXIT /b %ERRORLEVEL%
