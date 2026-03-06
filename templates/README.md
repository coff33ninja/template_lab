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

## `python-tool`
Automation, scraping, API, and AI utility starter.

## `node-api`
Express-based JavaScript API scaffold.

## `go-service`
Minimal HTTP service layout with `cmd` + `internal`.

## `flutter-app`
Cross-platform Flutter starter with simple feature folders.

## `kotlin-android`
Android app skeleton in Kotlin with Gradle Kotlin DSL.

## `powershell-tool`
PowerShell utility scaffold with modules and config.

## `web-static`
Simple HTML/CSS/JS structure for web experiments.

## `mad-lab`
Top-level organizer for many experiment types in one repo.

## Known lightweight gaps

- `flutter-app` and `kotlin-android` omit full tool-generated wrappers to stay small.
- `node-api` and `web-static` do not enforce lint/format by default.
- `mad-lab` is intentionally unopinionated and does not impose runtime tooling.
