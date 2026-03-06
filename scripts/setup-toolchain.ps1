[CmdletBinding()]
param(
    [string]$Template,

    [ValidateSet("install", "check", "all")]
    [string]$Phase = "all",

    [string[]]$Tools = @(),

    [switch]$IncludeOptional,

    [bool]$InstallMissing = $true,

    [bool]$UpgradeExisting = $true,

    [ValidatePattern('^\d+\.\d+(\.\d+)?$')]
    [string]$PythonVersion,

    [ValidatePattern('^\d+$')]
    [string]$JavaVersion,

    [ValidatePattern('^\d+\.\d+(\.\d+)?$')]
    [string]$GradleVersion,

    [ValidateSet("auto", "winget", "choco", "both")]
    [string]$PackageManager = "auto",

    [bool]$RefreshEnvironment = $true,

    [switch]$OpenNewShell,

    [string]$ShellCommand,

    [switch]$FailOnError,

    [switch]$DryRun,

    [switch]$UpdatePackageManagers,

    [switch]$PackageManagersOnly,

    [switch]$AllowBootstrapScript
)

$ErrorActionPreference = "Stop"
$script:AllowBootstrapScriptPreference = [bool]$AllowBootstrapScript
$script:LatestGradleRelease = $null

function Resolve-PythonVersionSpec {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $match = [regex]::Match($Version, '^(\d+)\.(\d+)')
    if (-not $match.Success) {
        throw "Invalid PythonVersion '$Version'. Use format like 3.12 or 3.12.10."
    }

    $major = $match.Groups[1].Value
    $minor = $match.Groups[2].Value
    $majorMinor = "$major.$minor"

    return @{
        MajorMinor = $majorMinor
        WingetId   = "Python.Python.$majorMinor"
        ChocoId    = "python$major$minor"
    }
}

function Resolve-JavaVersionSpec {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    if ($Version -notmatch '^\d+$') {
        throw "Invalid JavaVersion '$Version'. Use a major version like 17 or 21."
    }

    return @{
        WingetId = "EclipseAdoptium.Temurin.$Version.JDK"
        ChocoId  = "temurin$Version"
    }
}

function Get-WingetSearchOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [int]$Count = 200
    )

    if (-not (Test-CommandAvailable -Name "winget")) {
        return $null
    }

    $output = & winget search --query $Query --count $Count --disable-interactivity 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return $output
}

function Get-LatestPythonCatalogEntry {
    $output = Get-WingetSearchOutput -Query "Python.Python"
    $bestMajor = $null
    $bestMinor = $null

    if (-not [string]::IsNullOrWhiteSpace($output)) {
        foreach ($match in [regex]::Matches($output, 'Python\.Python\.(\d+)\.(\d+)\b')) {
            $major = [int]$match.Groups[1].Value
            $minor = [int]$match.Groups[2].Value
            if ($major -lt 3) {
                continue
            }

            if ($null -eq $bestMajor -or $major -gt $bestMajor -or ($major -eq $bestMajor -and $minor -gt $bestMinor)) {
                $bestMajor = $major
                $bestMinor = $minor
            }
        }
    }

    if ($null -ne $bestMajor) {
        return @{
            winget = "Python.Python.$bestMajor.$bestMinor"
            choco  = "python$bestMajor$bestMinor"
        }
    }

    return @{
        winget = $null
        choco  = "python"
    }
}

function Get-LatestJavaCatalogEntry {
    $output = Get-WingetSearchOutput -Query "EclipseAdoptium.Temurin"
    $bestMajor = $null

    if (-not [string]::IsNullOrWhiteSpace($output)) {
        foreach ($match in [regex]::Matches($output, 'EclipseAdoptium\.Temurin\.(\d+)\.JDK\b')) {
            $major = [int]$match.Groups[1].Value
            if ($null -eq $bestMajor -or $major -gt $bestMajor) {
                $bestMajor = $major
            }
        }
    }

    if ($null -ne $bestMajor) {
        return @{
            winget = "EclipseAdoptium.Temurin.$bestMajor.JDK"
            choco  = "Temurin$bestMajor"
        }
    }

    return @{
        winget = $null
        choco  = "Temurin"
    }
}

