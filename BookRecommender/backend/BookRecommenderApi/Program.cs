using BookRecommenderApi.Data;
using BookRecommenderApi.Models;
using Microsoft.EntityFrameworkCore;
using OpenAI;
using OpenAI.Chat;
using System.Text.Json;
using System.Text.RegularExpressions;

var builder = WebApplication.CreateBuilder(args);

// Configure logging to ensure console output appears in Azure
builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.AddAzureWebAppDiagnostics();
builder.Logging.SetMinimumLevel(LogLevel.Information);

bool isDocker = Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER") == "true";
Console.WriteLine($"[STARTUP] Application starting. Docker: {isDocker}");

builder.Configuration
    .AddJsonFile("appsettings.json", optional: false)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", optional: true);

if (isDocker)
{
    builder.Configuration.AddJsonFile("appsettings.Docker.json", optional: true);
}

builder.Configuration.AddEnvironmentVariables();

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();

builder.Services.AddControllers();

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        // Default allowed origins
        var allowedOrigins = new List<string> { "http://localhost:4200" }; // Angular dev server
        
        // Add production origins from environment variables
        var additionalOrigins = builder.Configuration["CORS:AllowedOrigins"];
        if (!string.IsNullOrEmpty(additionalOrigins))
        {
            var origins = additionalOrigins.Split(',', StringSplitOptions.RemoveEmptyEntries)
                                         .Select(o => o.Trim())
                                         .Where(o => !string.IsNullOrEmpty(o));
            allowedOrigins.AddRange(origins);
        }
        
        Console.WriteLine($"CORS allowed origins: {string.Join(", ", allowedOrigins)}");
        
        policy.WithOrigins(allowedOrigins.ToArray())
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

builder.Services.AddDbContext<BookDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

Console.WriteLine("Using connection string: " + builder.Configuration.GetConnectionString("DefaultConnection"));

var app = builder.Build();

// Startup migrations disabled - use /admin/migrate endpoint instead
// try 
// {
//     Console.WriteLine("Testing database connection and applying any pending migrations...");
//     ApplyMigrations(app);
//     Console.WriteLine("Database connection and migrations successful.");
// }
// catch (Exception ex)
// {
//     Console.WriteLine($"Database connection failed: {ex.GetType().Name}: {ex.Message}");
//     if (ex.InnerException != null)
//     {
//         Console.WriteLine($"Inner exception: {ex.InnerException.GetType().Name}: {ex.InnerException.Message}");
//     }
//     Console.WriteLine($"Stack trace: {ex.StackTrace}");
//     Console.WriteLine("Application will continue to run despite database connection failure.");
//     // Continue running - don't crash the app
// }

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseCors();

app.MapControllers();

// Health check endpoint - no database required
app.MapGet("/health", () => new { 
    status = "healthy", 
    timestamp = DateTime.UtcNow,
    environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "unknown",
    version = "1.0.0"
});

// Database test endpoint with comprehensive error handling
app.MapGet("/debug/db-test", async (BookDbContext db, ILogger<Program> logger) =>
{
    try
    {
        logger.LogInformation("[DB-TEST] Starting database test...");
        
        // Test connection
        var canConnect = await db.Database.CanConnectAsync();
        logger.LogInformation($"[DB-TEST] Can connect: {canConnect}");
        
        if (!canConnect)
        {
            return Results.Problem("Cannot connect to database");
        }
        
        // Test simple query
        var userCount = await db.Users.CountAsync();
        logger.LogInformation($"[DB-TEST] User count: {userCount}");
        
        return Results.Ok(new { status = "success", canConnect, userCount, message = "Database is working" });
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "[DB-TEST] Database test failed");
        return Results.Problem($"Database test failed: {ex.Message}");
    }
});

app.MapGet("/users", async (BookDbContext db, ILogger<Program> logger) =>
{
    try
    {
        logger.LogInformation("[USERS] Getting all users...");
        var users = await db.Users.ToListAsync();
        logger.LogInformation($"[USERS] Found {users.Count} users");
        return Results.Ok(users);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "[USERS] Failed to get users");
        return Results.Problem($"Failed to get users: {ex.Message}");
    }
});

