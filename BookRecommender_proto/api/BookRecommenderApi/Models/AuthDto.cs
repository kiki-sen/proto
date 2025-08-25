using System.ComponentModel.DataAnnotations;

namespace BookRecommenderApi.Models;

public record LoginRequest(
    [EmailAddress] string Email,
    [MinLength(6)] string Password
);

public record RegisterRequest(
    [EmailAddress] string Email,
    [MinLength(6)] string Password,
    string ConfirmPassword
);

public record AuthResponse(
    int Id,
    string Email,
    string Token,
    DateTime Expires
);

public record UserInfo(
    int Id,
    string Email,
    DateTime CreatedAt
);