function Get-LatestGradleRelease {
    if ($null -ne $script:LatestGradleRelease) {
        return $script:LatestGradleRelease
    }

    try {
        $response = Invoke-RestMethod -Uri "https://services.gradle.org/versions/current"
        if ([string]::IsNullOrWhiteSpace("$($response.version)")) {
            throw "Gradle current release response did not include a version."
        }

        $script:LatestGradleRelease = @{
            Version     = "$($response.version)"
            DownloadUrl = "$($response.downloadUrl)"
            ChecksumUrl = "$($response.checksumUrl)"
            Checksum    = "$($response.checksum)"
        }
        return $script:LatestGradleRelease
    }
    catch {
        Write-Warning "Failed to resolve latest Gradle release metadata: $($_.Exception.Message)"
        return $null
    }
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CommandAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Format-CommandLine {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @()
    )

    if ($Arguments.Count -eq 0) {
        return $Command
    }

    $escapedArgs = foreach ($arg in $Arguments) {
        if ($arg -match '[\s"]') {
            '"' + ($arg -replace '"', '\"') + '"'
        } else {
            $arg
        }
    }

    return "$Command $($escapedArgs -join ' ')"
}

function Invoke-CommandStep {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @()
    )

    $rendered = Format-CommandLine -Command $Command -Arguments $Arguments
    if ($DryRun) {
        Write-Output "[DryRun] $rendered"
        return @{
            Success = $true
            ExitCode = 0
            CommandLine = $rendered
        }
    }

    & $Command @Arguments
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    return @{
        Success = ($exitCode -eq 0)
        ExitCode = $exitCode
        CommandLine = $rendered
    }
}

function Get-ManifestToolSet {
    param(
        [string]$TemplateName,
        [Parameter(Mandatory = $true)][ValidateSet("install", "check", "all")][string]$ToolPhase
    )

    $repoRoot = Split-Path -Parent $PSScriptRoot
    $manifestPath = Join-Path $repoRoot "templates\manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Missing template manifest: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
    $templates = $manifest.templates
    if ($null -eq $templates -or $templates.Count -eq 0) {
        throw "Template manifest has no templates."
    }

    $templateNames = if ([string]::IsNullOrWhiteSpace($TemplateName)) {
        @($templates.Keys | Sort-Object)
    } else {
        if (-not $templates.ContainsKey($TemplateName)) {
            throw "Unknown template '$TemplateName'."
        }
        @($TemplateName)
    }

    $result = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [void]$result.Add("git")

    foreach ($name in $templateNames) {
        $cfg = $templates[$name]
        if ($ToolPhase -in @("install", "all")) {
            foreach ($tool in @($cfg.required_tools.install)) {
                if (-not [string]::IsNullOrWhiteSpace("$tool")) {
                    [void]$result.Add("$tool")
                }
            }
        }
        if ($ToolPhase -in @("check", "all")) {
            foreach ($tool in @($cfg.required_tools.check)) {
                if (-not [string]::IsNullOrWhiteSpace("$tool")) {
                    [void]$result.Add("$tool")
                }
            }
        }
    }

    return @($result | Sort-Object)
}

function Expand-ToolNameList {
    param(
        [string[]]$InputTools = @()
    )

    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $InputTools) {
        if ([string]::IsNullOrWhiteSpace("$entry")) {
            continue
        }
        foreach ($part in "$entry".Split(",")) {
            $name = $part.Trim().ToLowerInvariant()
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                [void]$names.Add($name)
            }
        }
    }
    return @($names)
}

function Get-ToolCatalog {
    $catalog = @{}

    # Built-ins are included for reporting but never installed.
    $catalog["cmd"] = @{
        commands = @("cmd")
        builtin = $true
        winget = $null
        choco = $null
    }

    $catalog["git"] = @{
        commands = @("git")
        builtin = $false
        winget = "Git.Git"
        choco = "git"
    }

    $catalog["python"] = @{
        commands = @("python", "py")
        builtin = $false
        winget = "Python.Python.3.12"
        choco = "python"
    }

    # npm availability is satisfied by Node installation.
    $catalog["npm"] = @{
        commands = @("npm")
        builtin = $false
        winget = "OpenJS.NodeJS.LTS"
        choco = "nodejs-lts"
    }

    $catalog["node"] = @{
        commands = @("node")
        builtin = $false
        winget = "OpenJS.NodeJS.LTS"
        choco = "nodejs-lts"
    }

    $catalog["go"] = @{
        commands = @("go")
        builtin = $false
        winget = "GoLang.Go"
        choco = "golang"
    }

    $catalog["java"] = @{
        commands = @("java")
        builtin = $false
        winget = "EclipseAdoptium.Temurin.17.JDK"
        choco = "temurin17"
    }
    $catalog["jdk"] = $catalog["java"]

    # "powershell" here means PowerShell 7 (pwsh). Windows PowerShell 5.1
    # is OS-managed and not upgraded through package managers.
    $catalog["pwsh"] = @{
        commands = @("pwsh")
        builtin = $false
        winget = "Microsoft.PowerShell"
        choco = "powershell-core"
    }
    $catalog["powershell"] = $catalog["pwsh"]

    # Flutter SDK is typically installed via choco on Windows; winget commonly
    # indexes wrappers/tools but not the canonical SDK package.
    $catalog["flutter"] = @{
        commands = @("flutter")
        builtin = $false
        winget = $null
        choco = "flutter"
    }

    $catalog["gradle"] = @{
        commands = @("gradle")
        builtin = $false
        winget = $null
        choco = "gradle"
    }

    $catalog["gh"] = @{
        commands = @("gh")
        builtin = $false
        winget = "GitHub.cli"
        choco = "gh"
    }

    $catalog["uv"] = @{
        commands = @("uv")
        builtin = $false
        winget = "astral-sh.uv"
        choco = "uv"
    }

    $catalog["docker"] = @{
        commands = @("docker")
        builtin = $false
        winget = "Docker.DockerDesktop"
        choco = "docker-desktop"
    }

    return $catalog
}

