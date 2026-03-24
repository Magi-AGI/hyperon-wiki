Param()

$envPath = Join-Path $PSScriptRoot "..\..\mcp\.env"
if (Test-Path $envPath) {
  Get-Content $envPath | ForEach-Object {
    if (-not $_ -or $_.StartsWith('#')) { return }
    $kv = $_.Split('=',2)
    if ($kv.Count -eq 2) { [System.Environment]::SetEnvironmentVariable($kv[0], $kv[1]) }
  }
}

if (-not $env:BROWSER_MCP_SERVER) {
  Write-Error "BROWSER_MCP_SERVER not set. Edit docs/mcp/.env or set environment variable."
  exit 1
}

Write-Host "Starting Browser Control MCP server..."
Write-Host " node $env:BROWSER_MCP_SERVER"
node $env:BROWSER_MCP_SERVER

