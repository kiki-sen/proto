using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace BookRecommenderApi.Models;

public enum ReadingStatus
{
    ToRead = 0,
    Reading = 1,
    Read = 2,
    DNF = 3 // Did Not Finish
}

[Table("user_books")]
public class UserBook
{
    [Key]
    [Column("id")]
    public int Id { get; set; }

    [Column("user_id")]
    public int UserId { get; set; }

    [Column("book_id")]
    public int BookId { get; set; }

    [Column("reading_status")]
    public ReadingStatus ReadingStatus { get; set; } = ReadingStatus.ToRead;

    [Column("rating")]
    public int? Rating { get; set; } // 1-5 stars

    [Column("review")]
    [MaxLength(2000)]
    public string? Review { get; set; }

    [Column("date_started")]
    public DateTime? DateStarted { get; set; }

    [Column("date_finished")]
    public DateTime? DateFinished { get; set; }

    [Column("added_at")]
    public DateTime AddedAt { get; set; } = DateTime.UtcNow;

    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    // Navigation properties
    [ForeignKey("UserId")]
    public User User { get; set; } = null!;

    [ForeignKey("BookId")]
    public Book Book { get; set; } = null!;
}