function Get-PythonCatalogEntryOverride {
    param(
        [string]$TargetVersion
    )

    if ([string]::IsNullOrWhiteSpace($TargetVersion)) {
        return Get-LatestPythonCatalogEntry
    }

    $spec = Resolve-PythonVersionSpec -Version $TargetVersion
    return @{
        winget = $spec.WingetId
        choco  = $spec.ChocoId
    }
}

function Get-JavaCatalogEntryOverride {
    param(
        [string]$TargetVersion
    )

    if ([string]::IsNullOrWhiteSpace($TargetVersion)) {
        return Get-LatestJavaCatalogEntry
    }

    $spec = Resolve-JavaVersionSpec -Version $TargetVersion
    return @{
        winget = $spec.WingetId
        choco  = $spec.ChocoId
    }
}

function Get-GradleCommandPath {
    $command = Get-Command "gradle" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    foreach ($scope in @("Process", "User", "Machine")) {
        $gradleHome = [Environment]::GetEnvironmentVariable("GRADLE_HOME", $scope)
        if ([string]::IsNullOrWhiteSpace($gradleHome)) {
            continue
        }

        $gradleBat = Join-Path $gradleHome "bin\gradle.bat"
        if (Test-Path -LiteralPath $gradleBat -PathType Leaf) {
            return $gradleBat
        }
    }

    return $null
}

function Get-ToolStatus {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Definition,
        [string]$ToolName
    )

    if ($ToolName -ieq "gradle") {
        return [bool](Get-GradleCommandPath)
    }

    foreach ($cmd in @($Definition.commands)) {
        if (Test-CommandAvailable -Name $cmd) {
            return $true
        }
    }
    return $false
}

function Invoke-WingetAction {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("install", "upgrade")][string]$Action,
        [Parameter(Mandatory = $true)][string]$PackageId
    )

    $base = @(
        $Action,
        "--id", $PackageId,
        "--exact",
        "--source", "winget",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--disable-interactivity"
    )
    if ($Action -eq "install") {
        $base += "--silent"
    } else {
        $base += "--silent"
        $base += "--include-unknown"
    }

    if ($DryRun) {
        Write-Output "[DryRun] winget $($base -join ' ')"
        return $true
    }

    & winget @base
    if ($LASTEXITCODE -eq 0) {
        return $true
    }

    return $false
}

function Invoke-ChocoAction {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("install", "upgrade")][string]$Action,
        [Parameter(Mandatory = $true)][string]$PackageId
    )

    $chocoArgs = @($Action, $PackageId, "-y", "--no-progress")

    if ($DryRun) {
        Write-Output "[DryRun] choco $($chocoArgs -join ' ')"
        return $true
    }

    & choco @chocoArgs
    if ($LASTEXITCODE -eq 0) {
        return $true
    }

    return $false
}

function Get-ManagedToolDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$ToolName
    )

    return Join-Path $env:LOCALAPPDATA ("template-lab\tools\" + $ToolName)
}

