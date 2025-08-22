var builder = WebApplication.CreateBuilder(args);

// Configure to listen on port 8080 in containers
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(8080);
});

// Add CORS for Angular frontend
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAngularApp", policy =>
    {
        // In production, be more specific about allowed origins
        if (builder.Environment.IsDevelopment())
        {
            policy.AllowAnyOrigin()
                  .AllowAnyMethod()
                  .AllowAnyHeader();
        }
        else
        {
            // Get allowed origins from environment variable or configuration
            var allowedOrigins = builder.Configuration["CORS:AllowedOrigins"]?.Split(';', StringSplitOptions.RemoveEmptyEntries)
                ?? new[] { "https://localhost:4200", "http://localhost:4200" };
            
            Console.WriteLine($"CORS configured for origins: {string.Join(", ", allowedOrigins)}");
            
            policy.WithOrigins(allowedOrigins)
                  .AllowAnyMethod()
                  .AllowAnyHeader()
                  .AllowCredentials();
        }
    });
});

// Add health checks
builder.Services.AddHealthChecks();

var app = builder.Build();

// Use CORS
app.UseCors("AllowAngularApp");

// Map built-in health checks - cleaner and more standard
app.MapHealthChecks("/api/health");

// Greeting endpoint (GET with query parameter)
app.MapGet("/api/greet", (string? name) =>
{
    var greetingName = name ?? "World";
    return Results.Ok(new
    {
        message = $"Hello {greetingName}!",
        timestamp = DateTime.UtcNow
    });
});

// Greeting endpoint (POST with JSON body)
app.MapPost("/api/greet", (GreetingRequest request) =>
{
    var greetingName = string.IsNullOrWhiteSpace(request.Name) ? "World" : request.Name;
    return Results.Ok(new
    {
        message = $"Hello {greetingName}!",
        timestamp = DateTime.UtcNow
    });
});

app.Run();

// Request model for POST endpoint
record GreetingRequest(string? Name);
