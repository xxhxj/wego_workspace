# 按端口停止四个系统。只结束正在监听这些端口的进程。
$ErrorActionPreference = 'Stop'
$ports = 3000, 3001, 3002, 5173, 5174, 5175, 5176
$pids = New-Object System.Collections.Generic.HashSet[int]

foreach ($port in $ports) {
  $matches = netstat -ano | Select-String -Pattern "LISTENING" | Select-String -Pattern ":$port\s"
  foreach ($line in $matches) {
    $parts = ($line.ToString() -split '\s+') | Where-Object { $_ -ne '' }
    $procId = 0
    if ([int]::TryParse($parts[-1], [ref] $procId) -and $procId -gt 0) {
      [void]$pids.Add($procId)
    }
  }
}

if ($pids.Count -eq 0) {
  Write-Host '这些端口上没有正在运行的服务。'
  exit 0
}

foreach ($procId in $pids) {
  Write-Host "结束进程 $procId"
  & taskkill /F /T /PID $procId | Out-Null
}

Write-Host '已停止。'
