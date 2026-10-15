@ECHO off
REM Provided by the node vcpkg port: run the corepack installed alongside this node.
REM The layout mirrors the official distribution (executable + node_modules/{npm,
REM corepack} + shims), so %~dp0 (this script's directory, trailing backslash
REM included) locates everything; no node/npm from PATH is needed.
REM
REM This file is deliberately ASCII-only: cmd.exe reads .cmd in the ANSI code
REM page, and non-ASCII comment bytes get mis-tokenized.
SETLOCAL
IF EXIST "%~dp0node.exe" (
  "%~dp0node.exe" "%~dp0node_modules\corepack\dist\corepack.js" %*
) ELSE (
  node "%~dp0node_modules\corepack\dist\corepack.js" %*
)
EXIT /b %ERRORLEVEL%