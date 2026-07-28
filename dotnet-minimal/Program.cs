using System.Security.Cryptography;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(options =>
{
    options.AddServerHeader = false;
});

// DB tier (/db, /queries, /updates) — TechEmpower shape against the same
// world(id, randomnumber) table the other stacks use. Pool is pinned to 64 to
// match jwc's JWC_DB_POOL_SIZE default and the bench's 64 connections.
var connString = Environment.GetEnvironmentVariable("DATABASE_URL")
    ?? "Host=localhost;Port=5432;Username=postgres;Password=1234;Database=BenchJWCDB;Maximum Pool Size=64;No Reset On Close=true";
var dataSource = NpgsqlDataSource.Create(connString);

var app = builder.Build();

app.MapGet("/ping", () => "pong");

app.MapGet("/json-small", () =>
{
    return Results.Json(new
    {
        Id = 1,
        Name = "Test",
        Active = true
    });
});

app.MapGet("/json-large", () =>
{
    var items = Enumerable.Range(0, 1000)
        .Select(i => new
        {
            Id = i,
            Name = $"Item {i}",
            Value = i * 10
        });

    return Results.Json(items);
});

app.MapGet("/cpu", () =>
{
    byte[] data = "benchmark"u8.ToArray();

    for (int i = 0; i < 100000; i++)
    {
        data = SHA256.HashData(data);
    }

    return Results.Text("done");
});

app.MapGet("/async-delay", async () =>
{
    await Task.Delay(10);
    return Results.Text("ok");
});

// -------------------- DB tier --------------------

static int ClampQueries(string? raw)
{
    if (!int.TryParse(raw, out var n)) n = 1;
    return n < 1 ? 1 : n > 500 ? 500 : n;
}

static async Task<World> FetchWorld(NpgsqlDataSource ds, int id)
{
    await using var cmd = ds.CreateCommand("SELECT id, randomnumber FROM world WHERE id = $1");
    cmd.Parameters.AddWithValue(id);
    await using var reader = await cmd.ExecuteReaderAsync();
    await reader.ReadAsync();
    return new World(reader.GetInt32(0), reader.GetInt32(1));
}

app.MapGet("/db", async () =>
{
    var id = Random.Shared.Next(1, 10001);
    return Results.Json(await FetchWorld(dataSource, id));
});

app.MapGet("/queries", async (HttpRequest req) =>
{
    var n = ClampQueries(req.Query["queries"]);
    var rows = new World[n];
    for (var i = 0; i < n; i++)
    {
        rows[i] = await FetchWorld(dataSource, Random.Shared.Next(1, 10001));
    }
    return Results.Json(rows);
});

app.MapGet("/updates", async (HttpRequest req) =>
{
    var n = ClampQueries(req.Query["queries"]);
    var rows = new World[n];
    for (var i = 0; i < n; i++)
    {
        var row = await FetchWorld(dataSource, Random.Shared.Next(1, 10001));
        var newValue = Random.Shared.Next(1, 10001);

        await using var cmd = dataSource.CreateCommand("UPDATE world SET randomnumber = $1 WHERE id = $2");
        cmd.Parameters.AddWithValue(newValue);
        cmd.Parameters.AddWithValue(row.Id);
        await cmd.ExecuteNonQueryAsync();

        rows[i] = row with { RandomNumber = newValue };
    }
    return Results.Json(rows);
});

app.Run("http://0.0.0.0:8080");

record World(int Id, int RandomNumber);