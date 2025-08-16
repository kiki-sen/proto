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

ApplyMigrations(app);

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseCors();

app.MapControllers();

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