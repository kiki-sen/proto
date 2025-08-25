using System.ComponentModel.DataAnnotations;

namespace BookRecommenderApi.Models;

public record CreateBookRequest(
    [Required] [MaxLength(255)] string Title,
    [Required] [MaxLength(255)] string Author,
    [MaxLength(20)] string? ISBN,
    [MaxLength(2000)] string? Description,
    DateTime? PublicationDate,
    [MaxLength(100)] string? Genre,
    int? PageCount,
    [MaxLength(500)] string? CoverImageUrl
);

public record UpdateBookRequest(
    [MaxLength(255)] string? Title,
    [MaxLength(255)] string? Author,
    [MaxLength(20)] string? ISBN,
    [MaxLength(2000)] string? Description,
    DateTime? PublicationDate,
    [MaxLength(100)] string? Genre,
    int? PageCount,
    [MaxLength(500)] string? CoverImageUrl
);

public record BookResponse(
    int Id,
    string Title,
    string Author,
    string? ISBN,
    string? Description,
    DateTime? PublicationDate,
    string? Genre,
    int? PageCount,
    string? CoverImageUrl,
    DateTime CreatedAt,
    int CreatedByUserId,
    string CreatedByUserEmail
);

public record AddBookToUserRequest(
    int BookId,
    ReadingStatus ReadingStatus = ReadingStatus.ToRead
);

public record UpdateUserBookRequest(
    ReadingStatus? ReadingStatus,
    int? Rating,
    string? Review,
    DateTime? DateStarted,
    DateTime? DateFinished
);

public record UserBookResponse(
    int Id,
    int UserId,
    BookResponse Book,
    ReadingStatus ReadingStatus,
    int? Rating,
    string? Review,
    DateTime? DateStarted,
    DateTime? DateFinished,
    DateTime AddedAt,
    DateTime UpdatedAt
);
