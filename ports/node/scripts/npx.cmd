@ECHO off
REM Provided by the node vcpkg port: run the npx bundled with this node.
REM The layout mirrors the official node distribution (executable +
REM node_modules/{npm,corepack} + shims), so %~dp0 (this script's directory,
REM trailing backslash included) is enough to locate everything -- the shim
REM never depends on a node/npm from PATH.
REM
REM NOTE: this file is deliberately ASCII-only. cmd.exe reads .cmd in the
REM ANSI code page; non-ASCII comment bytes get mis-tokenized and cmd then
REM tries to run comment fragments as commands ("The syntax of the command is
REM incorrect"). Keep the Chinese explanation in the port docs instead.
SETLOCAL
IF EXIST "%~dp0node.exe" (
  "%~dp0node.exe" "%~dp0node_modules\npm\bin\npx-cli.js" %*
) ELSE (
  node "%~dp0node_modules\npm\bin\npx-cli.js" %*
)
EXIT /b %ERRORLEVEL%
