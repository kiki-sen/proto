using Microsoft.EntityFrameworkCore;
using BookRecommenderApi.Data;
using BookRecommenderApi.Models;

var builder = WebApplication.CreateBuilder(args);

// Configure to listen on port 8080 in containers
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(8080);
});

// Add Entity Framework
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection")
    ?? "Host=postgres;Database=bookrecommender;Username=postgres;Password=postgres";

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(connectionString));

// Add CORS for Angular frontend
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAngularApp", policy =>
    {
        // Get allowed origins from environment variable or configuration
        var allowedOrigins = builder.Configuration["CORS:AllowedOrigins"]?.Split(';', StringSplitOptions.RemoveEmptyEntries)
            ?? new[] { "https://localhost:4200", "http://localhost:4200", "http://localhost:80", "http://localhost" };
        
        Console.WriteLine($"CORS configured for origins: {string.Join(", ", allowedOrigins)}");
        
        policy.WithOrigins(allowedOrigins)
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials();
    });
});

// Add health checks
builder.Services.AddHealthChecks();

var app = builder.Build();

// Apply database migrations on startup
using (var scope = app.Services.CreateScope())
{
    var dbContext = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await dbContext.Database.MigrateAsync();
}

// Use CORS
app.UseCors("AllowAngularApp");

// Map built-in health checks - cleaner and more standard
app.MapHealthChecks("/api/health");

// Greeting endpoint (GET with query parameter) - saves to database
app.MapGet("/api/greet", async (string? name, AppDbContext dbContext) =>
{
    var greetingName = name ?? "World";
    
    // Save greeting to database if name is provided
    if (!string.IsNullOrWhiteSpace(name))
    {
        var greeting = new Greeting { Name = name };
        dbContext.Greetings.Add(greeting);
        await dbContext.SaveChangesAsync();
    }
    
    return Results.Ok(new
    {
        message = $"Hello {greetingName}!",
        timestamp = DateTime.UtcNow
    });
});

// Greeting endpoint (POST with JSON body) - saves to database
app.MapPost("/api/greet", async (GreetingRequest request, AppDbContext dbContext) =>
{
    var greetingName = string.IsNullOrWhiteSpace(request.Name) ? "World" : request.Name;
    
    // Save greeting to database if name is provided
    if (!string.IsNullOrWhiteSpace(request.Name))
    {
        var greeting = new Greeting { Name = request.Name };
        dbContext.Greetings.Add(greeting);
        await dbContext.SaveChangesAsync();
    }
    
    return Results.Ok(new
    {
        message = $"Hello {greetingName}!",
        timestamp = DateTime.UtcNow
    });
});

// Get all greetings endpoint
app.MapGet("/api/greetings", async (AppDbContext dbContext) =>
{
    var greetings = await dbContext.Greetings
        .OrderByDescending(g => g.CreatedAt)
        .ToListAsync();
    
    return Results.Ok(greetings);
});

app.Run();

// Request model for POST endpoint
record GreetingRequest(string? Name);
