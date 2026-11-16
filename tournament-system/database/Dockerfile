FROM postgres:17-alpine

# The official entrypoint applies these files only to an empty data directory.
COPY migrations/ /docker-entrypoint-initdb.d/

HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=10 \
  CMD pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" || exit 1

EXPOSE 5432
