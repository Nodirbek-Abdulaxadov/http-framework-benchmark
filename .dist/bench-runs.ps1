param([int]$Runs = 3)

$ErrorActionPreference = 'Continue'
$ROOT     = 'C:\Users\nbkab\OneDrive\Ishchi stol\bench'
$BOMB     = "$ROOT\.dist\bombardier.exe"
$RESULTS  = "$ROOT\.dist\results"

$servers = @(
    @{ Name='dotnet-minimal';   Dir="$ROOT\dotnet-minimal";        Cmd='dotnet ./publish/dotnet-minimal.dll --urls http://0.0.0.0:8080' },
    @{ Name='go-fiber';         Dir="$ROOT\go-fiber";              Cmd='./go-fiber.exe' },
    @{ Name='node-fastify';     Dir="$ROOT\node-fastify";          Cmd='node "index,js"' },
    @{ Name='python-fastapi';   Dir="$ROOT\python-fastapi";        Cmd='python -m uvicorn main:app --host 0.0.0.0 --port 8080 --workers 1 --log-level warning' },
    @{ Name='rust-axum';        Dir="$ROOT\rust-axum";             Cmd='./target/release/benchmark.exe' },
    @{ Name='jwc-app';          Dir="$ROOT\_my\jwc-app";           Cmd='./bin/release/jwc-app.exe' },
    @{ Name='liteapi-managed';  Dir="$ROOT\_my\liteapi";           Cmd='dotnet ./publish/liteapi-managed.dll' },
    @{ Name='liteapi-rust';     Dir="$ROOT\_my\liteapi-rust";      Cmd='dotnet ./publish/liteapi-rust.dll' }
)

$endpoints = @(
    @{ path='/ping';        c=500;  d='15s' },
    @{ path='/json-small';  c=500;  d='15s' },
    @{ path='/json-large';  c=200;  d='15s' },
    @{ path='/cpu';         c=32;   d='15s' },
    @{ path='/async-delay'; c=1000; d='15s' }
)

function Stop-OnPort([int]$Port) {
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conns) { try { Stop-Process -Id $c.OwningProcess -Force -ErrorAction Stop } catch {} }
    Start-Sleep -Milliseconds 800
}

function Run-Server($s, [int]$Run) {
    $port = 8080
    $outDir = Join-Path $RESULTS "$($s.Name)\run$Run"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    Write-Host "[$($s.Name) run $Run] start" -ForegroundColor Cyan
    Stop-OnPort $port

    Start-Process -FilePath "powershell" `
        -ArgumentList "-NoProfile","-Command",$s.Cmd `
        -WorkingDirectory $s.Dir -WindowStyle Hidden | Out-Null

    $ready = $false
    for ($i=0; $i -lt 120; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port/ping" -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) {
        Write-Host "[$($s.Name) run $Run] FAILED to start" -ForegroundColor Red
        Stop-OnPort $port
        return
    }
    Write-Host "[$($s.Name) run $Run] ready (${i}*500ms)" -ForegroundColor Green

    # Warm-up
    & $BOMB -c 50 -d 3s -q "http://127.0.0.1:$port/ping" | Out-Null

    foreach ($e in $endpoints) {
        $epName = $e.path.TrimStart('/')
        $outFile = Join-Path $outDir "$epName.json"
        $raw = & $BOMB -c $e.c -d $e.d -t 5s -l -o json "http://127.0.0.1:$port$($e.path)"
        $jsonLine = ($raw | Where-Object { $_ -match '^\{.*\}$' } | Select-Object -Last 1)
        if (-not $jsonLine) { $jsonLine = ($raw -join "`n") }
        [System.IO.File]::WriteAllText($outFile, $jsonLine, [System.Text.UTF8Encoding]::new($false))

        try {
            $j = $jsonLine | ConvertFrom-Json
            $rps = [math]::Round($j.result.rps.mean, 1)
            $p99us = [math]::Round($j.result.latency.percentiles.'99', 1)
            $err = if ($j.result.errors) { ($j.result.errors | Measure-Object -Property count -Sum).Sum } else { 0 }
            Write-Host ("  {0,-13} rps={1,10:N1}  p99={2,9:N1}us  err={3}" -f $e.path, $rps, $p99us, $err)
        } catch {
            Write-Host "  $($e.path) -- (json parse failed)" -ForegroundColor Yellow
        }
    }

    Stop-OnPort $port
    Start-Sleep -Seconds 2  # cool-down so the next server starts clean
}

for ($r = 1; $r -le $Runs; $r++) {
    Write-Host "================ RUN $r / $Runs ================" -ForegroundColor Magenta
    foreach ($s in $servers) {
        try { Run-Server $s $r }
        catch { Write-Host "[$($s.Name) run $r] EXCEPTION: $_" -ForegroundColor Red }
        # Make sure the port is free before the next server.
        Stop-OnPort 8080
        Start-Sleep -Seconds 2
    }
}

Write-Host "ALL DONE" -ForegroundColor Green