app.MapPost("/users", async (BookDbContext db, User user, ILogger<Program> logger) =>
{
    try
    {
        logger.LogInformation($"[USERS] Creating user: {user.Name}");
        db.Users.Add(user);
        await db.SaveChangesAsync();
        logger.LogInformation($"[USERS] User created with ID: {user.Id}");
        return Results.Created($"/users/{user.Id}", user);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "[USERS] Failed to create user");
        return Results.Problem($"Failed to create user: {ex.Message}");
    }
});

app.MapGet("/books", async (BookDbContext db, ILogger<Program> logger) =>
{
    try
    {
        logger.LogInformation("[BOOKS] Getting all books...");
        var books = await db.Books.ToListAsync();
        logger.LogInformation($"[BOOKS] Found {books.Count} books");
        return Results.Ok(books);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "[BOOKS] Failed to get books");
        return Results.Problem($"Failed to get books: {ex.Message}");
    }
});

// Manual migration endpoint for bootstrapping
app.MapPost("/admin/migrate", async (BookDbContext db, IConfiguration config) =>
{
    try
    {
        Console.WriteLine("Starting migration process...");
        var connectionString = config.GetConnectionString("DefaultConnection");
        Console.WriteLine($"Using connection string: {connectionString?.Replace(GetPassword(connectionString ?? ""), "***")}");
        
        // Test database connection first
        Console.WriteLine("Testing database connection...");
        var canConnect = await db.Database.CanConnectAsync();
        Console.WriteLine($"Database connection test: {(canConnect ? "SUCCESS" : "FAILED")}");
        
        if (!canConnect)
        {
            return Results.Problem("Cannot connect to database. Check connection string and network access.");
        }
        
        Console.WriteLine("Checking for pending migrations...");
        var pending = await db.Database.GetPendingMigrationsAsync();
        var pendingList = pending.ToList();
        
        Console.WriteLine($"Found {pendingList.Count} pending migrations:");
        foreach (var migration in pendingList)
        {
            Console.WriteLine($"  - {migration}");
        }
        
        if (pendingList.Any())
        {
            Console.WriteLine($"Applying {pendingList.Count} pending migrations...");
            await db.Database.MigrateAsync();
            Console.WriteLine("Migrations applied successfully!");
            return Results.Ok(new { message = "Migrations applied successfully", count = pendingList.Count, migrations = pendingList });
        }
        else
        {
            Console.WriteLine("Database is up-to-date. No migrations needed.");
            return Results.Ok(new { message = "Database is up-to-date. No migrations needed." });
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Migration failed: {ex.GetType().Name}: {ex.Message}");
        if (ex.InnerException != null)
        {
            Console.WriteLine($"Inner exception: {ex.InnerException.GetType().Name}: {ex.InnerException.Message}");
        }
        Console.WriteLine($"Stack trace: {ex.StackTrace}");
        return Results.Problem($"Migration failed: {ex.Message}");
    }
});

// Helper method for masking passwords in connection strings
static string GetPassword(string connectionString)
{
    if (string.IsNullOrEmpty(connectionString)) return "";
    var parts = connectionString.Split(';');
    foreach (var part in parts)
    {
        if (part.Trim().StartsWith("Password=", StringComparison.OrdinalIgnoreCase))
        {
            return part.Trim().Substring("Password=".Length);
        }
    }
    return "password";
}

app.MapPost("/books", async (BookDbContext db, Book book) =>
{
    db.Books.Add(book);
    await db.SaveChangesAsync();
    return Results.Created($"/books/{book.Id}", book);
});

// POST /userbooks { userId, bookId }
app.MapPost("/userbooks", async (BookDbContext db, UserBookDto dto) =>
{
    var user = await db.Users
        .Include(u => u.ReadingHistory)
        .FirstOrDefaultAsync(u => u.Id == dto.UserId);
    var book = await db.Books.FindAsync(dto.BookId);

    if (user is null || book is null) return Results.NotFound();

    // avoid duplicates
    if (!user.ReadingHistory.Any(b => b.Id == book.Id))
        user.ReadingHistory.Add(book);

    await db.SaveChangesAsync();
    return Results.NoContent();
});

// GET /users/{id}/books => Book[]
app.MapGet("/users/{id:int}/books", async (int id, BookDbContext db) =>
{
    var user = await db.Users
        .Include(u => u.ReadingHistory)
        .FirstOrDefaultAsync(u => u.Id == id);

    return user is null ? Results.NotFound() : Results.Ok(user.ReadingHistory);
});


// Recommendation endpoint
app.MapGet("/recommendations/{userId:int}", async (int userId, BookDbContext db, IConfiguration config) =>
{
    var user = await db.Users
        .Include(u => u.ReadingHistory)
        .FirstOrDefaultAsync(u => u.Id == userId);

    if (user is null || !user.ReadingHistory.Any())
        return Results.BadRequest("User not found or has no reading history.");

    var apiKey = config["OpenAI:ApiKey"];
    if (string.IsNullOrEmpty(apiKey))
        return Results.Problem("OpenAI API key is not configured.");

    // Create OpenAI client
    var openAi = new OpenAIClient(apiKey);

    var titles = string.Join(", ", user.ReadingHistory.Select(b => $"{b.Title} by {b.Author}"));
    var prompt = $"The user has read the following books: {titles}. Suggest 5 similar books with title and author." +
        @"Output ONLY valid JSON in the following format:
        [
          { ""title"": ""Book Title"", ""author"": ""Author Name"", ""reason"": ""Why they might like it"" }
        ]";

    var messages = new ChatMessage[]
    {
        ChatMessage.CreateSystemMessage("You are a book recommendation engine."),
        ChatMessage.CreateUserMessage(prompt)
    };

    var chatClient = openAi.GetChatClient("gpt-4o-mini");
    var result = await chatClient.CompleteChatAsync(messages);

    var content = result.Value.Content[0].Text?.Trim();
    var cleanedContent = Regex.Replace(content!, @"```[a-zA-Z]*\s*", "", RegexOptions.Multiline)
                   .Replace("```", "")
                   .Trim();

    try
    {
        var aiRecs = JsonSerializer.Deserialize<List<AiRecommendation>>(cleanedContent!, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        });

        if (aiRecs is null || aiRecs.Count == 0)
            return Results.BadRequest("AI returned no recommendations.");

        var savedRecs = new List<Recommendation>();

        foreach (var aiRec in aiRecs)
        {
            // Check if this book already exists
            var existingBook = await db.Books
                .FirstOrDefaultAsync(b => b.Title == aiRec.Title && b.Author == aiRec.Author);

            if (existingBook == null)
            {
                existingBook = new Book
                {
                    Title = aiRec.Title,
                    Author = aiRec.Author
                };
                db.Books.Add(existingBook);
                await db.SaveChangesAsync(); // save so we get BookId
            }

            var recommendation = new Recommendation
            {
                UserId = userId,
                BookId = existingBook.Id,
                Reason = aiRec.Reason,
                Book = existingBook
            };

            savedRecs.Add(recommendation);
        }

        db.Recommendations.AddRange(savedRecs);
        await db.SaveChangesAsync();

        var recommendationResult = savedRecs.Select(r => new RecommendationDto(r.Id, r.Book.Title, r.Book.Author, r.Reason)).ToList();

        return Results.Ok(recommendationResult);
    }
    catch (JsonException ex)
    {
        // Fallback if GPT produces invalid JSON
        return Results.BadRequest(new { error = "Invalid JSON from AI", raw = content });
    }
});

app.Run();

static void ApplyMigrations(IHost app)
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<BookDbContext>();

    var pending = db.Database.GetPendingMigrations();

    if (pending.Any())
    {
        Console.WriteLine("Applying pending EF Core migrations...");
        db.Database.Migrate();
        Console.WriteLine("Migrations applied.");
    }
    else
    {
        Console.WriteLine("Database is up-to-date. No migrations needed.");
    }
}

public record UserBookDto(int UserId, int BookId);
public record AiRecommendation(string Title, string Author, string Reason);
public record RecommendationDto(int Id, string Title, string Author, string Reason);