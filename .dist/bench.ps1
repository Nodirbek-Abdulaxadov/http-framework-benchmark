param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$StartCmd,
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [int]$Port = 8080,
    # jwc's native binary binds [::] and Windows defaults IPV6_V6ONLY to on, so
    # it is only reachable over IPv6. Everything else listens on 0.0.0.0.
    [string]$BindHost = '127.0.0.1'
)

$ErrorActionPreference = 'Stop'
$BOMB = "C:\Users\nbkab\OneDrive\Ishchi stol\bench\.dist\bombardier.exe"
$RESULTS = "C:\Users\nbkab\OneDrive\Ishchi stol\bench\.dist\results"
$OUT_DIR = Join-Path $RESULTS $Name
New-Item -ItemType Directory -Force -Path $OUT_DIR | Out-Null

function Stop-OnPort([int]$Port) {
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
        try { Stop-Process -Id $c.OwningProcess -Force -ErrorAction Stop } catch {}
    }
    Start-Sleep -Milliseconds 800
}

Write-Host "=== $Name ===" -ForegroundColor Cyan
Stop-OnPort $Port

# Reset the world table so every server meets the same physical layout and no
# autovacuum fires mid-measurement — see .dist/reset-db.js.
$reset = Join-Path $PSScriptRoot 'reset-db.js'
if (Test-Path $reset) {
    $out = & node $reset
    if ($LASTEXITCODE -eq 0) { Write-Host "  $out" -ForegroundColor DarkGray }
    else { Write-Host "  DB reset skipped (exit $LASTEXITCODE)" -ForegroundColor Yellow }
}

# Launch server
Start-Process -FilePath "powershell" -ArgumentList "-NoProfile","-Command",$StartCmd -WorkingDirectory $WorkDir -WindowStyle Hidden | Out-Null

# Wait for /ping ready (max 60s)
$ready = $false
for ($i=0; $i -lt 120; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "http://$($BindHost):$Port/ping" -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { Start-Sleep -Milliseconds 500 }
}
if (-not $ready) {
    Write-Host "FAILED to start $Name" -ForegroundColor Red
    Stop-OnPort $Port
    exit 1
}
Write-Host "$Name started (took $($i*0.5)s)" -ForegroundColor Green

# Warm-up
& $BOMB -c 50 -d 3s -q "http://$($BindHost):$Port/ping" | Out-Null

# DB tier (/db, /queries, /updates) is implemented by every stack now, but it
# only runs against a seeded world table — see .dist/setup-linux.sh.
$endpoints = @(
    @{ path='/ping';        c=500;  d='15s' },
    @{ path='/json-small';  c=500;  d='15s' },
    @{ path='/json-large';  c=200;  d='15s' },
    @{ path='/cpu';         c=32;   d='15s' },
    @{ path='/async-delay'; c=1000; d='15s' },
    @{ path='/db';          c=64;   d='15s' },
    @{ path='/queries';     c=64;   d='15s'; query='?queries=20' },
    @{ path='/updates';     c=64;   d='15s'; query='?queries=20' }
)

foreach ($e in $endpoints) {
    $epName = $e.path.TrimStart('/')
    $outFile = Join-Path $OUT_DIR "$epName.json"
    $qs = if ($e.ContainsKey('query')) { $e.query } else { '' }
    Write-Host "  bench $($e.path)$qs c=$($e.c) d=$($e.d)" -ForegroundColor Yellow
    $raw = & $BOMB -c $e.c -d $e.d -t 5s -l -o json "http://$($BindHost):$Port$($e.path)$qs"
    # Extract the JSON line (last non-empty line)
    $jsonLine = ($raw | Where-Object { $_ -match '^\{.*\}$' } | Select-Object -Last 1)
    if (-not $jsonLine) { $jsonLine = ($raw -join "`n") }
    [System.IO.File]::WriteAllText($outFile, $jsonLine, [System.Text.UTF8Encoding]::new($false))
}

Stop-OnPort $Port
Write-Host "$Name done" -ForegroundColor Green