function Add-PathEntry {
    param(
        [string]$ExistingPath,
        [Parameter(Mandatory = $true)][string]$Entry
    )

    $normalizedEntry = $Entry.Trim().TrimEnd("\")
    $segments = @()

    foreach ($segment in @("$ExistingPath" -split ";")) {
        $candidate = $segment.Trim()
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $segments += $candidate
        }
    }

    foreach ($segment in $segments) {
        if ($segment.TrimEnd("\") -ieq $normalizedEntry) {
            return ($segments -join ";")
        }
    }

    if ($segments.Count -eq 0) {
        return $Entry
    }

    return (($segments + $Entry) -join ";")
}

function Set-UserEnvironmentValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if ($DryRun) {
        Write-Output "[DryRun] Set user env $Name=$Value"
        return $true
    }

    $current = [Environment]::GetEnvironmentVariable($Name, "User")
    if ($current -eq $Value) {
        [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
        return $false
    }

    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
    return $true
}

function Ensure-UserPathEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Entry
    )

    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $updatedPath = Add-PathEntry -ExistingPath $userPath -Entry $Entry

    if ($DryRun) {
        if ($updatedPath -ne "$userPath") {
            Write-Output "[DryRun] Add user PATH entry: $Entry"
            return $true
        }

        return $false
    }

    if ($updatedPath -ne "$userPath") {
        [Environment]::SetEnvironmentVariable("PATH", $updatedPath, "User")
    }

    $processPath = Add-PathEntry -ExistingPath $env:PATH -Entry $Entry
    $env:PATH = $processPath
    [Environment]::SetEnvironmentVariable("PATH", $processPath, "Process")

    return ($updatedPath -ne "$userPath")
}

function Invoke-GradleArchiveInstall {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("install", "upgrade")][string]$Action,
        [string]$Version
    )

    $release = $null
    if ([string]::IsNullOrWhiteSpace($Version)) {
        $release = Get-LatestGradleRelease
        if ($null -eq $release) {
            Write-Warning "Gradle archive install requires release metadata, but latest version resolution failed."
            return $false
        }

        $Version = $release.Version
    }

    $toolRoot = Get-ManagedToolDirectory -ToolName "gradle"
    $versionRoot = Join-Path $toolRoot $Version
    $gradleHome = Join-Path $versionRoot "gradle-$Version"
    $gradleBat = Join-Path $gradleHome "bin\gradle.bat"
    $downloadUrl = if ($null -ne $release -and -not [string]::IsNullOrWhiteSpace($release.DownloadUrl)) { $release.DownloadUrl } else { "https://services.gradle.org/distributions/gradle-$Version-bin.zip" }
    $checksumUrl = if ($null -ne $release -and -not [string]::IsNullOrWhiteSpace($release.ChecksumUrl)) { $release.ChecksumUrl } else { "$downloadUrl.sha256" }

    if ((Test-Path -LiteralPath $gradleBat -PathType Leaf) -and $Action -eq "install") {
        [void](Set-UserEnvironmentValue -Name "GRADLE_HOME" -Value $gradleHome)
        [void](Ensure-UserPathEntry -Entry (Join-Path $gradleHome "bin"))
        return $true
    }

    $tempRoot = Join-Path $env:TEMP ("template-lab-gradle-" + [guid]::NewGuid().ToString("N"))
    $zipPath = Join-Path $tempRoot "gradle-$Version-bin.zip"
    $shaPath = Join-Path $tempRoot "gradle-$Version-bin.zip.sha256"

    if ($DryRun) {
        Write-Output "[DryRun] Invoke-WebRequest -Uri $downloadUrl -OutFile `"$zipPath`""
        Write-Output "[DryRun] Invoke-WebRequest -Uri $checksumUrl -OutFile `"$shaPath`""
        Write-Output "[DryRun] Expand-Archive -LiteralPath `"$zipPath`" -DestinationPath `"$versionRoot`" -Force"
        Write-Output "[DryRun] Set user env GRADLE_HOME=$gradleHome"
        Write-Output "[DryRun] Add user PATH entry: $(Join-Path $gradleHome 'bin')"
        return $true
    }

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        $expectedHash = if ($null -ne $release -and -not [string]::IsNullOrWhiteSpace($release.Checksum)) {
            $release.Checksum.ToLowerInvariant()
        } else {
            Invoke-WebRequest -Uri $checksumUrl -OutFile $shaPath -UseBasicParsing
            ((Get-Content -LiteralPath $shaPath -Raw).Trim() -split "\s+")[0].ToLowerInvariant()
        }
        $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Gradle archive checksum mismatch. Expected '$expectedHash', got '$actualHash'."
        }

        if (Test-Path -LiteralPath $versionRoot) {
            Remove-Item -LiteralPath $versionRoot -Recurse -Force
        }

        New-Item -ItemType Directory -Path $versionRoot -Force | Out-Null
        Expand-Archive -LiteralPath $zipPath -DestinationPath $versionRoot -Force

        if (-not (Test-Path -LiteralPath $gradleBat -PathType Leaf)) {
            throw "Gradle archive install did not produce '$gradleBat'."
        }

        [void](Set-UserEnvironmentValue -Name "GRADLE_HOME" -Value $gradleHome)
        [void](Ensure-UserPathEntry -Entry (Join-Path $gradleHome "bin"))
        return $true
    }
    catch {
        Write-Warning "Gradle archive install failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-ManagerOrder {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("auto", "winget", "choco", "both")][string]$Mode
    )

    switch ($Mode) {
        "winget" { return @("winget") }
        "choco" { return @("choco") }
        "both" { return @("winget", "choco") }
        default {
            $hasWinget = Test-CommandAvailable -Name "winget"
            $hasChoco = Test-CommandAvailable -Name "choco"
            if ($hasWinget -and $hasChoco) { return @("winget", "choco") }
            if ($hasWinget) { return @("winget") }
            if ($hasChoco) { return @("choco") }
            return @()
        }
    }
}

