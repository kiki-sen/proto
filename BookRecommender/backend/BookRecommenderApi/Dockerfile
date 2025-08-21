# Base image
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
USER $APP_UID
WORKDIR /app
EXPOSE 8080

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
ARG BUILD_CONFIGURATION=Release
ARG PROJECT_PATH=.
WORKDIR /src

# Copy project file and restore
COPY ${PROJECT_PATH}/BookRecommenderApi.csproj BookRecommenderApi/
RUN dotnet restore "BookRecommenderApi/BookRecommenderApi.csproj"

# Copy entire project
COPY ${PROJECT_PATH}/ BookRecommenderApi/
WORKDIR /src/BookRecommenderApi
RUN dotnet build "BookRecommenderApi.csproj" -c $BUILD_CONFIGURATION -o /app/build

# Publish stage
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "BookRecommenderApi.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

# Final runtime stage
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "BookRecommenderApi.dll"]