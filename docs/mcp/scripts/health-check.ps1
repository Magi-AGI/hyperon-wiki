Param()

$envPath = Join-Path $PSScriptRoot "..\..\mcp\.env"
if (Test-Path $envPath) {
  Get-Content $envPath | ForEach-Object {
    if (-not $_ -or $_.StartsWith('#')) { return }
    $kv = $_.Split('=',2)
    if ($kv.Count -eq 2) { [System.Environment]::SetEnvironmentVariable($kv[0], $kv[1]) }
  }
}

if (-not $env:EXTENSION_SECRET) { Write-Error "EXTENSION_SECRET is not set"; exit 1 }
if (-not $env:BROWSER_MCP_SERVER) { Write-Error "BROWSER_MCP_SERVER is not set"; exit 1 }

node (Join-Path $PSScriptRoot "health-check.mjs")

