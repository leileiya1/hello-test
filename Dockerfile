FROM gcr.io/distroless/static-debian12:latest

WORKDIR /app
COPY app /app/app

EXPOSE 8080
ENTRYPOINT ["/app/app"]