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
