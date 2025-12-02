FROM paradedb/paradedb:latest

USER root

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-17 \
    git \
    cmake \
    flex \
    bison \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install pgvector (if not in ParadeDB)
RUN cd /tmp && \
    git clone --branch v0.8.1 https://github.com/pgvector/pgvector.git && \
    cd pgvector && \
    make && \
    make install && \
    cd .. && rm -rf pgvector

# Install Apache AGE
RUN cd /tmp && \
    git clone --branch release/PG17/1.6.0 https://github.com/apache/age.git && \
    cd age && \
    make && \
    make install && \
    cd .. && rm -rf age

# Install temporal_tables
RUN cd /tmp && \
    git clone https://github.com/arkhipov/temporal_tables.git && \
    cd temporal_tables && \
    make && \
    make install && \
    cd .. && rm -rf temporal_tables

# Note: ULID will be implemented as SQL function in migrations
# No additional dependencies needed

# Cleanup
RUN apt-get purge -y build-essential git cmake && \
    apt-get autoremove -y && \
    apt-get clean

USER postgres

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
    CMD pg_isready -U postgres || exit 1