function Invoke-WingetBootstrapFromMsix {
    $downloadUrl = "https://aka.ms/getwinget"
    $tempPath = Join-Path $env:TEMP "winget-bootstrap.msixbundle"

    if ($DryRun) {
        Write-Output "[DryRun] Invoke-WebRequest -Uri $downloadUrl -OutFile `"$tempPath`""
        Write-Output "[DryRun] Add-AppxPackage -Path `"$tempPath`""
        return $true
    }

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempPath -UseBasicParsing
        Add-AppxPackage -Path $tempPath
        return $true
    }
    catch {
        Write-Warning "Winget MSIX bootstrap failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ChocoBootstrapScriptInstall {
    if (-not $script:AllowBootstrapScriptPreference) {
        return $false
    }

    $bootstrapScript = @'
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
'@

    if ($DryRun) {
        Write-Output "[DryRun] pwsh -NoProfile -ExecutionPolicy Bypass -Command <choco bootstrap script>"
        return $true
    }

    & pwsh -NoProfile -ExecutionPolicy Bypass -Command $bootstrapScript
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    return ($exitCode -eq 0)
}

function Invoke-WingetMaintenance {
    $state = if (Test-CommandAvailable -Name "winget") { "present" } else { "missing" }
    $attempts = New-Object System.Collections.Generic.List[string]
    $success = $false
    $anyChanges = $false
    $managerUsed = "-"

    if (Test-CommandAvailable -Name "winget") {
        $sourceUpdate = Invoke-CommandStep -Command "winget" -Arguments @("source", "update", "--accept-source-agreements", "--disable-interactivity")
        if ($sourceUpdate.Success) {
            $attempts.Add("source-update ok")
        } else {
            $attempts.Add("source-update failed($($sourceUpdate.ExitCode))")
        }

        $upgradeAppInstaller = Invoke-CommandStep -Command "winget" -Arguments @(
            "upgrade", "--id", "Microsoft.AppInstaller", "--exact", "--source", "winget",
            "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity",
            "--include-unknown", "--silent"
        )
        if ($upgradeAppInstaller.Success) {
            $success = $true
            $anyChanges = $true
            $managerUsed = "winget"
            $attempts.Add("upgrade-appinstaller ok")
        } else {
            $attempts.Add("upgrade-appinstaller failed($($upgradeAppInstaller.ExitCode))")

            $installAppInstaller = Invoke-CommandStep -Command "winget" -Arguments @(
                "install", "--id", "Microsoft.AppInstaller", "--exact", "--source", "winget",
                "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity",
                "--silent"
            )
            if ($installAppInstaller.Success) {
                $success = $true
                $anyChanges = $true
                $managerUsed = "winget"
                $attempts.Add("install-appinstaller ok")
            } else {
                $attempts.Add("install-appinstaller failed($($installAppInstaller.ExitCode))")
            }
        }
    } else {
        $attempts.Add("winget command missing")
    }

    if (-not $success -and (Test-CommandAvailable -Name "choco")) {
        $viaChocoUpgrade = Invoke-ChocoAction -Action "upgrade" -PackageId "winget"
        if ($viaChocoUpgrade) {
            $success = $true
            $anyChanges = $true
            $managerUsed = "choco"
            $attempts.Add("choco-upgrade-winget ok")
        } else {
            $attempts.Add("choco-upgrade-winget failed")
            $viaChocoInstall = Invoke-ChocoAction -Action "install" -PackageId "winget"
            if ($viaChocoInstall) {
                $success = $true
                $anyChanges = $true
                $managerUsed = "choco"
                $attempts.Add("choco-install-winget ok")
            } else {
                $attempts.Add("choco-install-winget failed")
            }
        }
    }

    if (-not $success) {
        $msixResult = Invoke-WingetBootstrapFromMsix
        if ($msixResult) {
            $success = $true
            $anyChanges = $true
            $managerUsed = if ($managerUsed -eq "-") { "msix" } else { $managerUsed }
            $attempts.Add("msix-bootstrap ok")
        } else {
            $attempts.Add("msix-bootstrap failed")
        }
    }

    $row = [pscustomobject]@{
        Tool    = "winget"
        State   = $state
        Action  = "maintenance"
        Manager = $managerUsed
        Result  = if ($success) { "ok: $($attempts -join '; ')" } else { $attempts -join "; " }
    }

    return @{
        Row = $row
        Success = $success
        AnyChanges = $anyChanges
    }
}

