$ErrorActionPreference = 'Stop'
$RESULTS = "C:\Users\nbkab\OneDrive\Ishchi stol\bench\.dist\results"
$servers = 'dotnet-minimal','go-fiber','node-fastify','python-fastapi','rust-axum','jwc-app','liteapi-rust','liteapi-managed'
$endpoints = 'ping','json-small','json-large','cpu','async-delay'

$data = @{}
foreach ($s in $servers) {
    $data[$s] = @{}
    foreach ($e in $endpoints) {
        $f = Join-Path $RESULTS "$s\$e.json"
        $json = Get-Content -Raw -Encoding UTF8 $f | ConvertFrom-Json
        $r = $json.result
        $total = $r.req1xx + $r.req2xx + $r.req3xx + $r.req4xx + $r.req5xx + $r.others
        $errCount = 0
        if ($r.errors) { foreach ($er in $r.errors) { $errCount += $er.count } }
        $data[$s][$e] = [pscustomobject]@{
            rps_mean    = [math]::Round($r.rps.mean, 1)
            rps_max     = [math]::Round($r.rps.max, 1)
            rps_stddev  = [math]::Round($r.rps.stddev, 1)
            lat_mean_us = [math]::Round($r.latency.mean, 1)
            lat_p50_us  = [math]::Round($r.latency.percentiles.'50', 1)
            lat_p75_us  = [math]::Round($r.latency.percentiles.'75', 1)
            lat_p90_us  = [math]::Round($r.latency.percentiles.'90', 1)
            lat_p95_us  = [math]::Round($r.latency.percentiles.'95', 1)
            lat_p99_us  = [math]::Round($r.latency.percentiles.'99', 1)
            lat_max_us  = [math]::Round($r.latency.max, 1)
            ok2xx       = $r.req2xx
            non2xx      = $r.req1xx + $r.req3xx + $r.req4xx + $r.req5xx + $r.others
            errors      = $errCount
            total       = $total
            bytes_read  = $r.bytesRead
            duration    = [math]::Round($r.timeTakenSeconds, 2)
        }
    }
}

$data | ConvertTo-Json -Depth 8 | Out-File -Encoding utf8 (Join-Path $RESULTS 'summary.json')
Write-Host "Summary saved."
