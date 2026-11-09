# 从项目根目录启动四个系统：单点登录、包装样机、三维建模、答题闯关。
# 某个子项目没有 node_modules 时会先 npm install。
# 用法：powershell -ExecutionPolicy Bypass -File .\start.ps1
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot

if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command npm -ErrorAction SilentlyContinue)) {
  throw '未找到 Node.js 或 npm。请先安装 Node.js 18 或更高版本。'
}

$apps = @(
  @{ Name = 'sso-api';    Dir = 'wego_sso\backend';            Npm = 'start'; Port = 3001; Url = 'http://127.0.0.1:3001' },
  @{ Name = 'sso-web';    Dir = 'wego_sso\frontend';           Npm = 'dev';   Port = 5174; Url = 'http://127.0.0.1:5174' },
  @{ Name = 'mockup-api'; Dir = 'wego_3d_texture\backend';     Npm = 'start'; Port = 3000; Url = 'http://127.0.0.1:3000' },
  @{ Name = 'mockup-web'; Dir = 'wego_3d_texture\frontend';    Npm = 'dev';   Port = 5173; Url = 'http://127.0.0.1:5173' },
  @{ Name = 'cad-web';    Dir = 'wego_fingertip_3d_web';       Npm = 'dev';   Port = 5175; Url = 'http://127.0.0.1:5175' },
  @{ Name = 'quiz-api';   Dir = 'wego_quiz_3d\backend';        Npm = 'start'; Port = 3002; Url = 'http://127.0.0.1:3002' },
  @{ Name = 'quiz-web';   Dir = 'wego_quiz_3d\frontend';       Npm = 'dev';   Port = 5176; Url = 'http://127.0.0.1:5176' }
)

function Test-Listening([int] $Port) {
  $lines = netstat -ano | Select-String -Pattern "LISTENING"
  return [bool]($lines | Select-String -Pattern ":$Port\s")
}

function Install-IfMissing([string] $Dir) {
  $full = Join-Path $Root $Dir
  if (-not (Test-Path (Join-Path $full 'package.json'))) {
    throw "找不到 $full\package.json"
  }
  $example = Join-Path $full '.env.example'
  $envFile = Join-Path $full '.env'
  if ((Test-Path $example) -and -not (Test-Path $envFile)) {
    Copy-Item $example $envFile
    Write-Host "已复制 $Dir\.env，请先填写数据库等配置。"
  }
  if (Test-Path (Join-Path $full 'node_modules')) {
    return
  }
  Write-Host "首次启动，正在安装依赖：$Dir"
  Push-Location $full
  try {
    & npm install
    if ($LASTEXITCODE -ne 0) { throw "npm install 失败：$Dir" }
  } finally {
    Pop-Location
  }
}

foreach ($app in $apps) {
  Install-IfMissing $app.Dir
  if (Test-Listening $app.Port) {
    Write-Host "已在运行，跳过 $($app.Name)  $($app.Url)"
    continue
  }
  $full = Join-Path $Root $app.Dir
  $npmArgs = if ($app.Npm -eq 'start') { 'start' } else { 'run dev' }
  $command = "`$Host.UI.RawUI.WindowTitle = 'wego $($app.Name)'; npm $npmArgs"
  Start-Process -FilePath 'powershell.exe' -WorkingDirectory $full -ArgumentList @(
    '-NoExit', '-NoProfile', '-Command', $command
  ) | Out-Null
  Write-Host "已启动 $($app.Name)  $($app.Url)"
}

Write-Host ''
Write-Host '单点登录  http://127.0.0.1:5174   接口 3001'
Write-Host '包装样机  http://127.0.0.1:5173   接口 3000'
Write-Host '三维建模  http://127.0.0.1:5175'
Write-Host '答题闯关  http://127.0.0.1:5176   接口 3002'
Write-Host '停止全部：powershell -ExecutionPolicy Bypass -File .\stop.ps1'
