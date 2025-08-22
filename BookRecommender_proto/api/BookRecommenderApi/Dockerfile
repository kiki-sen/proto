# Use the official .NET 9 runtime as a base image
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
WORKDIR /app
EXPOSE 8080

# Use the SDK image to build the application
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ["BookRecommenderApi.csproj", "."]
RUN dotnet restore "./BookRecommenderApi.csproj"
COPY . .
WORKDIR "/src/."
RUN dotnet build "BookRecommenderApi.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "BookRecommenderApi.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "BookRecommenderApi.dll"]
