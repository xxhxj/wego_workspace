@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

rem 只用 Git for Windows 的 bash；C:\Windows\System32\bash.exe 是 WSL，找不到 Windows 的 Node
set "BASH_EXE="
set "GIT_DIR="
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\GitForWindows" /v InstallPath 2^>nul ^| findstr /i "InstallPath"') do if not defined GIT_DIR set "GIT_DIR=%%B"
if not defined GIT_DIR for /f "tokens=2,*" %%A in ('reg query "HKCU\SOFTWARE\GitForWindows" /v InstallPath 2^>nul ^| findstr /i "InstallPath"') do if not defined GIT_DIR set "GIT_DIR=%%B"
if defined GIT_DIR if exist "%GIT_DIR%\bin\bash.exe" set "BASH_EXE=%GIT_DIR%\bin\bash.exe"

if not defined BASH_EXE if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "BASH_EXE=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if not defined BASH_EXE if exist "D:\Program Files\Git\bin\bash.exe" set "BASH_EXE=D:\Program Files\Git\bin\bash.exe"
if not defined BASH_EXE if exist "D:\Git\bin\bash.exe" set "BASH_EXE=D:\Git\bin\bash.exe"
if not defined BASH_EXE if exist "E:\Program Files\Git\bin\bash.exe" set "BASH_EXE=E:\Program Files\Git\bin\bash.exe"

if not defined BASH_EXE for /f "delims=" %%I in ('where git 2^>nul') do (
  if not defined BASH_EXE if exist "%%~dpI..\bin\bash.exe" set "BASH_EXE=%%~dpI..\bin\bash.exe"
)

if not defined BASH_EXE (
  echo 未找到 Git Bash，请安装 Git for Windows（不要使用 WSL 的 bash）。
  echo 下载：https://git-scm.com/download/win
  pause
  exit /b 1
)
echo 使用 Git Bash：%BASH_EXE%

set "OUT=%~1"
if "%OUT%"=="" set /p "OUT=输出目录（留空 = 当前 deploy\dist）: "
if "%OUT%"=="" set "OUT=%~dp0dist"

set "SERVER_ROOT=%~2"
if "%SERVER_ROOT%"=="" set /p "SERVER_ROOT=服务器部署目录（留空 = /opt/wego）: "
if "%SERVER_ROOT%"=="" set "SERVER_ROOT=/opt/wego"

set "OUT=%OUT:"=%"
set "SERVER_ROOT=%SERVER_ROOT:"=%"

if exist "%OUT%\wego-bundle" (
  choice /c YN /m "输出目录已有 wego-bundle，覆盖吗？"
  if errorlevel 2 (
    echo 已取消。
    pause
    exit /b 0
  )
  set "FORCE_BUNDLE=1"
)

echo.
echo 输出目录：%OUT%
echo 服务器目录：%SERVER_ROOT%
echo 开始构建四个前端并打包，请稍候...
echo.

"%BASH_EXE%" "./build-bundle.sh" "%OUT%" "%SERVER_ROOT%"
if errorlevel 1 (
  echo.
  echo 打包失败，请查看上面的错误信息。
  pause
  exit /b 1
)

echo.
echo 打包完成：%OUT%\wego-bundle.tar.gz
pause
