using BookRecommenderApi.Data;
using BookRecommenderApi.Models;
using Microsoft.EntityFrameworkCore;
using OpenAI;
using OpenAI.Chat;
using System.Text.Json;
using System.Text.RegularExpressions;

var builder = WebApplication.CreateBuilder(args);

bool isDocker = Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER") == "true";

builder.Configuration
    .AddJsonFile("appsettings.json", optional: false)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", optional: true);

if (isDocker)
{
    builder.Configuration.AddJsonFile("appsettings.Docker.json", optional: true);
}

builder.Configuration.AddEnvironmentVariables();

// Add services to the container.
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

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

// Apply migrations with better error handling
try 
{
    ApplyMigrations(app);
}
catch (Exception ex)
{
    Console.WriteLine($"Migration failed: {ex.Message}");
    Console.WriteLine($"Stack trace: {ex.StackTrace}");
    Console.WriteLine("Continuing without migrations - they can be applied later manually.");
}

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
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

// Configuration debugging endpoint
app.MapGet("/debug/config", (IConfiguration config, ILogger<Program> logger) =>
{
    try
    {
        logger.LogInformation("[CONFIG] Getting configuration debug info...");
        
        var connectionString = config.GetConnectionString("DefaultConnection");
        var environment = config["ASPNETCORE_ENVIRONMENT"];
        var dockerEnv = Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER");
        
        // Check various ways the connection string might be stored
        var connStringDirect = config["ConnectionStrings:DefaultConnection"];
        var connStringEnv = Environment.GetEnvironmentVariable("SQLAZURECONNSTR_DefaultConnection");
        var connStringCustom = Environment.GetEnvironmentVariable("DefaultConnection");
        
        logger.LogInformation($"[CONFIG] Connection string length: {connectionString?.Length ?? 0}");
        logger.LogInformation($"[CONFIG] Environment: {environment}");
        
        return Results.Ok(new {
            environment = environment,
            isDocker = dockerEnv,
            connectionString = new {
                fromConfig = connectionString?.Length ?? 0,
                fromConfigDirect = connStringDirect?.Length ?? 0,
                fromSqlAzureEnv = connStringEnv?.Length ?? 0,
                fromCustomEnv = connStringCustom?.Length ?? 0,
                hasValue = !string.IsNullOrEmpty(connectionString)
            },
            configSources = config.AsEnumerable().Where(kvp => kvp.Key.Contains("Connection") || kvp.Key.Contains("SQLAZURE"))
                                                .Select(kvp => new { key = kvp.Key, hasValue = !string.IsNullOrEmpty(kvp.Value) })
                                                .ToList()
        });
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "[CONFIG] Configuration debug failed");
        return Results.Problem($"Config debug failed: {ex.Message}");
    }
});

// Simple DbContext creation test
app.MapGet("/debug/simple-db", (IConfiguration config, ILogger<Program> logger) =>
{
    try
    {
        logger.LogInformation("[SIMPLE-DB] Testing DbContext creation...");
        Console.WriteLine("[SIMPLE-DB] Testing DbContext creation...");
        
        var connectionString = config.GetConnectionString("DefaultConnection");
        logger.LogInformation($"[SIMPLE-DB] Connection string length: {connectionString?.Length ?? 0}");
        Console.WriteLine($"[SIMPLE-DB] Connection string length: {connectionString?.Length ?? 0}");
        
        if (string.IsNullOrEmpty(connectionString))
        {
            logger.LogError("[SIMPLE-DB] Connection string is null or empty!");
            Console.WriteLine("[SIMPLE-DB] Connection string is null or empty!");
            return Results.Problem("Connection string not found");
        }
        
        // Just try to create DbContextOptions - don't actually connect
        var optionsBuilder = new DbContextOptionsBuilder<BookDbContext>();
        logger.LogInformation("[SIMPLE-DB] Created options builder");
        Console.WriteLine("[SIMPLE-DB] Created options builder");
        
        optionsBuilder.UseNpgsql(connectionString);
        logger.LogInformation("[SIMPLE-DB] Configured Npgsql options");
        Console.WriteLine("[SIMPLE-DB] Configured Npgsql options");
        
        var options = optionsBuilder.Options;
        logger.LogInformation("[SIMPLE-DB] Got options");
        Console.WriteLine("[SIMPLE-DB] Got options");
        
        return Results.Ok(new { 
            status = "success", 
            connectionStringLength = connectionString.Length,
            message = "DbContext options created successfully!" 
        });
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "[SIMPLE-DB] Simple database test failed");
        Console.WriteLine($"[SIMPLE-DB] Simple database test failed: {ex.GetType().Name}: {ex.Message}");
        Console.WriteLine($"[SIMPLE-DB] Stack trace: {ex.StackTrace}");
        return Results.Problem($"Simple database test failed: {ex.GetType().Name}: {ex.Message}");
    }
});

