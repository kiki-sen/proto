using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using System.Text;
using System.Security.Claims;
using BookRecommenderApi.Data;
using BookRecommenderApi.Models;
using BookRecommenderApi.Services;
using BC = BCrypt.Net.BCrypt;

var builder = WebApplication.CreateBuilder(args);

// Configure to listen on port 8080 in containers
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(8080);
});

// Add Entity Framework
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
if (string.IsNullOrEmpty(connectionString))
{
    if (builder.Environment.IsDevelopment())
    {
        throw new InvalidOperationException(
            "Missing connection string 'DefaultConnection' in appsettings.Development.json or user secrets.");
    }
    else
    {
        connectionString = "Host=postgres;Database=bookrecommender;Username=postgres;Password=postgres";
    }
}

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

// Add JWT service
builder.Services.AddScoped<IJwtService, JwtService>();

// Add JWT Authentication
var jwtSecretKey = builder.Configuration["Jwt:SecretKey"] ?? "MyVeryLongSecretKeyForJWT_MustBeAtLeast32Characters!!";
var jwtIssuer = builder.Configuration["Jwt:Issuer"] ?? "BookRecommenderApi";
var jwtAudience = builder.Configuration["Jwt:Audience"] ?? "BookRecommenderApp";

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecretKey)),
            ValidateIssuer = true,
            ValidIssuer = jwtIssuer,
            ValidateAudience = true,
            ValidAudience = jwtAudience,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.Zero
        };
    });

builder.Services.AddAuthorization();

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

// Use Authentication and Authorization
app.UseAuthentication();
app.UseAuthorization();

// Map built-in health checks - cleaner and more standard
app.MapHealthChecks("/api/health");

// Authentication endpoints
app.MapPost("/api/auth/register", async (RegisterRequest request, AppDbContext dbContext, IJwtService jwtService) =>
{
    // Validate password match
    if (request.Password != request.ConfirmPassword)
    {
        return Results.BadRequest(new { message = "Passwords do not match" });
    }

    // Check if user already exists
    var existingUser = await dbContext.Users
        .FirstOrDefaultAsync(u => u.Email.ToLower() == request.Email.ToLower());
    
    if (existingUser != null)
    {
        return Results.BadRequest(new { message = "Email already registered" });
    }

    // Create new user
    var user = new User
    {
        Email = request.Email.ToLower(),
        PasswordHash = BC.HashPassword(request.Password),
        CreatedAt = DateTime.UtcNow,
        UpdatedAt = DateTime.UtcNow
    };

    dbContext.Users.Add(user);
    await dbContext.SaveChangesAsync();

    // Generate JWT token
    var token = jwtService.GenerateToken(user);
    var expires = DateTime.UtcNow.AddHours(24);

    return Results.Ok(new AuthResponse(user.Id, user.Email, token, expires));
});

app.MapPost("/api/auth/login", async (LoginRequest request, AppDbContext dbContext, IJwtService jwtService) =>
{
    // Find user by email
    var user = await dbContext.Users
        .FirstOrDefaultAsync(u => u.Email.ToLower() == request.Email.ToLower());

    if (user == null || !BC.Verify(request.Password, user.PasswordHash))
    {
        return Results.BadRequest(new { message = "Invalid email or password" });
    }

    // Generate JWT token
    var token = jwtService.GenerateToken(user);
    var expires = DateTime.UtcNow.AddHours(24);

    return Results.Ok(new AuthResponse(user.Id, user.Email, token, expires));
});

// Get current user info (protected endpoint)
app.MapGet("/api/auth/me", async (ClaimsPrincipal user, AppDbContext dbContext) =>
{
    var userIdString = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (!int.TryParse(userIdString, out var userId))
    {
        return Results.Unauthorized();
    }

    var currentUser = await dbContext.Users.FindAsync(userId);
    if (currentUser == null)
    {
        return Results.NotFound(new { message = "User not found" });
    }

    return Results.Ok(new UserInfo(currentUser.Id, currentUser.Email, currentUser.CreatedAt));
})
.RequireAuthorization();

// Book management endpoints

// Get all books (public)
app.MapGet("/api/books", async (AppDbContext dbContext) =>
{
    var books = await dbContext.Books
        .Include(b => b.CreatedByUser)
        .OrderByDescending(b => b.CreatedAt)
        .ToListAsync();
    
    var bookResponses = books.Select(b => new BookResponse(
        b.Id,
        b.Title,
        b.Author,
        b.ISBN,
        b.Description,
        b.PublicationDate,
        b.Genre,
        b.PageCount,
        b.CoverImageUrl,
        b.CreatedAt,
        b.CreatedByUserId,
        b.CreatedByUser.Email
    ));
    
    return Results.Ok(bookResponses);
});

