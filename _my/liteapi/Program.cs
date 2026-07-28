using System.Security.Cryptography;
using LiteAPI;
using Npgsql;

var builder = LiteWebApplication.CreateBuilder(args);
builder.Configure(cfg => cfg.Urls = new[] { "http://127.0.0.1:6070" });

// DB tier (/db, /queries, /updates) — TechEmpower shape against the same
// world(id, randomnumber) table the other stacks use. Pool is pinned to 64 to
// match jwc's JWC_DB_POOL_SIZE default and the bench's 64 connections.
var connString = Environment.GetEnvironmentVariable("DATABASE_URL")
    ?? "Host=localhost;Port=5432;Username=postgres;Password=1234;Database=BenchJWCDB;Maximum Pool Size=64;No Reset On Close=true";
var dataSource = NpgsqlDataSource.Create(connString);

var app = builder.Build();

app.Get("/ping", () =>
{
    return Response.Text("pong");
});

app.Get("/json-small", () =>
{
    return Response.OkJson(new
    {
        Id = 1,
        Name = "Test",
        Active = true
    });
});

app.Get("/json-large", () =>
{
    var items = Enumerable.Range(0, 1000)
        .Select(i => new
        {
            Id = i,
            Name = $"Item {i}",
            Value = i * 10
        });

    return Response.OkJson(items);
});

app.Get("/cpu", () =>
{
    byte[] data = "benchmark"u8.ToArray();

    for (int i = 0; i < 100000; i++)
    {
        data = SHA256.HashData(data);
    }

    return Response.Text("done");
});

app.Get("/async-delay", async () =>
{
    await Task.Delay(10);
    return Response.Text("ok");
});

// -------------------- DB tier --------------------

app.Get("/db", async () =>
{
    return Response.OkJson(await Db.FetchWorld(dataSource, Db.RandomId()));
});

app.Get("/queries", async (string? queries) =>
{
    var n = Db.ClampQueries(queries);
    var rows = new World[n];
    for (var i = 0; i < n; i++)
    {
        rows[i] = await Db.FetchWorld(dataSource, Db.RandomId());
    }
    return Response.OkJson(rows);
});

app.Get("/updates", async (string? queries) =>
{
    var n = Db.ClampQueries(queries);
    var rows = new World[n];
    for (var i = 0; i < n; i++)
    {
        var row = await Db.FetchWorld(dataSource, Db.RandomId());
        var newValue = Db.RandomId();
        await Db.UpdateWorld(dataSource, row.Id, newValue);
        rows[i] = row with { RandomNumber = newValue };
    }
    return Response.OkJson(rows);
});

app.Run();

public record World(int Id, int RandomNumber);

public static class Db
{
    public static int RandomId() => Random.Shared.Next(1, 10001);

    /// Missing or unparsable ?queries= is 1; the value is pinned to 1..500.
    public static int ClampQueries(string? raw)
    {
        if (!int.TryParse(raw, out var n)) n = 1;
        return n < 1 ? 1 : n > 500 ? 500 : n;
    }

    public static async Task<World> FetchWorld(NpgsqlDataSource ds, int id)
    {
        await using var cmd = ds.CreateCommand("SELECT id, randomnumber FROM world WHERE id = $1");
        cmd.Parameters.AddWithValue(id);
        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
        return new World(reader.GetInt32(0), reader.GetInt32(1));
    }

    public static async Task UpdateWorld(NpgsqlDataSource ds, int id, int value)
    {
        await using var cmd = ds.CreateCommand("UPDATE world SET randomnumber = $1 WHERE id = $2");
        cmd.Parameters.AddWithValue(value);
        cmd.Parameters.AddWithValue(id);
        await cmd.ExecuteNonQueryAsync();
    }
}
