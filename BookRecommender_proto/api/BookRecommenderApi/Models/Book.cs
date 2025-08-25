using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace BookRecommenderApi.Models;

[Table("books")]
public class Book
{
    [Key]
    [Column("id")]
    public int Id { get; set; }

    [Column("title")]
    [MaxLength(255)]
    public string Title { get; set; } = string.Empty;

    [Column("author")]
    [MaxLength(255)]
    public string Author { get; set; } = string.Empty;

    [Column("isbn")]
    [MaxLength(20)]
    public string? ISBN { get; set; }

    [Column("description")]
    [MaxLength(2000)]
    public string? Description { get; set; }

    [Column("publication_date")]
    public DateTime? PublicationDate { get; set; }

    [Column("genre")]
    [MaxLength(100)]
    public string? Genre { get; set; }

    [Column("page_count")]
    public int? PageCount { get; set; }

    [Column("cover_image_url")]
    [MaxLength(500)]
    public string? CoverImageUrl { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    [Column("created_by_user_id")]
    public int CreatedByUserId { get; set; }

    // Navigation properties
    [ForeignKey("CreatedByUserId")]
    public User CreatedByUser { get; set; } = null!;

    public ICollection<UserBook> UserBooks { get; set; } = new List<UserBook>();
}
