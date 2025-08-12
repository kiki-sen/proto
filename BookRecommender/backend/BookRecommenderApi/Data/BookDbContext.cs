using BookRecommenderApi.Models;
using Microsoft.EntityFrameworkCore;

namespace BookRecommenderApi.Data
{

    public class BookDbContext : DbContext
    {
        public BookDbContext(DbContextOptions<BookDbContext> options) : base(options) { }

        public DbSet<User> Users => Set<User>();
        public DbSet<Book> Books => Set<Book>();
        public DbSet<Recommendation> Recommendations => Set<Recommendation>();

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            modelBuilder.Entity<User>()
                .HasMany(u => u.ReadingHistory)
                .WithMany(b => b.Readers)
                .UsingEntity(j => j.ToTable("UserBooks"));
        }
    }
}