// Get book by ID
app.MapGet("/api/books/{id:int}", async (int id, AppDbContext dbContext) =>
{
    var book = await dbContext.Books
        .Include(b => b.CreatedByUser)
        .FirstOrDefaultAsync(b => b.Id == id);
    
    if (book == null)
        return Results.NotFound(new { message = "Book not found" });
    
    var bookResponse = new BookResponse(
        book.Id,
        book.Title,
        book.Author,
        book.ISBN,
        book.Description,
        book.PublicationDate,
        book.Genre,
        book.PageCount,
        book.CoverImageUrl,
        book.CreatedAt,
        book.CreatedByUserId,
        book.CreatedByUser.Email
    );
    
    return Results.Ok(bookResponse);
});

// Create a new book (protected)
app.MapPost("/api/books", async (CreateBookRequest request, ClaimsPrincipal user, AppDbContext dbContext) =>
{
    var userIdString = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (!int.TryParse(userIdString, out var userId))
    {
        return Results.Unauthorized();
    }
    
    var book = new Book
    {
        Title = request.Title,
        Author = request.Author,
        ISBN = request.ISBN,
        Description = request.Description,
        PublicationDate = request.PublicationDate?.ToUniversalTime(),
        Genre = request.Genre,
        PageCount = request.PageCount,
        CoverImageUrl = request.CoverImageUrl,
        CreatedByUserId = userId,
        CreatedAt = DateTime.UtcNow
    };
    
    dbContext.Books.Add(book);
    await dbContext.SaveChangesAsync();
    
    // Reload with user info
    var createdBook = await dbContext.Books
        .Include(b => b.CreatedByUser)
        .FirstAsync(b => b.Id == book.Id);
    
    var bookResponse = new BookResponse(
        createdBook.Id,
        createdBook.Title,
        createdBook.Author,
        createdBook.ISBN,
        createdBook.Description,
        createdBook.PublicationDate,
        createdBook.Genre,
        createdBook.PageCount,
        createdBook.CoverImageUrl,
        createdBook.CreatedAt,
        createdBook.CreatedByUserId,
        createdBook.CreatedByUser.Email
    );
    
    return Results.Created($"/api/books/{book.Id}", bookResponse);
})
.RequireAuthorization();

// Add book to user's library
app.MapPost("/api/my-books", async (AddBookToUserRequest request, ClaimsPrincipal user, AppDbContext dbContext) =>
{
    Console.WriteLine($"[DEBUG] AddBookToUser endpoint called with BookId: {request.BookId}, Status: {request.ReadingStatus}");
    
    var userIdString = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    Console.WriteLine($"[DEBUG] User ID from token: {userIdString}");
    
    if (!int.TryParse(userIdString, out var userId))
    {
        Console.WriteLine($"[DEBUG] Failed to parse user ID: {userIdString}");
        return Results.Unauthorized();
    }
    
    // Check if book exists
    var book = await dbContext.Books.FindAsync(request.BookId);
    Console.WriteLine($"[DEBUG] Book lookup result: {(book != null ? "Found" : "Not found")}");
    if (book == null)
    {
        Console.WriteLine($"[DEBUG] Book {request.BookId} not found, returning 400");
        return Results.BadRequest(new { message = "Book not found" });
    }
    
    // Check if user already has this book
    var existingUserBook = await dbContext.UserBooks
        .FirstOrDefaultAsync(ub => ub.UserId == userId && ub.BookId == request.BookId);
    
    Console.WriteLine($"[DEBUG] Existing user book check: {(existingUserBook != null ? "Book already in library" : "Book not in library")}");
    if (existingUserBook != null)
    {
        Console.WriteLine($"[DEBUG] Book {request.BookId} already in user {userId} library, updating status to {request.ReadingStatus}");
        
        // Update existing book's status
        existingUserBook.ReadingStatus = request.ReadingStatus;
        existingUserBook.UpdatedAt = DateTime.UtcNow;
        
        // Set dates based on new status
        if (request.ReadingStatus == ReadingStatus.Reading && existingUserBook.DateStarted == null)
        {
            existingUserBook.DateStarted = DateTime.UtcNow;
        }
        else if (request.ReadingStatus == ReadingStatus.Read)
        {
            existingUserBook.DateFinished = DateTime.UtcNow;
            if (existingUserBook.DateStarted == null)
            {
                existingUserBook.DateStarted = DateTime.UtcNow;
            }
        }
        else if (request.ReadingStatus == ReadingStatus.ToRead)
        {
            // Reset dates when marking as "want to read"
            existingUserBook.DateStarted = null;
            existingUserBook.DateFinished = null;
        }
        
        await dbContext.SaveChangesAsync();
        Console.WriteLine($"[DEBUG] Successfully updated existing book status");
        
        return Results.Ok(new { message = "Book status updated in your library" });
    }
    
    var userBook = new UserBook
    {
        UserId = userId,
        BookId = request.BookId,
        ReadingStatus = request.ReadingStatus,
        AddedAt = DateTime.UtcNow,
        UpdatedAt = DateTime.UtcNow
    };
    
    dbContext.UserBooks.Add(userBook);
    await dbContext.SaveChangesAsync();
    
    return Results.Created($"/api/my-books/{userBook.Id}", new { message = "Book added to your library" });
})
.RequireAuthorization();

