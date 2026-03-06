# Template Lab

Reusable project skeletons for rapid experiments.

## Included templates

- `cmd-batch-tool`
- `python-tool`
- `python-fastapi-service`
- `node-api`
- `typescript-node-api`
- `go-service`
- `go-cli-tool`
- `flutter-app`
- `flutter-full-app`
- `kotlin-android`
- `kotlin-jvm-cli`
- `fullstack-monorepo`
- `dockerized-service`
- `powershell-tool`
- `web-static`
- `mad-lab`

## Quick start

```powershell
pwsh -File .\scripts\new-project.ps1 -Template python-tool -Name idea-scraper
pwsh -File .\scripts\new-project.ps1 -Template go-service -Name tiny-api -Destination C:\scipts\projects
pwsh -File .\scripts\new-project.ps1 -Template node-api -Name bot-lab -Destination C:\scipts\projects -InitGit
pwsh -File .\scripts\new-project.ps1 -Template flutter-app -Name mobile-lab -Destination C:\scipts\projects -CreateGitHub -Visibility private -Push
pwsh -File .\scripts\new-project.ps1 -Template node-api -Name api-lab -Destination C:\scipts\projects -InstallDeps -InitGit
pwsh -File .\scripts\new-project.ps1 -Template python-tool -Name py-lab -Destination C:\scipts\projects -InstallDeps -PythonEnvManager uv -PythonVersion 3.12 -PythonVenvName .venv312 -AdditionalPackages "httpx==0.28.1" "rich==14.0.0" -InitGit
pwsh -File .\scripts\new-project.ps1 -Template node-api -Name node-lab -Destination C:\scipts\projects -InstallDeps -AdditionalPackages "zod@3.25.0" "dotenv@17.2.3" -InitGit
pwsh -File .\scripts\new-project.ps1 -Template go-service -Name go-lab -Destination C:\scipts\projects -InstallDeps -RunChecks -InitGit
pwsh -File .\scripts\new-project.ps1 -Template typescript-node-api -Name ts-api -Destination C:\scipts\projects -InstallDeps -RunChecks -InitGit
pwsh -File .\scripts\new-project.ps1 -Template python-fastapi-service -Name fast-api -Destination C:\scipts\projects -InstallDeps -RunChecks -InitGit
pwsh -File .\scripts\new-project.ps1 -Template cmd-batch-tool -Name win-tool -Destination C:\scipts\projects -RunChecks -InitGit
pwsh -File .\scripts\new-project.ps1 -Template fullstack-monorepo -Name stack-lab -Destination C:\scipts\projects -InstallDeps -RunChecks -InitGit
```

## No Clone Bootstrap (IRM)

Use this when you want to scaffold + initialize a repo without cloning/pulling `template_lab`.

Quick one-liner:

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/coff33ninja/template_lab/main/scripts/bootstrap.ps1"))) `
  -Template node-api `
  -Name api-lab `
  -Destination C:\scipts\projects `
  -InstallDeps `
  -RunChecks `
  -InitGit
```

With GitHub repo creation and first push:

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/coff33ninja/template_lab/main/scripts/bootstrap.ps1"))) `
  -Template python-tool `
  -Name py-lab `
  -Destination C:\scipts\projects `
  -InstallDeps `
  -RunChecks `
  -InitGit `
  -CreateGitHub `
  -Visibility private `
  -Push
