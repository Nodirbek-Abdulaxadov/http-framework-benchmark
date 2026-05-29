using System.Security.Cryptography;
using LiteAPI;

var builder = LiteWebApplication.CreateBuilder(args);

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

app.RunWithRust();