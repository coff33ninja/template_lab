# Template Lab

Reusable project skeletons for rapid experiments.

## What is included

Templates are declared in `templates/manifest.json` and scaffolded by `scripts/new-project.ps1`.

Current templates:

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
pwsh -File .\scripts\new-project.ps1 -Template typescript-node-api -Name ts-api -Destination C:\scipts\projects -InstallDeps -RunChecks
```

## Preflight

Check local tool availability before scaffolding:

```powershell
pwsh -File .\scripts\preflight.ps1 -Phase all
pwsh -File .\scripts\preflight.ps1 -Template flutter-app -Phase install
pwsh -File .\scripts\preflight.ps1 -Phase all -FailOnMissing
```

## Dry run + policies

`-DryRun` shows what will happen without writing files.

```powershell
pwsh -File .\scripts\new-project.ps1 -Template node-api -Name api-lab -DryRun -InstallDeps -RunChecks
```

`-SkipChecksOnMissingTool` makes missing-tool behavior explicit for install/check stages.

```powershell
pwsh -File .\scripts\new-project.ps1 -Template flutter-full-app -Name mobile-lab -InstallDeps -RunChecks -SkipChecksOnMissingTool
```

Every non-dry run writes `scaffold.log` in the generated project with command trace data.

## Optional repo docs injection

```powershell
pwsh -File .\scripts\new-project.ps1 `
  -Template web-static `
  -Name web-lab `
  -IncludeLicense `
  -LicenseType MIT `
  -IncludeContributing `
  -IncludeCodeOfConduct
```

Supported `-LicenseType` values:

- `MIT`
- `Apache-2.0`
- `BSD-3-Clause`
- `Unlicense`

## Post-create hook

Run a custom script right after scaffold and checks:

```powershell
pwsh -File .\scripts\new-project.ps1 `
  -Template python-tool `
  -Name py-lab `
  -InstallDeps `
  -RunChecks `
  -PostCreateScript .\scripts\my-post-create.ps1
```

If the hook is a PowerShell script, it is invoked with:

- `-ProjectPath <generated-path>`
- `-Template <template-name>`

## Dependency control

Inline additional packages:

```powershell
pwsh -File .\scripts\new-project.ps1 -Template python-tool -Name py-lab -InstallDeps -AdditionalPackages "httpx==0.28.1" "rich==14.0.0"
pwsh -File .\scripts\new-project.ps1 -Template node-api -Name node-lab -InstallDeps -AdditionalPackages "zod@3.25.0"
```

Spec file input:

```json
{
  "python-tool": ["httpx==0.28.1", "rich==14.0.0"],
  "typescript-node-api": ["zod@3.25.0"],
  "go-service": ["github.com/go-chi/chi/v5@v5.2.3"]
}
```

```powershell
pwsh -File .\scripts\new-project.ps1 -Template python-tool -Name py-lab -InstallDeps -DependencySpecFile .\deps.json
```

## Git bootstrap

`new-project.ps1` can call `scripts/init-repo.ps1` directly.

```powershell
pwsh -File .\scripts\new-project.ps1 -Template go-cli-tool -Name go-cli -InitGit
pwsh -File .\scripts\new-project.ps1 -Template go-cli-tool -Name go-cli -InitGit -CreateGitHub -Visibility private -Push
```

## Secure IRM bootstrap

`scripts/bootstrap.ps1` now supports pinned tags and SHA256 verification.

Preferred flow (tag + release checksum asset):

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/coff33ninja/template_lab/main/scripts/bootstrap.ps1"))) `
  -Template node-api `
  -Name api-lab `
  -Destination C:\scipts\projects `
  -Ref v1.0.0 `
  -RefType tag `
  -InstallDeps `
  -RunChecks
```

Explicit hash flow:

```powershell
pwsh -File .\scripts\bootstrap.ps1 `
  -Template python-tool `
  -Name py-lab `
  -Ref v1.0.0 `
  -RefType tag `
  -ArchiveSha256 "<expected_sha256>"
```

Mutable branch fallback (intentionally explicit):

```powershell
pwsh -File .\scripts\bootstrap.ps1 `
  -Template web-static `
  -Name web-lab `
  -Ref main `
  -RefType branch `
  -AllowMutableRef `
  -AllowUnverified
```

## CI and release automation

- `.github/workflows/template-matrix.yml`
- `.github/workflows/release.yml`

The matrix workflow:

- reads templates from `templates/manifest.json`
- runs `scripts/test-template-contract.ps1`
- scaffolds every template with `-InstallDeps -RunChecks -SkipChecksOnMissingTool`

The release workflow (tag push `v*`):

- builds `template_lab-<tag>.zip`
- builds `template_lab-<tag>.zip.sha256`
- publishes both assets to the GitHub release

## Contract tests

Run locally:

```powershell
pwsh -File .\scripts\test-template-contract.ps1
```

It validates required files and placeholder-token contracts across all templates.

## Token replacement

`new-project.ps1` replaces:

- `{{project_name}}`
- `{{project_slug}}`
- `{{project_module}}`

See `templates/README.md` for template-level notes.
