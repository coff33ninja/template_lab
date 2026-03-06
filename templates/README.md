# Templates

## Strategy baseline

- Keep every template runnable with a minimal entrypoint.
- Include a starter README and folder layout that can evolve quickly.
- Include `.gitignore` where build artifacts are expected.
- Include `.gitattributes` to keep line endings predictable across OSes.
- Keep tests as placeholders, so every scaffold starts with a testing path.
- Keep setup lightweight; avoid heavy generators unless they are required.
- Keep dependency install automation in scriptable commands (`-InstallDeps`).
- Keep version control of installed deps user-driven (`-AdditionalPackages` or `-DependencySpecFile`).
- Keep first-pass verification scriptable (`-RunChecks`) before first commit.

## Manifest contract

Template behavior is defined in `templates/manifest.json`.

Each template entry declares:

- install/check strategy keys
- required tools for install/check phases
- required file paths
- entrypoint and test-file contract paths
- whether additional packages are supported
- whether module token remapping is required

These are validated by `scripts/test-template-contract.ps1` and consumed by `scripts/new-project.ps1`.

## `cmd-batch-tool`
CMD batch utility scaffold with a smoke check command.

## `python-tool`
Automation, scraping, API, and AI utility starter.

## `python-fastapi-service`
FastAPI-first Python service template.

## `node-api`
Express-based JavaScript API scaffold.

## `typescript-node-api`
Express-based TypeScript API scaffold.

## `go-service`
Minimal HTTP service layout with `cmd` + `internal`.

## `go-cli-tool`
Go CLI scaffold with subcommands and version package.

## `flutter-app`
Cross-platform Flutter starter with simple feature folders.

## `flutter-full-app`
Flutter full-platform scaffold that materializes Android, iOS, Web, Windows, Linux, and macOS.

## `kotlin-android`
Android app skeleton in Kotlin with Gradle Kotlin DSL.

## `kotlin-jvm-cli`
Kotlin JVM CLI scaffold with Gradle build.

## `fullstack-monorepo`
Workspace scaffold for API, web, mobile placeholder, and shared package.

## `dockerized-service`
Docker-first FastAPI service with `Dockerfile`, `docker-compose.yml`, and healthcheck.

## `react-vite-web`
Modern React + Vite frontend scaffold with build + smoke tests.

## `python-worker`
Background worker starter for queue/cron-style automation tasks.

## `go-worker`
Go worker starter with `cmd` + `internal/jobs` layout.

## `db-api-service`
Database-backed FastAPI service with migration + seed script folders.

## `shared-contracts`
OpenAPI + JSON Schema package for cross-language contracts.

## `python-module`
Reusable Python package/module scaffold.

## `typescript-library`
Reusable TypeScript library scaffold.

## `go-module`
Reusable Go module scaffold.

## `powershell-tool`
PowerShell utility scaffold with modules and config.

## `web-static`
Simple HTML/CSS/JS structure for web experiments.

## `mad-lab`
Top-level organizer for many experiment types in one repo.

## Known lightweight gaps

- `flutter-full-app` materializes platform folders during `-InstallDeps`; the raw template stays lightweight.
- Kotlin templates do not ship Gradle wrapper binaries; they rely on Java plus a Gradle install from `scripts/setup-toolchain.ps1`, and you can pin versions explicitly when compatibility matters.
- Node/web templates do not enforce lint/format by default.
- `mad-lab` is intentionally unopinionated and does not impose runtime tooling.
