param([int]$Runs = 3)

$ErrorActionPreference = 'Stop'
$RESULTS = "C:\Users\nbkab\OneDrive\Ishchi stol\bench\.dist\results"

$servers = 'dotnet-minimal','go-fiber','node-fastify','python-fastapi','rust-axum','jwc-app','liteapi-managed','liteapi-rust'
$endpoints = 'ping','json-small','json-large','cpu','async-delay'

function Mean($a) { if ($a.Count -eq 0) { 0 } else { ($a | Measure-Object -Average).Average } }

# table[$endpoint][$server] = pscustomobject with mean rps + p99 across runs
$grand = @{}
foreach ($e in $endpoints) { $grand[$e] = @{} }

foreach ($s in $servers) {
    foreach ($e in $endpoints) {
        $rpsRuns = @()
        $p99Runs = @()
        $errRuns = @()
        $okRuns  = 0
        for ($r=1; $r -le $Runs; $r++) {
            $f = Join-Path $RESULTS "$s\run$r\$e.json"
            if (-not (Test-Path $f)) { continue }
            try {
                $j = Get-Content -Raw -Encoding UTF8 $f | ConvertFrom-Json
                $rpsRuns += [double]$j.result.rps.mean
                $p99Runs += [double]$j.result.latency.percentiles.'99'
                $err = if ($j.result.errors) { ($j.result.errors | Measure-Object -Property count -Sum).Sum } else { 0 }
                $errRuns += [int]$err
                $okRuns++
            } catch {}
        }
        $grand[$e][$s] = [pscustomobject]@{
            runs    = $okRuns
            rps     = [math]::Round((Mean $rpsRuns), 1)
            p99_ms  = [math]::Round((Mean $p99Runs) / 1000.0, 2)
            errors  = ($errRuns | Measure-Object -Sum).Sum
            rps_min = if ($rpsRuns.Count) { [math]::Round(($rpsRuns | Measure-Object -Minimum).Minimum, 1) } else { 0 }
            rps_max = if ($rpsRuns.Count) { [math]::Round(($rpsRuns | Measure-Object -Maximum).Maximum, 1) } else { 0 }
        }
    }
}

# Pretty print, endpoint-by-endpoint
foreach ($e in $endpoints) {
    Write-Host ""
    Write-Host "=== /$e ===" -ForegroundColor Cyan
    $rows = foreach ($s in $servers) {
        $v = $grand[$e][$s]
        [pscustomobject]@{
            Server  = $s
            Runs    = $v.runs
            'RPS (mean)' = $v.rps
            'RPS min..max' = "$($v.rps_min)..$($v.rps_max)"
            'p99 (ms)' = $v.p99_ms
            Errors  = $v.errors
        }
    }
    $rows | Sort-Object 'RPS (mean)' -Descending | Format-Table -AutoSize
}

# Save full json
$grand | ConvertTo-Json -Depth 6 | Out-File -Encoding utf8 (Join-Path $RESULTS "summary-runs.json")
Write-Host ""
Write-Host "Saved: $RESULTS\summary-runs.json" -ForegroundColor Green
