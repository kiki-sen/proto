using Microsoft.EntityFrameworkCore.Storage.ValueConversion.Internal;

namespace BookRecommenderApi.Models
{
    public class Recommendation
    {
        public int Id { get; set; }
        public int UserId { get; set; }
        public User User { get; set; } = default!;
        public int BookId { get; set; }
        public Book Book { get; set; } = default!;
        public string Reason { get; set; } = default!;
    }
}
