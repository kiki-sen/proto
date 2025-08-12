using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace BookRecommenderApi.Migrations
{
    /// <inheritdoc />
    public partial class AddUserBookRelation : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "UserBooks",
                columns: table => new
                {
                    ReadersId = table.Column<int>(type: "integer", nullable: false),
                    ReadingHistoryId = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UserBooks", x => new { x.ReadersId, x.ReadingHistoryId });
                    table.ForeignKey(
                        name: "FK_UserBooks_Books_ReadingHistoryId",
                        column: x => x.ReadingHistoryId,
                        principalTable: "Books",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_UserBooks_Users_ReadersId",
                        column: x => x.ReadersId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_UserBooks_ReadingHistoryId",
                table: "UserBooks",
                column: "ReadingHistoryId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "UserBooks");
        }
    }
}