// Manual users endpoint that bypasses DI completely
app.MapGet("/debug/manual-users", async (HttpContext context) =>
{
    try
    {
        Console.WriteLine("[MANUAL-USERS] Starting manual users test...");
        
        // Get configuration manually
        var config = context.RequestServices.GetRequiredService<IConfiguration>();
        var connectionString = config.GetConnectionString("DefaultConnection");
        
        Console.WriteLine($"[MANUAL-USERS] Connection string length: {connectionString?.Length ?? 0}");
        
        if (string.IsNullOrEmpty(connectionString))
        {
            Console.WriteLine("[MANUAL-USERS] Connection string is null or empty!");
            await context.Response.WriteAsJsonAsync(new { error = "Connection string not found" });
            return;
        }
        
        // Create DbContext manually
        var optionsBuilder = new DbContextOptionsBuilder<BookDbContext>();
        optionsBuilder.UseNpgsql(connectionString);
        
        Console.WriteLine("[MANUAL-USERS] Creating DbContext...");
        using var dbContext = new BookDbContext(optionsBuilder.Options);
        
        Console.WriteLine("[MANUAL-USERS] Testing database connection...");
        var canConnect = await dbContext.Database.CanConnectAsync();
        Console.WriteLine($"[MANUAL-USERS] Can connect: {canConnect}");
        
        if (!canConnect)
        {
            Console.WriteLine("[MANUAL-USERS] Cannot connect to database");
            context.Response.StatusCode = 500;
            await context.Response.WriteAsJsonAsync(new { error = "Cannot connect to database" });
            return;
        }
        
        Console.WriteLine("[MANUAL-USERS] Getting users...");
        var users = await dbContext.Users.ToListAsync();
        Console.WriteLine($"[MANUAL-USERS] Found {users.Count} users");
        
        await context.Response.WriteAsJsonAsync(new { status = "success", userCount = users.Count, users = users });
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[MANUAL-USERS] Failed: {ex.GetType().Name}: {ex.Message}");
        Console.WriteLine($"[MANUAL-USERS] Inner: {ex.InnerException?.Message}");
        Console.WriteLine($"[MANUAL-USERS] Stack: {ex.StackTrace}");
        
        context.Response.StatusCode = 500;
        await context.Response.WriteAsJsonAsync(new { 
            error = ex.GetType().Name, 
            message = ex.Message,
            innerMessage = ex.InnerException?.Message,
            stack = ex.StackTrace
        });
    }
});

// Raw database connection test using Entity Framework
app.MapGet("/debug/raw-db-test", async (IConfiguration config, ILogger<Program> logger, IServiceProvider services) =>
{
    try
    {
        logger.LogInformation("[RAW-DB] Starting database connection test...");
        Console.WriteLine("[RAW-DB] Starting database connection test...");
        
        var connectionString = config.GetConnectionString("DefaultConnection");
        logger.LogInformation($"[RAW-DB] Connection string length: {connectionString?.Length ?? 0}");
        Console.WriteLine($"[RAW-DB] Connection string length: {connectionString?.Length ?? 0}");
        
        if (string.IsNullOrEmpty(connectionString))
        {
            logger.LogError("[RAW-DB] Connection string is null or empty!");
            Console.WriteLine("[RAW-DB] Connection string is null or empty!");
            return Results.Problem("Connection string not found");
        }
        
        // Create a new DbContext with the connection string
        var optionsBuilder = new DbContextOptionsBuilder<BookDbContext>();
        optionsBuilder.UseNpgsql(connectionString);
        
        using var dbContext = new BookDbContext(optionsBuilder.Options);
        
        logger.LogInformation("[RAW-DB] Testing database connection...");
        Console.WriteLine("[RAW-DB] Testing database connection...");
        
        var canConnect = await dbContext.Database.CanConnectAsync();
        logger.LogInformation($"[RAW-DB] Can connect: {canConnect}");
        Console.WriteLine($"[RAW-DB] Can connect: {canConnect}");
        
        if (!canConnect)
        {
            logger.LogError("[RAW-DB] Cannot connect to database");
            Console.WriteLine("[RAW-DB] Cannot connect to database");
            return Results.Problem("Cannot connect to database");
        }
        
        // Try to execute a simple query
        logger.LogInformation("[RAW-DB] Executing test query...");
        Console.WriteLine("[RAW-DB] Executing test query...");
        
        var result = await dbContext.Database.ExecuteSqlRawAsync("SELECT 1");
        logger.LogInformation($"[RAW-DB] Query executed successfully, result: {result}");
        Console.WriteLine($"[RAW-DB] Query executed successfully, result: {result}");
        
        return Results.Ok(new { 
            status = "success", 
            connectionStringLength = connectionString.Length,
            canConnect = true,
            message = "Database connection works!" 
        });
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "[RAW-DB] Database test failed");
        Console.WriteLine($"[RAW-DB] Database test failed: {ex.GetType().Name}: {ex.Message}");
        Console.WriteLine($"[RAW-DB] Stack trace: {ex.StackTrace}");
        return Results.Problem($"Database test failed: {ex.GetType().Name}: {ex.Message}");
    }
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

app.MapGet("/users", async (BookDbContext db) =>
    await db.Users.ToListAsync());

app.MapPost("/users", async (BookDbContext db, User user) =>
{
    db.Users.Add(user);
    await db.SaveChangesAsync();
    return Results.Created($"/users/{user.Id}", user);
});

app.MapGet("/books", async (BookDbContext db) =>
    await db.Books.ToListAsync());

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