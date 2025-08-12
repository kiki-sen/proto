using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BookRecommenderApi.Migrations
{
    /// <inheritdoc />
    public partial class AddRecommendationReason : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Reason",
                table: "Recommendations",
                type: "text",
                nullable: false,
                defaultValue: "");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Reason",
                table: "Recommendations");
        }
    }
}
