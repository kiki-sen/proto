namespace BookRecommenderApi.Models
{
    public class Book
    {
        public int Id { get; set; }
        public string Title { get; set; } = default!;
        public string Author { get; set; } = default!;


        // Navigation property
        public List<User> Readers { get; set; } = [];
    }
}
