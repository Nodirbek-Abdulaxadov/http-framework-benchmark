param([int]$Run = 1, [int]$Sec = 5)

$ErrorActionPreference = 'Continue'
$ROOT = 'C:\Users\nbkab\OneDrive\Ishchi stol\bench'
$BOMB = "$ROOT\.dist\bombardier.exe"
$RESULTS = "$ROOT\.dist\results"

# (Name, Exe, ArgList, WorkDir)
$servers = @(
    @{ Name='dotnet-minimal';  Exe='dotnet'; Args='./publish/dotnet-minimal.dll','--urls','http://0.0.0.0:8080'; Dir="$ROOT\dotnet-minimal" },
    @{ Name='go-fiber';        Exe="$ROOT\go-fiber\go-fiber.exe"; Args=@();                                       Dir="$ROOT\go-fiber" },
    @{ Name='node-fastify';    Exe='node'; Args='index,js';                                                       Dir="$ROOT\node-fastify" },
    @{ Name='python-fastapi';  Exe='python'; Args='-m','uvicorn','main:app','--host','0.0.0.0','--port','8080','--workers','1','--log-level','warning'; Dir="$ROOT\python-fastapi" },
    @{ Name='rust-axum';       Exe="$ROOT\rust-axum\target\release\benchmark.exe"; Args=@();                       Dir="$ROOT\rust-axum" },
    @{ Name='jwc-app';         Exe="$ROOT\_my\jwc-app\bin\release\jwc-app.exe"; Args=@();                          Dir="$ROOT\_my\jwc-app" },
    @{ Name='liteapi-managed'; Exe='dotnet'; Args='./publish/liteapi-managed.dll';                                 Dir="$ROOT\_my\liteapi" },
    @{ Name='liteapi-rust';    Exe='dotnet'; Args='./publish/liteapi-rust.dll';                                    Dir="$ROOT\_my\liteapi-rust" }
)

$endpoints = @(
    @{ path='/ping';        c=500 },
    @{ path='/json-small';  c=500 },
    @{ path='/json-large';  c=200 },
    @{ path='/cpu';         c=32 },
    @{ path='/async-delay'; c=1000 }
)

function Stop-OnPort([int]$Port) {
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conns) { try { Stop-Process -Id $c.OwningProcess -Force -ErrorAction Stop } catch {} }
    Start-Sleep -Milliseconds 500
}

Write-Host "=========== RUN $Run (${Sec}s per endpoint) ==========="
foreach ($s in $servers) {
    $outDir = Join-Path $RESULTS "$($s.Name)\run$Run"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    Stop-OnPort 8080

    Write-Host ""
    Write-Host "[$($s.Name)] starting" -ForegroundColor Cyan
    $startArgs = @{
        FilePath = $s.Exe
        WindowStyle = 'Hidden'
        WorkingDirectory = $s.Dir
        PassThru = $true
    }
    if ($s.Args -and $s.Args.Count -gt 0) { $startArgs.ArgumentList = $s.Args }

    try {
        $proc = Start-Process @startArgs
    } catch {
        Write-Host "  start FAILED: $_" -ForegroundColor Red
        continue
    }

    $ready = $false
    for ($i=0; $i -lt 60; $i++) {
        try {
            $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/ping' -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) {
        Write-Host "  NOT READY (after 30s)" -ForegroundColor Red
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        Stop-OnPort 8080
        continue
    }
    Write-Host "  ready (${i}*500ms)" -ForegroundColor Green

    # warmup
    & $BOMB -c 50 -d 2s -q "http://127.0.0.1:8080/ping" | Out-Null

    foreach ($e in $endpoints) {
        $epName = $e.path.TrimStart('/')
        $outFile = Join-Path $outDir "$epName.json"
        $raw = & $BOMB -c $e.c -d "${Sec}s" -t 5s -l -o json "http://127.0.0.1:8080$($e.path)"
        $jsonLine = ($raw | Where-Object { $_ -match '^\{' } | Select-Object -Last 1)
        if ($jsonLine) {
            [System.IO.File]::WriteAllText($outFile, $jsonLine, [System.Text.UTF8Encoding]::new($false))
            try {
                $j = $jsonLine | ConvertFrom-Json
                $rps = [math]::Round($j.result.rps.mean, 0)
                $p99 = [math]::Round($j.result.latency.percentiles.'99' / 1000, 2)
                $err = if ($j.result.errors) { ($j.result.errors | Measure-Object -Property count -Sum).Sum } else { 0 }
                Write-Host ("  {0,-13} rps={1,9}  p99={2,7}ms  err={3}" -f $e.path, $rps, $p99, $err)
            } catch {
                Write-Host "  $($e.path) (parse error)"
            }
        } else {
            Write-Host "  $($e.path) (no bombardier output)" -ForegroundColor Yellow
        }
    }

    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    Stop-OnPort 8080
    Start-Sleep -Seconds 1
}
Write-Host ""
Write-Host "RUN $Run done" -ForegroundColor Green
