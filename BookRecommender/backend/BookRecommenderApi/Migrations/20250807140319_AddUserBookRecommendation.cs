using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BookRecommenderApi.Migrations
{
    /// <inheritdoc />
    public partial class AddUserBookRecommendation : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "BookId",
                table: "Recommendations",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.CreateIndex(
                name: "IX_Recommendations_BookId",
                table: "Recommendations",
                column: "BookId");

            migrationBuilder.AddForeignKey(
                name: "FK_Recommendations_Books_BookId",
                table: "Recommendations",
                column: "BookId",
                principalTable: "Books",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Recommendations_Books_BookId",
                table: "Recommendations");

            migrationBuilder.DropIndex(
                name: "IX_Recommendations_BookId",
                table: "Recommendations");

            migrationBuilder.DropColumn(
                name: "BookId",
                table: "Recommendations");
        }
    }
}
