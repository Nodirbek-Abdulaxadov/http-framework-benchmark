$ErrorActionPreference = 'Continue'
$ROOT = "C:\Users\nbkab\OneDrive\Ishchi stol\bench"
$SCRIPT = Join-Path $ROOT ".dist\bench.ps1"

$servers = @(
    @{ Name='dotnet-minimal'; Dir="$ROOT\dotnet-minimal";   Cmd='dotnet ./publish/dotnet-minimal.dll --urls http://0.0.0.0:8080'; Port=8080 },
    @{ Name='go-fiber';       Dir="$ROOT\go-fiber";          Cmd='./go-fiber.exe'; Port=8080 },
    @{ Name='node-fastify';   Dir="$ROOT\node-fastify";      Cmd='node "index,js"'; Port=8080 },
    @{ Name='python-fastapi'; Dir="$ROOT\python-fastapi";    Cmd='python -m uvicorn main:app --host 0.0.0.0 --port 8080 --workers 1 --log-level warning'; Port=8080 },
    @{ Name='rust-axum';      Dir="$ROOT\rust-axum";         Cmd='./target/release/benchmark.exe'; Port=8080 },
    # jwc's native binary binds [::] with IPV6_V6ONLY, so it is only reachable
    # over IPv6 on Windows. `jwc build --native --release` writes both
    # bin/release and .jwc-build/target/release; use the former, which is also
    # what bench-runs.ps1 uses.
    @{ Name='jwc-app';        Dir="$ROOT\_my\jwc-app";       Cmd='./bin/release/jwc-app.exe'; Port=8080; BindHost='[::1]' },
    @{ Name='liteapi-rust';    Dir="$ROOT\_my\liteapi-rust"; Cmd='dotnet ./publish/liteapi-rust.dll';    Port=6080 },
    @{ Name='liteapi-managed'; Dir="$ROOT\_my\liteapi";      Cmd='dotnet ./publish/liteapi-managed.dll'; Port=6070 }
)

foreach ($s in $servers) {
    Write-Host "######## $($s.Name) ########"
    $bindHost = if ($s.ContainsKey('BindHost')) { $s.BindHost } else { '127.0.0.1' }
    & $SCRIPT -Name $s.Name -StartCmd $s.Cmd -WorkDir $s.Dir -Port $s.Port -BindHost $bindHost
}

Write-Host "######## report ########"
& (Join-Path $ROOT ".dist\report.ps1")
Write-Host "FULL DONE"