```

Safer review-first flow:

```powershell
$url = "https://raw.githubusercontent.com/coff33ninja/template_lab/main/scripts/bootstrap.ps1"
irm $url | Set-Content .\bootstrap.ps1
pwsh -File .\bootstrap.ps1 -Template go-service -Name go-lab -Destination C:\scipts\projects -InstallDeps -RunChecks -InitGit
```

## Git bootstrap

```powershell
pwsh -File .\scripts\init-repo.ps1 -Path C:\scipts\projects\idea-scraper
pwsh -File .\scripts\init-repo.ps1 -Path C:\scipts\projects\idea-scraper -CreateGitHub -Visibility private -Push
```

`new-project.ps1` can now call `init-repo.ps1` directly when you pass `-InitGit`, `-CreateGitHub`, or `-Push`.

Useful flags on `new-project.ps1`:

- `-InstallDeps` run template dependency install step before git bootstrap
- `-RunChecks` run template checks/tests before git bootstrap
- `-AdditionalPackages` add version-pinned extra packages/modules for the selected template
- `-DependencySpecFile` JSON file with per-template package specs
- `-PythonEnvManager auto|uv|venv` select python env strategy when `-InstallDeps` is used
- `-PythonVenvName` customize python venv folder (default `.venv`)
- `-PythonVersion` target Python version (used with `uv` or `py`)
- `-InitGit` initialize repo + first commit
- `-CreateGitHub` create remote repo with `gh`
- `-GitHubRepo yourname/repo-name` explicit repo target
- `-Visibility private|public|internal` GitHub repo visibility
- `-Push` push initial commit (or push to existing `origin`)

`-InstallDeps` behavior by template:

- `cmd-batch-tool`: no dependency step (skipped)
- `python-tool`: `uv venv` + `uv pip install -e .[dev]` when `uv` exists; otherwise `python/py -m venv` + pip install
- `python-fastapi-service`: same as `python-tool`
- `dockerized-service`: Python venv + install from `requirements.txt` and `requirements-dev.txt`
- `python-tool` extra packages: `-AdditionalPackages "requests==2.32.3" "rich==14.0.0"`
- `node-api`: `npm install`
- `typescript-node-api`: `npm install`
- `fullstack-monorepo`: `npm install` from monorepo root
- `node-api` extra packages: `-AdditionalPackages "zod@3.25.0" "dotenv@17.2.3"`
- `go-service`: `go mod tidy`
- `go-cli-tool`: `go mod tidy`
- `go-service` extra modules: `-AdditionalPackages "github.com/go-chi/chi/v5@v5.2.3"`
- `flutter-app`: `flutter pub get`
- `flutter-full-app`: `flutter create ...` (if platforms are missing) + `flutter pub get`
- `flutter-app` extra packages: `-AdditionalPackages "dio:^5.8.0"`
- `kotlin-android`: runs `gradlew.bat dependencies`; falls back to `gradle dependencies` if wrapper is missing
- `kotlin-jvm-cli`: same Gradle dependency behavior as Kotlin Android
- `powershell-tool`, `web-static`, `mad-lab`: no dependency step (skipped)

`-RunChecks` behavior by template:

- `cmd-batch-tool`: run `cmd /c tool.cmd --check`
- `python-tool`: run `pytest -q` (prefers selected venv if present)
- `python-fastapi-service`: run `pytest -q`
- `dockerized-service`: run `pytest -q` and `docker compose config -q` (if Docker is installed)
- `node-api`: run `npm test`
- `typescript-node-api`: run `npm run build` then `npm test`
- `fullstack-monorepo`: run `npm run test -ws --if-present`
- `go-service`: run `go test ./...`
- `go-cli-tool`: run `go test ./...` then `go build ./cmd/app`
- `flutter-app`: run `flutter test`
- `flutter-full-app`: run `flutter test`
- `kotlin-android`: run `gradlew.bat test`; falls back to `gradle test` if wrapper is missing
- `kotlin-jvm-cli`: same Gradle test behavior
- `powershell-tool`, `web-static`, `mad-lab`: no checks defined (skipped)

`-DependencySpecFile` example (`deps.json`):

```json
{
  "python-tool": ["httpx==0.28.1", "rich==14.0.0"],
  "python-fastapi-service": ["orjson==3.10.12"],
  "node-api": ["zod@3.25.0"],
  "typescript-node-api": ["zod@3.25.0"],
  "go-service": ["github.com/go-chi/chi/v5@v5.2.3"],
  "go-cli-tool": ["github.com/spf13/cobra@v1.8.1"],
  "fullstack-monorepo": ["zod@3.25.0"],
  "flutter-app": ["dio:^5.8.0"]
}
```

Use it with:

```powershell
pwsh -File .\scripts\new-project.ps1 -Template python-tool -Name py-lab -InstallDeps -DependencySpecFile .\deps.json
```

The generator copies a template and replaces placeholders:

- `{{project_name}}`
- `{{project_slug}}`
- `{{project_module}}`

See [`templates/README.md`](templates/README.md) for per-template notes.
