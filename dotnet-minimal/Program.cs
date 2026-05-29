using System.Security.Cryptography;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(options =>
{
    options.AddServerHeader = false;
});

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

app.Run("http://0.0.0.0:8080");