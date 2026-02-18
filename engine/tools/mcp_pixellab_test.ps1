$ErrorActionPreference = 'Stop'

$cfgPath = Join-Path $env:APPDATA 'Trae\User\mcp.json'
if (-not (Test-Path $cfgPath)) {
  throw "Arquivo não encontrado: $cfgPath"
}

$cfg = Get-Content -Raw $cfgPath | ConvertFrom-Json
$server = $cfg.mcpServers.pixellab
if (-not $server) {
  throw 'Servidor MCP "pixellab" não encontrado em mcp.json'
}

$url = [string]$server.url
$auth = [string]$server.headers.Authorization

$baseHeaders = @{
  Authorization = $auth
  Accept        = 'application/json, text/event-stream'
  'Content-Type'= 'application/json'
}

function Invoke-McpJsonRpc {
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][hashtable]$Headers,
    [Parameter(Mandatory=$true)][string]$Body
  )
  return Invoke-WebRequest -UseBasicParsing -Method Post -Uri $Url -Headers $Headers -Body $Body
}

function Get-McpJsonRpcFromResponseText {
  param([Parameter(Mandatory=$true)][string]$Text)
  $trim = $Text.Trim()
  if ($trim.StartsWith('{') -or $trim.StartsWith('[')) {
    try { return @($trim | ConvertFrom-Json) } catch { return @() }
  }
  $msgs = @()
  $lines = $Text -split "`r?`n"
  foreach ($line in $lines) {
    if ($line.StartsWith('data: ')) {
      $json = $line.Substring(6).Trim()
      if ($json -and ($json.StartsWith('{') -or $json.StartsWith('['))) {
        try {
          $parsed = $json | ConvertFrom-Json
          if ($parsed -is [System.Array]) { $msgs += $parsed } else { $msgs += @($parsed) }
        } catch {}
      }
    }
  }
  return $msgs
}

$initBodyObj = @{ 
  jsonrpc='2.0'; id=1; method='initialize';
  params=@{ 
    protocolVersion='2025-03-26';
    clientInfo=@{ name='trae-smoketest'; version='1.0' };
    capabilities=@{ tools=@{}; resources=@{}; prompts=@{}; logging=@{} }
  }
}
$initBody = ($initBodyObj | ConvertTo-Json -Depth 8 -Compress)
$initResp = Invoke-McpJsonRpc -Url $url -Headers $baseHeaders -Body $initBody
Write-Host ('[MCP] initialize status=' + $initResp.StatusCode)

$notifBodyObj = @{ jsonrpc='2.0'; method='notifications/initialized'; params=@{} }
$notifBody = ($notifBodyObj | ConvertTo-Json -Depth 4 -Compress)
$notifResp = Invoke-McpJsonRpc -Url $url -Headers $baseHeaders -Body $notifBody
Write-Host ('[MCP] notifications/initialized status=' + $notifResp.StatusCode)

$toolsMethods = @('engine/tools/list','tools/list')
$toolsResp = $null
$toolsMethodUsed = $null
foreach ($m in $toolsMethods) {
  $toolsBodyObj = @{ jsonrpc='2.0'; id=2; method=$m; params=@{} }
  $toolsBody = ($toolsBodyObj | ConvertTo-Json -Depth 6 -Compress)
  try {
    $toolsResp = Invoke-McpJsonRpc -Url $url -Headers $baseHeaders -Body $toolsBody
    $toolsMethodUsed = $m
    break
  } catch {
    continue
  }
}
if (-not $toolsResp) { throw 'Falha ao chamar tools/list (tentou engine/tools/list e tools/list)' }
Write-Host ('[MCP] ' + $toolsMethodUsed + ' status=' + $toolsResp.StatusCode)

$messages = Get-McpJsonRpcFromResponseText -Text $toolsResp.Content
$payload = $null
foreach ($m in $messages) {
  if ($m -and $m.id -eq 2 -and $m.result -and $m.result.tools) { $payload = $m; break }
}
if (-not $payload) { throw ($toolsMethodUsed + ' não retornou payload parseável') }

$names = @($payload.result.tools | ForEach-Object { $_.name })
Write-Host ('[MCP] tools_count=' + $names.Count)
Write-Host ('[MCP] tools_preview=' + (($names | Select-Object -First 20) -join ', '))

