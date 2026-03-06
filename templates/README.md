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

## `powershell-tool`
PowerShell utility scaffold with modules and config.

## `web-static`
Simple HTML/CSS/JS structure for web experiments.

## `mad-lab`
Top-level organizer for many experiment types in one repo.

## Known lightweight gaps

- `flutter-full-app` materializes platform folders during `-InstallDeps`; the raw template stays lightweight.
- Kotlin templates do not ship Gradle wrapper binaries; they use local `gradle` if wrapper is absent.
- Node/web templates do not enforce lint/format by default.
- `mad-lab` is intentionally unopinionated and does not impose runtime tooling.
