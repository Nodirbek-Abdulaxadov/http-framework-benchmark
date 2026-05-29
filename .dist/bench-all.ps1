$ROOT = "C:\Users\nbkab\OneDrive\Ishchi stol\bench"
$SCRIPT = Join-Path $ROOT ".dist\bench.ps1"

$servers = @(
    @{ Name='dotnet-minimal'; Dir="$ROOT\dotnet-minimal";  Cmd='dotnet ./publish/dotnet-minimal.dll --urls http://0.0.0.0:8080' },
    @{ Name='go-fiber';       Dir="$ROOT\go-fiber";        Cmd='./go-fiber.exe' },
    @{ Name='node-fastify';   Dir="$ROOT\node-fastify";    Cmd='node "index,js"' },
    @{ Name='python-fastapi'; Dir="$ROOT\python-fastapi";  Cmd='python -m uvicorn main:app --host 0.0.0.0 --port 8080 --workers 1 --log-level warning' },
    @{ Name='rust-axum';      Dir="$ROOT\rust-axum";       Cmd='./target/release/benchmark.exe' }
)

foreach ($s in $servers) {
    & $SCRIPT -Name $s.Name -StartCmd $s.Cmd -WorkDir $s.Dir
}

Write-Host "ALL DONE" -ForegroundColor Green
