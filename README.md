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
- `react-vite-web`
- `python-worker`
- `go-worker`
- `db-api-service`
- `shared-contracts`
- `python-module`
- `typescript-library`
- `go-module`
- `powershell-tool`
- `web-static`
- `mad-lab`

## Quick start

```powershell
pwsh -File .\scripts\new-project.ps1 -Template python-tool -Name idea-scraper
pwsh -File .\scripts\new-project.ps1 -Template go-service -Name tiny-api -Destination C:\scipts\projects
pwsh -File .\scripts\new-project.ps1 -Template typescript-node-api -Name ts-api -Destination C:\scipts\projects -InstallDeps -RunChecks
pwsh -File .\scripts\new-project.ps1 -Template react-vite-web -Name web-lab -Destination C:\scipts\projects -InstallDeps -RunChecks
pwsh -File .\scripts\new-project.ps1 -Template db-api-service -Name data-api -Destination C:\scipts\projects -InstallDeps -RunChecks
```

## Stack presets

Use `-Stack` to scaffold multi-project recipes from `templates/manifest.json`.

```powershell
pwsh -File .\scripts\new-project.ps1 -Stack go-api-flutter-contracts -Name orbit -Destination C:\scipts\projects -InstallDeps -RunChecks
pwsh -File .\scripts\new-project.ps1 -Stack db-react-worker -Name pulse -Destination C:\scipts\projects -InstallDeps -RunChecks
pwsh -File .\scripts\new-project.ps1 -Stack library-pack -Name toolkit -Destination C:\scipts\projects -InstallDeps -RunChecks
```

Current stacks:

- `go-api-flutter-contracts`
- `db-react-worker`
- `library-pack`

## Preflight

Check local tool availability before scaffolding:

```powershell
pwsh -File .\scripts\preflight.ps1 -Phase all
pwsh -File .\scripts\preflight.ps1 -Template flutter-app -Phase install
pwsh -File .\scripts\preflight.ps1 -Phase all -FailOnMissing
```

## Toolchain bootstrap (Win10/11)

Install or upgrade missing/outdated toolchain dependencies with `winget` and `choco` fallback:

Method reference:

- `-Phase all`: manifest-driven run across install + check tool requirements.
- `-InstallMissing:$true -UpgradeExisting:$false`: install-only mode (no upgrades).
- `-Template <name> -Phase install`: scope to one template's install requirements.
- `-Tools <list>`: override manifest resolution and target only the listed tools.
- `-Tools python -PythonVersion <x.y>`: optionally force a Python version; latest is used when omitted.
- `-Tools java -JavaVersion <major>`: optionally force a JDK major version; latest is used when omitted.
- `-Tools gradle -GradleVersion <x.y.z>`: optionally force a Gradle version; latest is used when omitted.
- `-OpenNewShell`: refresh env and start a new shell so PATH changes are active.
- `-UpdatePackageManagers -PackageManagersOnly`: manager maintenance without tool installs.
- `-AllowBootstrapScript`: enables Chocolatey community bootstrap script fallback.

```powershell
# Manifest-driven (all templates, install + check tools)
pwsh -File .\scripts\setup-toolchain.ps1 -Phase all

# Install missing only (no upgrades)
pwsh -File .\scripts\setup-toolchain.ps1 -Phase all -InstallMissing:$true -UpgradeExisting:$false

# Target one template's tools
pwsh -File .\scripts\setup-toolchain.ps1 -Template flutter-app -Phase install

# Explicit tool list
pwsh -File .\scripts\setup-toolchain.ps1 -Tools git,python,npm,go,java,flutter,gradle,uv,gh,pwsh

# Resolve latest versions automatically when not pinned
pwsh -File .\scripts\setup-toolchain.ps1 -Tools python,java,gradle -InstallMissing:$true -UpgradeExisting:$false

# Pin Python target version (winget/choco package selection)
pwsh -File .\scripts\setup-toolchain.ps1 -Tools python -PythonVersion 3.13 -InstallMissing:$true -UpgradeExisting:$true

# Pin Java + Gradle explicitly when you need reproducibility or compatibility control
pwsh -File .\scripts\setup-toolchain.ps1 -Tools java,gradle -JavaVersion 17 -GradleVersion 8.10.2 -InstallMissing:$true -UpgradeExisting:$false

# Refresh env and open a fresh shell that reruns preflight
pwsh -File .\scripts\setup-toolchain.ps1 -Phase all -OpenNewShell

# Update package managers only (winget + choco maintenance)
pwsh -File .\scripts\setup-toolchain.ps1 -UpdatePackageManagers -PackageManagersOnly -PackageManager both

# Allow choco bootstrap script fallback (last resort)
pwsh -File .\scripts\setup-toolchain.ps1 -UpdatePackageManagers -PackageManagersOnly -AllowBootstrapScript
```

