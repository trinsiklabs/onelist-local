FROM elixir:1.16.1

# Install build dependencies
RUN apt-get update && apt-get install -y \
  build-essential \
  inotify-tools \
  && rm -rf /var/lib/apt/lists/*

# Install Node.js for asset compilation
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs \
  && npm install -g npm@latest

# Set environment variables
ENV MIX_ENV=dev
ENV NODE_ENV=development

# Create app directory and copy the Elixir project into it
WORKDIR /app
COPY . .

# Install Hex and Rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# Install mix dependencies
RUN mix deps.get

# Install Node.js dependencies
RUN npm install --prefix assets

# Compile the project
RUN mix do compile

EXPOSE 4000

CMD ["mix", "phx.server"] 