$ErrorActionPreference = 'Continue'
$ROOT = 'C:\Users\nbkab\OneDrive\Ishchi stol\bench'
$BOMB = "$ROOT\.dist\bombardier.exe"
$EXE  = "$ROOT\_my\jwc-app\bin\release\jwc-app.exe"
$DIR  = "$ROOT\_my\jwc-app"
$OUT  = "$ROOT\.dist\results\jwc-app\refresh15s"
New-Item -ItemType Directory -Force -Path $OUT | Out-Null

$endpoints = @(
    @{ path='/ping';        c=500  },
    @{ path='/json-small';  c=500  },
    @{ path='/json-large';  c=200  },
    @{ path='/cpu';         c=32   },
    @{ path='/async-delay'; c=1000 }
)

function Stop-OnPort([int]$Port) {
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conns) { try { Stop-Process -Id $c.OwningProcess -Force -ErrorAction Stop } catch {} }
    Start-Sleep -Milliseconds 800
}

Stop-OnPort 8080
Write-Host "[jwc-app] starting" -ForegroundColor Cyan
$proc = Start-Process -FilePath $EXE -WorkingDirectory $DIR -WindowStyle Hidden -PassThru

$ready = $false
for ($i=0; $i -lt 60; $i++) {
    try {
        $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/ping' -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { Start-Sleep -Milliseconds 500 }
}
if (-not $ready) { Write-Host "NOT READY" -ForegroundColor Red; exit 1 }
Write-Host "  ready (${i}*500ms)" -ForegroundColor Green

# warmup 3s
& $BOMB -c 50 -d 3s -q "http://127.0.0.1:8080/ping" | Out-Null

foreach ($e in $endpoints) {
    $epName = $e.path.TrimStart('/')
    $outFile = Join-Path $OUT "$epName.json"
    Write-Host "[jwc-app] $($e.path) 15s c=$($e.c)" -ForegroundColor Cyan
    $raw = & $BOMB -c $e.c -d 15s -t 5s -l -o json "http://127.0.0.1:8080$($e.path)"
    $jsonLine = ($raw | Where-Object { $_ -match '^\{' } | Select-Object -Last 1)
    if ($jsonLine) {
        [System.IO.File]::WriteAllText($outFile, $jsonLine, [System.Text.UTF8Encoding]::new($false))
        try {
            $j = $jsonLine | ConvertFrom-Json
            $rps   = [math]::Round($j.result.rps.mean, 0)
            $rpsMx = [math]::Round($j.result.rps.max, 0)
            $p50   = [math]::Round($j.result.latency.percentiles.'50' / 1000, 2)
            $p90   = [math]::Round($j.result.latency.percentiles.'90' / 1000, 2)
            $p99   = [math]::Round($j.result.latency.percentiles.'99' / 1000, 2)
            $r2x   = $j.result.req2xx
            $bytes = $j.result.bytesRead
            $err   = if ($j.result.errors) { ($j.result.errors | Measure-Object -Property count -Sum).Sum } else { 0 }
            Write-Host ("  rps={0} max={1} p50={2}ms p90={3}ms p99={4}ms 2xx={5} bytes={6} err={7}" -f $rps,$rpsMx,$p50,$p90,$p99,$r2x,$bytes,$err)
        } catch {
            Write-Host "  parse error: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "  no output" -ForegroundColor Yellow
    }
    Start-Sleep -Seconds 2
}

try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
Stop-OnPort 8080
Write-Host "DONE" -ForegroundColor Green
