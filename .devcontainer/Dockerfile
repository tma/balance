# Dev Container for Balance Rails App
# Ruby 3.2.3 with SQLite and development tools

FROM ruby:3.2.3-slim

# Install system dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    libsqlite3-dev \
    sqlite3 \
    libyaml-dev \
    libvips \
    curl \
    pkg-config \
    watchman \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# Set working directory
WORKDIR /workspaces/balance

# Install foreman for bin/dev (runs Procfile.dev)
RUN gem install foreman

# Default command
CMD ["sleep", "infinity"]