function Invoke-ChocoMaintenance {
    $state = if (Test-CommandAvailable -Name "choco") { "present" } else { "missing" }
    $attempts = New-Object System.Collections.Generic.List[string]
    $success = $false
    $anyChanges = $false
    $managerUsed = "-"

    if (Test-CommandAvailable -Name "choco") {
        $upgradeChoco = Invoke-ChocoAction -Action "upgrade" -PackageId "chocolatey"
        if ($upgradeChoco) {
            $success = $true
            $anyChanges = $true
            $managerUsed = "choco"
            $attempts.Add("choco-upgrade-chocolatey ok")
        } else {
            $attempts.Add("choco-upgrade-chocolatey failed")
            $installChoco = Invoke-ChocoAction -Action "install" -PackageId "chocolatey"
            if ($installChoco) {
                $success = $true
                $anyChanges = $true
                $managerUsed = "choco"
                $attempts.Add("choco-install-chocolatey ok")
            } else {
                $attempts.Add("choco-install-chocolatey failed")
            }
        }
    } else {
        $attempts.Add("choco command missing")
    }

    if (-not $success -and (Test-CommandAvailable -Name "winget")) {
        $upgradeViaWinget = Invoke-WingetAction -Action "upgrade" -PackageId "Chocolatey.Chocolatey"
        if ($upgradeViaWinget) {
            $success = $true
            $anyChanges = $true
            $managerUsed = "winget"
            $attempts.Add("winget-upgrade-chocolatey ok")
        } else {
            $attempts.Add("winget-upgrade-chocolatey failed")
            $installViaWinget = Invoke-WingetAction -Action "install" -PackageId "Chocolatey.Chocolatey"
            if ($installViaWinget) {
                $success = $true
                $anyChanges = $true
                $managerUsed = "winget"
                $attempts.Add("winget-install-chocolatey ok")
            } else {
                $attempts.Add("winget-install-chocolatey failed")
            }
        }
    }

    if (-not $success) {
        $bootstrap = Invoke-ChocoBootstrapScriptInstall
        if ($bootstrap) {
            $success = $true
            $anyChanges = $true
            $managerUsed = if ($managerUsed -eq "-") { "bootstrap-script" } else { $managerUsed }
            $attempts.Add("bootstrap-script ok")
        } elseif ($script:AllowBootstrapScriptPreference) {
            $attempts.Add("bootstrap-script failed")
        } else {
            $attempts.Add("bootstrap-script skipped")
        }
    }

    $row = [pscustomobject]@{
        Tool    = "choco"
        State   = $state
        Action  = "maintenance"
        Manager = $managerUsed
        Result  = if ($success) { "ok: $($attempts -join '; ')" } else { $attempts -join "; " }
    }

    return @{
        Row = $row
        Success = $success
        AnyChanges = $anyChanges
    }
}

function Invoke-PackageManagerMaintenance {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("auto", "winget", "choco", "both")][string]$Mode
    )

    $targets = switch ($Mode) {
        "winget" { @("winget") }
        "choco" { @("choco") }
        default { @("winget", "choco") }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $hadFailure = $false
    $anyChanges = $false

    foreach ($target in $targets) {
        if ($target -eq "winget") {
            $result = Invoke-WingetMaintenance
        } else {
            $result = Invoke-ChocoMaintenance
        }

        $rows.Add($result.Row)
        if (-not $result.Success) {
            $hadFailure = $true
        }
        if ($result.AnyChanges) {
            $anyChanges = $true
        }
    }

    return @{
        Rows = $rows.ToArray()
        HadFailure = $hadFailure
        AnyChanges = $anyChanges
    }
}

function Invoke-ProcessEnvironmentRefresh {
    $machine = [Environment]::GetEnvironmentVariables("Machine")
    $user = [Environment]::GetEnvironmentVariables("User")

    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $machine.Keys) { [void]$names.Add("$k") }
    foreach ($k in $user.Keys) { [void]$names.Add("$k") }

    foreach ($name in $names) {
        $machineValue = if ($machine.Contains($name)) { "$($machine[$name])" } else { $null }
        $userValue = if ($user.Contains($name)) { "$($user[$name])" } else { $null }
        if ($name -ieq "PATH") {
            $combined = @()
            if (-not [string]::IsNullOrWhiteSpace($machineValue)) { $combined += $machineValue }
            if (-not [string]::IsNullOrWhiteSpace($userValue)) { $combined += $userValue }
            [Environment]::SetEnvironmentVariable("PATH", ($combined -join ";"), "Process")
        } else {
            $effective = if ($null -ne $userValue) { $userValue } else { $machineValue }
            [Environment]::SetEnvironmentVariable($name, $effective, "Process")
        }
    }
}

