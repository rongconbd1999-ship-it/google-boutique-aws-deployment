FROM mcr.microsoft.com/dotnet/sdk:10.0 AS builder
WORKDIR /app
COPY . .
RUN dotnet restore
RUN dotnet publish -c Release -o /out
#
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=builder /out .
ENV ASPNETCORE_URLS=http://*:7070
EXPOSE 7070
ENTRYPOINT ["./cartservice"]