// Get user's books
app.MapGet("/api/my-books", async (ClaimsPrincipal user, AppDbContext dbContext) =>
{
    var userIdString = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (!int.TryParse(userIdString, out var userId))
    {
        return Results.Unauthorized();
    }
    
    var userBooks = await dbContext.UserBooks
        .Include(ub => ub.Book)
        .ThenInclude(b => b.CreatedByUser)
        .Where(ub => ub.UserId == userId)
        .OrderByDescending(ub => ub.AddedAt)
        .ToListAsync();
    
    var userBookResponses = userBooks.Select(ub => new UserBookResponse(
        ub.Id,
        ub.UserId,
        new BookResponse(
            ub.Book.Id,
            ub.Book.Title,
            ub.Book.Author,
            ub.Book.ISBN,
            ub.Book.Description,
            ub.Book.PublicationDate,
            ub.Book.Genre,
            ub.Book.PageCount,
            ub.Book.CoverImageUrl,
            ub.Book.CreatedAt,
            ub.Book.CreatedByUserId,
            ub.Book.CreatedByUser.Email
        ),
        ub.ReadingStatus,
        ub.Rating,
        ub.Review,
        ub.DateStarted,
        ub.DateFinished,
        ub.AddedAt,
        ub.UpdatedAt
    ));
    
    return Results.Ok(userBookResponses);
})
.RequireAuthorization();

// Update user's book status
app.MapPut("/api/my-books/{id:int}", async (int id, UpdateUserBookRequest request, ClaimsPrincipal user, AppDbContext dbContext) =>
{
    var userIdString = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (!int.TryParse(userIdString, out var userId))
    {
        return Results.Unauthorized();
    }
    
    var userBook = await dbContext.UserBooks
        .Include(ub => ub.Book)
        .ThenInclude(b => b.CreatedByUser)
        .FirstOrDefaultAsync(ub => ub.Id == id && ub.UserId == userId);
    
    if (userBook == null)
    {
        return Results.NotFound(new { message = "Book not found in your library" });
    }
    
    // Update fields if provided
    if (request.ReadingStatus.HasValue)
        userBook.ReadingStatus = request.ReadingStatus.Value;
    if (request.Rating.HasValue)
        userBook.Rating = request.Rating.Value;
    if (request.Review != null)
        userBook.Review = request.Review;
    if (request.DateStarted.HasValue)
        userBook.DateStarted = request.DateStarted.Value;
    
    // Handle DateFinished - allow explicit null to clear the field
    if (request.DateFinished.HasValue)
        userBook.DateFinished = request.DateFinished.Value;
    else if (request.ReadingStatus.HasValue && request.ReadingStatus.Value != ReadingStatus.Read)
        userBook.DateFinished = null; // Clear when not marking as read
    
    userBook.UpdatedAt = DateTime.UtcNow;
    
    await dbContext.SaveChangesAsync();
    
    var userBookResponse = new UserBookResponse(
        userBook.Id,
        userBook.UserId,
        new BookResponse(
            userBook.Book.Id,
            userBook.Book.Title,
            userBook.Book.Author,
            userBook.Book.ISBN,
            userBook.Book.Description,
            userBook.Book.PublicationDate,
            userBook.Book.Genre,
            userBook.Book.PageCount,
            userBook.Book.CoverImageUrl,
            userBook.Book.CreatedAt,
            userBook.Book.CreatedByUserId,
            userBook.Book.CreatedByUser.Email
        ),
        userBook.ReadingStatus,
        userBook.Rating,
        userBook.Review,
        userBook.DateStarted,
        userBook.DateFinished,
        userBook.AddedAt,
        userBook.UpdatedAt
    );
    
    return Results.Ok(userBookResponse);
})
.RequireAuthorization();

// Remove book from user's library
app.MapDelete("/api/my-books/{id:int}", async (int id, ClaimsPrincipal user, AppDbContext dbContext) =>
{
    var userIdString = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (!int.TryParse(userIdString, out var userId))
    {
        return Results.Unauthorized();
    }
    
    var userBook = await dbContext.UserBooks
        .FirstOrDefaultAsync(ub => ub.Id == id && ub.UserId == userId);
    
    if (userBook == null)
    {
        return Results.NotFound(new { message = "Book not found in your library" });
    }
    
    dbContext.UserBooks.Remove(userBook);
    await dbContext.SaveChangesAsync();
    
    return Results.Ok(new { message = "Book removed from your library" });
})
.RequireAuthorization();

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
