# Onelist

A lightweight, multi-user, notes application with Markdown support and version control.

## Features

* Plaintext Note Taking with Markdown support
* Visual Markdown Editor (Toast UI Editor)
* Robust Version Control for notes
* RESTful API with API key authentication
* Free-form tagging system
* Multi-user support
* Full-text search
* Security and privacy by design

## Development Setup

### Prerequisites

* Docker
* Docker Compose

### Getting Started

1. Clone the repository:

```bash
git clone <repository-url>
cd onelist
```

2. Start the development environment:

```bash
docker-compose up
```

3. Create and migrate the database:

```bash
docker-compose exec web mix ecto.setup
```

4. Visit [`localhost:4000`](http://localhost:4000) to see the application.

### Running Tests

```bash
docker-compose exec web mix test
```

## Architecture

* Backend: Elixir/Phoenix with LiveView
* Database: PostgreSQL
* Frontend: TailwindCSS, Toast UI Editor
* API: RESTful with API key authentication
* Background Jobs: Oban
* Monitoring: Prometheus + Grafana

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Extensions

The `extensions/` directory contains OpenClaw plugins that integrate with Onelist:

* **onelist-memory** - Streams chat messages to Onelist for persistent memory extraction. Auto-injects recovered context on session start. See [extensions/onelist-memory/README.md](extensions/onelist-memory/README.md)

## License

This project is licensed under the MIT License - see the LICENSE file for details.