function Invoke-NewShellIfRequested {
    param(
        [string]$CommandToRun
    )

    if (-not $OpenNewShell) {
        return
    }

    $shellArgs = @("-NoExit")
    if (-not [string]::IsNullOrWhiteSpace($CommandToRun)) {
        $shellArgs += @("-Command", $CommandToRun)
    }

    if ($DryRun) {
        Write-Output "[DryRun] Would start new terminal: pwsh $($shellArgs -join ' ')"
        return
    }

    Start-Process -FilePath "pwsh" -ArgumentList $shellArgs -WorkingDirectory (Get-Location).Path | Out-Null
}

$catalog = Get-ToolCatalog
$pythonOverride = Get-PythonCatalogEntryOverride -TargetVersion $PythonVersion
if ($catalog.ContainsKey("python")) {
    $catalog["python"].winget = $pythonOverride.winget
    $catalog["python"].choco = $pythonOverride.choco
}
$javaOverride = Get-JavaCatalogEntryOverride -TargetVersion $JavaVersion
if ($catalog.ContainsKey("java")) {
    $catalog["java"].winget = $javaOverride.winget
    $catalog["java"].choco = $javaOverride.choco
}
$catalog["jdk"] = $catalog["java"]
$toolsToEnsure = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($tool in (Get-ManifestToolSet -TemplateName $Template -ToolPhase $Phase)) {
    [void]$toolsToEnsure.Add($tool)
}

foreach ($tool in (Expand-ToolNameList -InputTools $Tools)) {
    if (-not [string]::IsNullOrWhiteSpace($tool)) {
        [void]$toolsToEnsure.Add($tool.ToLowerInvariant())
    }
}

if ($IncludeOptional) {
    foreach ($tool in @("uv", "docker", "gh", "pwsh")) {
        [void]$toolsToEnsure.Add($tool)
    }
}

$managerOrder = Get-ManagerOrder -Mode $PackageManager

$rows = New-Object System.Collections.Generic.List[object]
$hadFailures = $false
$anyChanges = $false
$environmentRefreshed = $false

if ($PackageManagersOnly) {
    $UpdatePackageManagers = $true
}

if ($UpdatePackageManagers) {
    $maintenance = Invoke-PackageManagerMaintenance -Mode $PackageManager
    foreach ($row in @($maintenance.Rows)) {
        $rows.Add($row)
    }
    if ($maintenance.HadFailure) {
        $hadFailures = $true
    }
    if ($maintenance.AnyChanges) {
        $anyChanges = $true
    }

    if ($RefreshEnvironment -and -not $DryRun -and $maintenance.AnyChanges) {
        Invoke-ProcessEnvironmentRefresh
        Write-Output "Refreshed process environment variables after package manager maintenance."
        $environmentRefreshed = $true
    }

    $managerOrder = Get-ManagerOrder -Mode $PackageManager
}

if (-not $PackageManagersOnly -and $managerOrder.Count -eq 0) {
    throw "No package manager available. Install winget or choco, or run with -PackageManager targeting an available one."
}

if (($managerOrder -contains "choco" -or $UpdatePackageManagers) -and -not (Test-Admin)) {
    Write-Warning "Chocolatey operations may fail without an elevated PowerShell session."
}

