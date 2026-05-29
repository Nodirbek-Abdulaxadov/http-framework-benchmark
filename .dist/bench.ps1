param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$StartCmd,
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [int]$Port = 8080
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

# Launch server
$proc = Start-Process -FilePath "powershell" -ArgumentList "-NoProfile","-Command",$StartCmd -WorkingDirectory $WorkDir -WindowStyle Hidden -PassThru

# Wait for /ping ready (max 60s)
$ready = $false
for ($i=0; $i -lt 120; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/ping" -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
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
& $BOMB -c 50 -d 3s -q "http://127.0.0.1:$Port/ping" | Out-Null

$endpoints = @(
    @{ path='/ping';        c=500;  d='15s' },
    @{ path='/json-small';  c=500;  d='15s' },
    @{ path='/json-large';  c=200;  d='15s' },
    @{ path='/cpu';         c=32;   d='15s' },
    @{ path='/async-delay'; c=1000; d='15s' }
)

foreach ($e in $endpoints) {
    $epName = $e.path.TrimStart('/')
    $outFile = Join-Path $OUT_DIR "$epName.json"
    Write-Host "  bench $($e.path) c=$($e.c) d=$($e.d)" -ForegroundColor Yellow
    $raw = & $BOMB -c $e.c -d $e.d -t 5s -l -o json "http://127.0.0.1:$Port$($e.path)"
    # Extract the JSON line (last non-empty line)
    $jsonLine = ($raw | Where-Object { $_ -match '^\{.*\}$' } | Select-Object -Last 1)
    if (-not $jsonLine) { $jsonLine = ($raw -join "`n") }
    [System.IO.File]::WriteAllText($outFile, $jsonLine, [System.Text.UTF8Encoding]::new($false))
}

Stop-OnPort $Port
Write-Host "$Name done" -ForegroundColor Green
