# BookRecommender Proto

A full-stack application with Angular frontend, .NET backend, PostgreSQL database, and pgAdmin for database administration.

## Architecture

- **Frontend**: Angular application served with Nginx
- **Backend**: .NET 9 Web API with Entity Framework Core
- **Database**: PostgreSQL 16
- **Database Admin**: pgAdmin 4

## Getting Started

### Prerequisites

- Docker and Docker Compose
- .NET 9 SDK (for local development)
- Node.js 18+ (for local development)

### Running with Docker Compose

1. Build and start all services:
   ```bash
   docker-compose up -d --build
   ```

2. Access the applications:
   - **Frontend**: http://localhost (port 80)
   - **Backend API**: http://localhost:8080
   - **pgAdmin**: http://localhost:5050
   - **PostgreSQL**: localhost:5432

### API Endpoints

- `GET /api/health` - Health check endpoint
- `GET /api/greet?name=YourName` - Greeting endpoint (saves name to database)
- `POST /api/greet` - Greeting endpoint with JSON body (saves name to database)
- `GET /api/greetings` - Retrieve all stored greetings

### Database Access

#### pgAdmin
- URL: http://localhost:5050
- Email: admin@bookrecommender.local
- Password: admin123

To connect to PostgreSQL from pgAdmin:
- Host: postgres (container name)
- Port: 5432
- Database: bookrecommender
- Username: postgres
- Password: postgres

#### Direct PostgreSQL Connection
- Host: localhost
- Port: 5432
- Database: bookrecommender
- Username: postgres
- Password: postgres

## Database Schema

### greetings Table
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key (auto-increment) |
| name | VARCHAR(255) | Name from greeting requests |
| created_at | TIMESTAMP | When the greeting was created |

## Development

### Backend Development

1. Navigate to the API project:
   ```bash
   cd api/BookRecommenderApi
   ```

2. Restore packages:
   ```bash
   dotnet restore
   ```

3. Run locally (requires PostgreSQL running):
   ```bash
   dotnet run
   ```

### Frontend Development

1. Navigate to the UI project:
   ```bash
   cd ui
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Start development server:
   ```bash
   npm start
   ```

### Database Migrations

To create a new migration:
```bash
cd api/BookRecommenderApi
dotnet ef migrations add MigrationName
```

To apply migrations:
```bash
dotnet ef database update
```

## Docker Services

The docker-compose.yml includes the following services:

1. **postgres** - PostgreSQL database with persistent volume
2. **backend** - .NET API with health checks and dependency on PostgreSQL
3. **frontend** - Angular app built with multi-stage Dockerfile
4. **pgadmin** - Database administration tool

All services are connected via a custom Docker network for secure communication.

## Stopping the Application

```bash
docker-compose down
```

To remove volumes as well:
```bash
docker-compose down -v
```