Behavior notes:

- Uses `winget` first where package IDs are known and valid, then falls back to `choco`.
- Some tools (notably `flutter`) are installed via `choco` by default because winget IDs are inconsistent across environments.
- Python version is user-selectable via `-PythonVersion`; if omitted the script resolves the latest available Python 3 package at runtime.
- Java version is user-selectable via `-JavaVersion`; if omitted the script resolves the latest available Temurin JDK at runtime.
- Gradle version is user-selectable via `-GradleVersion`; if omitted the script resolves the current Gradle release at runtime.
- Latest-version defaults optimize for convenience; pass explicit versions when you need deterministic or compatibility-sensitive installs.
- If package managers fail to produce a usable `gradle` command, the script falls back to the official Gradle distribution ZIP in `%LOCALAPPDATA%\template-lab\tools\gradle`.
- Winget maintenance methods: `winget source update` -> `winget upgrade Microsoft.AppInstaller` -> `winget install Microsoft.AppInstaller` -> `choco upgrade/install winget` -> `https://aka.ms/getwinget` MSIX bootstrap.
- Chocolatey maintenance methods: `choco upgrade chocolatey` -> `choco install chocolatey` -> `winget upgrade/install Chocolatey.Chocolatey` -> optional community bootstrap script (`-AllowBootstrapScript`).
- Refreshes the current process environment (`PATH` and other Machine/User vars) after installs.
- Use `-OpenNewShell` when you want a fresh terminal session after installs.
- Use `-DryRun` to preview actions without making changes.
- `pwsh`/`powershell` maps to PowerShell 7 (`Microsoft.PowerShell` / `powershell-core`).
- Windows PowerShell 5.1 is OS-managed and upgrades via Windows Update, not winget/choco.

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

In `-Stack` mode, use `-DependencySpecFile` for per-template package control. `-AdditionalPackages` is intentionally ignored.

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

Method reference:

- `-InitGit`: initialize local git repo and first commit only.
- `-InitGit -CreateGitHub -Push`: create remote repo via `gh` and push initial branch.

```powershell
pwsh -File .\scripts\new-project.ps1 -Template go-cli-tool -Name go-cli -InitGit
pwsh -File .\scripts\new-project.ps1 -Template go-cli-tool -Name go-cli -InitGit -CreateGitHub -Visibility private -Push
```

## Secure IRM bootstrap

`scripts/bootstrap.ps1` now supports pinned tags and SHA256 verification.

Scope note:

- `bootstrap.ps1` is the only script designed for direct `irm` use.
- `preflight.ps1` and `setup-toolchain.ps1` are repo-bound scripts; they read `templates/manifest.json` and expect the checked-out repository layout to exist on disk.
- That means a raw `irm` of those scripts alone is not equivalent to `bootstrap.ps1` and is not the recommended path.
- If you want the same remote-entry experience for those tools, use `bootstrap-repo-script.ps1`, which first downloads/extracts the repo and then invokes the target script locally.
- If you want reproducible tool installs from a remote wrapper, pin both the repo ref and any tool versions you care about; when version flags are omitted, `setup-toolchain.ps1` now resolves latest available versions at execution time.

