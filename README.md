# projet-gites

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/GHCR-ready-blue)](https://ghcr.io/sepp67/projet-gites)

**Grav application image for the Gîtes website, built on the shared `grav-runtime`.**

This repository contains only the project-specific application layer: theme, business
plugins, versioned configuration and initial content.

The runtime and deployment mechanism are provided by separate reusable components.

## Where does it fit?

```text
grav-runtime
      │
      ▼
projet-gites                 ← YOU ARE HERE
      │
      ▼
ansible-role-grav-site
      │
      ▼
persistent Grav instance
```

`projet-gites` turns the generic Grav runtime into one concrete website without
duplicating the runtime or deployment logic.

## Responsibilities

### What it does

- Provides the website-specific Grav theme.
- Provides project-specific plugins.
- Provides non-secret Grav configuration.
- Provides the initial content used to seed a new instance.
- Builds a versioned application image derived from `grav-runtime`.
- Provides automated application tests.
- Publishes versioned application images to GHCR.

### What it does not do

- Does not provide or maintain PHP.
- Does not provide or maintain Nginx.
- Does not provide Grav Core.
- Does not contain production secrets.
- Does not implement production deployment logic.
- Does not manage persistent production data after initialization.
- Does not manage DNS, TLS or the reverse proxy.

The runtime is provided by `grav-runtime`. Production deployment and persistent
volumes are handled by `ansible-role-grav-site`.

## Quick Start

Requirements:

- Docker
- Docker Compose v2

Start the development environment:

```bash
docker compose -f compose.dev.yml up -d --build
```

Open:

```text
Site:  http://localhost:8080
Admin: http://localhost:8080/admin
```

The development credentials are defined in `compose.dev.yml` and are disposable.

Stop and remove the local development environment:

```bash
docker compose -f compose.dev.yml down -v
```

Run the complete local test suite:

```bash
sh tests/run-all.sh
```

## Tested & Supported

| Component | Support |
|---|---|
| Base runtime | `grav-runtime` |
| Deployment | `ansible-role-grav-site` |
| Local runtime | Docker + Docker Compose v2 |
| Application packaging | Docker image |
| Container registry | GHCR |
| Versioning | Semantic Versioning |

The test suite covers the application build, startup, application presence and
persistence behaviour.

Releases are created from explicit SemVer tags:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The release workflow publishes:

```text
ghcr.io/sepp67/projet-gites
```

with version tags such as:

```text
1.0.0
1.0
1
latest
```

Production deployments must use an explicit version and never rely on `latest`.

## Documentation & Related Components

Full documentation:

**https://docs.lavallee.tech/grav-stack/applications/projet-gites/**

Related repositories:

- [`grav-runtime`](https://github.com/sepp67/grav-runtime) — shared Grav runtime.
- [`projet-lavallee-website`](https://github.com/sepp67/projet-lavallee-website) — another application built on the same architecture.
- [`ansible-role-grav-site`](https://github.com/sepp67/ansible-role-grav-site) — reusable deployment role.

## License

MIT