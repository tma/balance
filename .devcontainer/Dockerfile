# Dev Container for Balance Rails App
# Ruby 3.4.8 with SQLite and development tools

FROM ruby:3.4.8-slim

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
    libffi-dev \
    # OCR dependencies for PDF text extraction
    tesseract-ocr \
    tesseract-ocr-deu \
    tesseract-ocr-fra \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# Ensure tmp directory exists and has proper permissions for gem builds
RUN mkdir -p /tmp && chmod 1777 /tmp
ENV TMPDIR=/tmp

# Install Node.js (for OpenCode)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install OpenCode CLI
RUN npm install -g opencode-ai

# Set working directory
WORKDIR /workspaces/balance

# Install foreman for bin/dev (runs Procfile.dev)
RUN gem install foreman

# Default command
CMD ["sleep", "infinity"]