if (-not $PackageManagersOnly) {
foreach ($toolName in ($toolsToEnsure | Sort-Object)) {
    if (-not $catalog.ContainsKey($toolName)) {
        $rows.Add([pscustomobject]@{
                Tool    = $toolName
                State   = "unknown"
                Action  = "none"
                Manager = "-"
                Result  = "No catalog mapping. Skipped."
            })
        continue
    }

    $definition = $catalog[$toolName]
    $available = Get-ToolStatus -Definition $definition -ToolName $toolName

    if ([bool]$definition.builtin) {
        $rows.Add([pscustomobject]@{
                Tool    = $toolName
                State   = if ($available) { "present" } else { "builtin" }
                Action  = "none"
                Manager = "-"
                Result  = "Built-in command"
            })
        continue
    }

    $desiredAction = $null
    if (-not $available -and $InstallMissing) {
        $desiredAction = "install"
    } elseif ($available -and $UpgradeExisting) {
        $desiredAction = "upgrade"
    } else {
        $rows.Add([pscustomobject]@{
                Tool    = $toolName
                State   = if ($available) { "present" } else { "missing" }
                Action  = "none"
                Manager = "-"
                Result  = "No action requested"
            })
        continue
    }

    $success = $false
    $managerUsed = "-"
    $failureReasons = @()
    $archiveAttempted = $false

    if ($toolName -eq "gradle" -and [string]::IsNullOrWhiteSpace($GradleVersion)) {
        $archiveAttempted = $true
        $managerUsed = "archive"
        $success = Invoke-GradleArchiveInstall -Action $desiredAction -Version $null
        if ($success) {
            if ($RefreshEnvironment -and -not $DryRun) {
                Invoke-ProcessEnvironmentRefresh
            }

            if (-not (Get-ToolStatus -Definition $definition -ToolName $toolName)) {
                $success = $false
                $failureReasons += "archive install completed but 'gradle' is still unavailable"
            } else {
                $anyChanges = $true
            }
        } else {
            $failureReasons += "archive install failed"
            $managerUsed = "-"
        }
    }

    if ($success) {
        $rows.Add([pscustomobject]@{
                Tool    = $toolName
                State   = if ($available) { "present" } else { "missing" }
                Action  = $desiredAction
                Manager = $managerUsed
                Result  = "ok"
            })
        continue
    }

    foreach ($manager in $managerOrder) {
        $commandSucceeded = $false
        if ($manager -eq "winget") {
            $id = $definition.winget
            if ([string]::IsNullOrWhiteSpace($id)) {
                $failureReasons += "winget id missing"
                continue
            }
            $commandSucceeded = Invoke-WingetAction -Action $desiredAction -PackageId $id
        } elseif ($manager -eq "choco") {
            $id = $definition.choco
            if ([string]::IsNullOrWhiteSpace($id)) {
                $failureReasons += "choco id missing"
                continue
            }
            $commandSucceeded = Invoke-ChocoAction -Action $desiredAction -PackageId $id
        }

        if (-not $commandSucceeded) {
            $failureReasons += "$manager command failed"
            continue
        }

        if ($RefreshEnvironment -and -not $DryRun) {
            Invoke-ProcessEnvironmentRefresh
        }

        if (-not (Get-ToolStatus -Definition $definition -ToolName $toolName)) {
            $failureReasons += "$manager completed but '$toolName' is still unavailable"
            continue
        }

        $managerUsed = $manager
        $success = $true
        $anyChanges = $true
        break
    }

    if (-not $success -and $toolName -eq "gradle" -and -not $archiveAttempted) {
        $managerUsed = "archive"
        $success = Invoke-GradleArchiveInstall -Action $desiredAction -Version $GradleVersion
        if ($success) {
            if ($RefreshEnvironment -and -not $DryRun) {
                Invoke-ProcessEnvironmentRefresh
            }

            if (-not (Get-ToolStatus -Definition $definition -ToolName $toolName)) {
                $success = $false
                $failureReasons += "archive install completed but 'gradle' is still unavailable"
            } else {
                $anyChanges = $true
            }
        } else {
            $failureReasons += "archive install failed"
        }
    }

    if ($success) {
        $rows.Add([pscustomobject]@{
                Tool    = $toolName
                State   = if ($available) { "present" } else { "missing" }
                Action  = $desiredAction
                Manager = $managerUsed
                Result  = "ok"
            })
    } else {
        $hadFailures = $true
        $rows.Add([pscustomobject]@{
                Tool    = $toolName
                State   = if ($available) { "present" } else { "missing" }
                Action  = $desiredAction
                Manager = if ($managerUsed -eq "-") { "-" } else { $managerUsed }
                Result  = ($failureReasons -join "; ")
            })
    }
}
}

$rows | Format-Table -AutoSize | Out-String | Write-Output

if ($RefreshEnvironment -and -not $environmentRefreshed) {
    if ($DryRun) {
        Write-Output "[DryRun] Would refresh process environment from Machine/User scope."
    } else {
        Invoke-ProcessEnvironmentRefresh
        Write-Output "Refreshed process environment variables."
    }
}

if ($OpenNewShell) {
    $nextCommand = if ([string]::IsNullOrWhiteSpace($ShellCommand)) { "pwsh -NoProfile -File .\scripts\preflight.ps1 -Phase all" } else { $ShellCommand }
    Invoke-NewShellIfRequested -CommandToRun $nextCommand
}

if ($anyChanges) {
    if ($DryRun) {
        Write-Output "Toolchain actions planned (dry run)."
    } else {
        Write-Output "Toolchain changes were applied."
    }
} else {
    Write-Output "No toolchain changes were needed."
}

if ($hadFailures) {
    if ($FailOnError) {
        throw "One or more toolchain actions failed."
    }
    Write-Warning "One or more toolchain actions failed."
}