Method reference:

- `irm` inline: fastest one-liner, no local clone required.
- local `pwsh -File`: use checked-in/local script path, avoids inline remote execution.
- `-RefType tag` + checksum: stable/reproducible and preferred for production bootstrap.
- `-RefType branch` + `-AllowMutableRef -AllowUnverified`: explicitly insecure dev fallback.

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

Stack flow:

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/coff33ninja/template_lab/main/scripts/bootstrap.ps1"))) `
  -Stack library-pack `
  -Name toolkit `
  -Destination C:\scipts\projects `
  -Ref main `
  -RefType branch `
  -AllowMutableRef `
  -AllowUnverified `
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

Non-IRM equivalents (same behavior, no inline `irm`):

- Tag-verified local run: safest local/cloned method.
- Mutable branch local run: dev-only local method.

```powershell
# Tag-verified local run
pwsh -File .\scripts\bootstrap.ps1 `
  -Template node-api `
  -Name api-lab `
  -Destination C:\scipts\projects `
  -Ref v1.0.0 `
  -RefType tag `
  -InstallDeps `
  -RunChecks

# Mutable branch local run (explicitly insecure)
pwsh -File .\scripts\bootstrap.ps1 `
  -Template web-static `
  -Name web-lab `
  -Destination C:\scipts\projects `
  -Ref main `
  -RefType branch `
  -AllowMutableRef `
  -AllowUnverified
```

## Secure IRM repo scripts

`scripts/bootstrap-repo-script.ps1` gives `preflight.ps1` and `setup-toolchain.ps1` the same remote-entry model as `bootstrap.ps1`: download repo archive, verify it, extract it, then run the target script locally from that extracted repo.

Method reference:

- `-Script preflight|setup-toolchain`: choose the repo-bound script to run.
- Shares the same archive trust model as `bootstrap.ps1`: tag + checksum preferred, mutable branch only with `-AllowMutableRef`, unverified only with `-AllowUnverified`.
- Use a release tag that already includes `bootstrap-repo-script.ps1` and the target script, or use `main` with the explicit mutable/unverified flags until a release includes them.
- Use explicit tool version flags when you want deterministic installs; otherwise `setup-toolchain.ps1` resolves latest available versions at execution time.
- `-Script setup-toolchain -OpenNewShell` requires `-KeepDownloadedFiles` so the extracted repo still exists for the new shell.

Preferred `preflight` flow:

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/coff33ninja/template_lab/main/scripts/bootstrap-repo-script.ps1"))) `
  -Script preflight `
  -Phase all `
  -Ref vX.Y.Z `
  -RefType tag
```

Preferred `setup-toolchain` flow:

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/coff33ninja/template_lab/main/scripts/bootstrap-repo-script.ps1"))) `
  -Script setup-toolchain `
  -Phase all `
  -InstallMissing:$true `
  -UpgradeExisting:$false `
  -Ref vX.Y.Z `
  -RefType tag
```

Pinned toolchain example:

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/coff33ninja/template_lab/main/scripts/bootstrap-repo-script.ps1"))) `
  -Script setup-toolchain `
  -Tools java,gradle `
  -JavaVersion 17 `
  -GradleVersion 8.10.2 `
  -InstallMissing:$true `
  -UpgradeExisting:$false `
  -Ref vX.Y.Z `
  -RefType tag
```

Mutable branch fallback:

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/coff33ninja/template_lab/main/scripts/bootstrap-repo-script.ps1"))) `
  -Script preflight `
  -Phase all `
  -Ref main `
  -RefType branch `
  -AllowMutableRef `
  -AllowUnverified
```

Non-IRM equivalents:

```powershell
pwsh -File .\scripts\bootstrap-repo-script.ps1 -Script preflight -Phase all -Ref vX.Y.Z -RefType tag
pwsh -File .\scripts\bootstrap-repo-script.ps1 -Script setup-toolchain -Phase all -InstallMissing:$true -UpgradeExisting:$false -Ref vX.Y.Z -RefType tag
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
