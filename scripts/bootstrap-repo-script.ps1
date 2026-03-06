[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("preflight", "setup-toolchain")]
    [string]$Script,

    [string]$Template,

    [ValidateSet("install", "check", "all")]
    [string]$Phase = "all",

    [switch]$FailOnMissing,

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

    [switch]$AllowBootstrapScript,

    [string]$Repo = "coff33ninja/template_lab",

    [string]$Ref = "v1.0.4",

    [ValidateSet("tag", "branch")]
    [string]$RefType = "tag",

    [string]$ArchiveSha256,

    [switch]$AllowMutableRef,

    [switch]$AllowUnverified,

    [switch]$KeepDownloadedFiles
)

$ErrorActionPreference = "Stop"

function Resolve-ExpectedHash {
    param(
        [string]$ExplicitHash,
        [string]$ChecksumFile,
        [switch]$AllowUnverifiedMode
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitHash)) {
        return $ExplicitHash.Trim().ToLowerInvariant()
    }

    if (Test-Path -LiteralPath $ChecksumFile -PathType Leaf) {
        $raw = (Get-Content -LiteralPath $ChecksumFile -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            return (($raw -split "\s+")[0]).ToLowerInvariant()
        }
    }

    if ($AllowUnverifiedMode) {
        return $null
    }

    throw "No SHA256 hash provided. Pass -ArchiveSha256, publish a .sha256 release asset, or use -AllowUnverified."
}

function Resolve-RepoScriptFromArchive {
    param(
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $true)][string]$RelativeScriptPath
    )

    $scriptCandidates = [System.Collections.Generic.List[string]]::new()

    $rootCandidate = Join-Path $TempRoot $RelativeScriptPath
    if (Test-Path -LiteralPath $rootCandidate -PathType Leaf) {
        $scriptCandidates.Add($rootCandidate)
    }

    Get-ChildItem -LiteralPath $TempRoot -Directory |
        Where-Object { $_.Name -ne "__MACOSX" } |
        ForEach-Object {
            $candidate = Join-Path $_.FullName $RelativeScriptPath
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $scriptCandidates.Add($candidate)
            }
        }

    if ($scriptCandidates.Count -eq 0) {
        throw "$RelativeScriptPath not found in extracted archive."
    }

    $scriptPath = $scriptCandidates[0]
    $repoRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)

    return @{
        ScriptPath = $scriptPath
        RepoRoot   = $repoRoot
    }
}

function Get-TargetScriptRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptName
    )

    switch ($ScriptName) {
        "preflight" { return "scripts\preflight.ps1" }
        "setup-toolchain" { return "scripts\setup-toolchain.ps1" }
        default { throw "Unsupported script '$ScriptName'." }
    }
}

if ($Script -eq "setup-toolchain" -and $OpenNewShell -and -not $KeepDownloadedFiles -and -not $DryRun) {
    throw "-OpenNewShell requires -KeepDownloadedFiles in bootstrap-repo-script mode so the extracted repo remains available to the new shell."
}

$tempRoot = Join-Path $env:TEMP ("template-lab-script-" + [guid]::NewGuid().ToString("N"))
$archivePath = Join-Path $tempRoot "template_lab.zip"
$checksumPath = Join-Path $tempRoot "template_lab.zip.sha256"

New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    if ($RefType -eq "branch" -and -not $AllowMutableRef) {
        throw "RefType 'branch' is mutable and blocked by default. Use -AllowMutableRef to proceed or switch to -RefType tag."
    }

    $archiveUrl = $null
    $checksumUrl = $null

    if ($RefType -eq "tag") {
        $assetName = "template_lab-$Ref.zip"
        $checksumAssetName = "$assetName.sha256"
        $archiveUrl = "https://github.com/$Repo/releases/download/$Ref/$assetName"
        $checksumUrl = "https://github.com/$Repo/releases/download/$Ref/$checksumAssetName"
    } else {
        $archiveUrl = "https://github.com/$Repo/archive/refs/heads/$Ref.zip"
    }

    Write-Output "Downloading template archive from $archiveUrl ..."
    Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath

    if ($checksumUrl) {
        try {
            Write-Output "Downloading checksum from $checksumUrl ..."
            Invoke-WebRequest -Uri $checksumUrl -OutFile $checksumPath
        }
        catch {
            if (-not $AllowUnverified -and [string]::IsNullOrWhiteSpace($ArchiveSha256)) {
                throw "Failed to download checksum file from release assets: $checksumUrl"
            }

            Write-Warning "Checksum asset not found for $Ref; continuing based on provided flags."
        }
    }

    $expectedHash = Resolve-ExpectedHash -ExplicitHash $ArchiveSha256 -ChecksumFile $checksumPath -AllowUnverifiedMode:$AllowUnverified
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($expectedHash)) {
        if ($actualHash -ne $expectedHash) {
            throw "SHA256 mismatch for downloaded archive. Expected '$expectedHash', got '$actualHash'."
        }
        Write-Output "Archive SHA256 verification passed."
    } else {
        Write-Warning "Archive downloaded without SHA256 verification (-AllowUnverified)."
    }

    Write-Output "Extracting archive ..."
    Expand-Archive -LiteralPath $archivePath -DestinationPath $tempRoot -Force

    $targetScript = Resolve-RepoScriptFromArchive -TempRoot $tempRoot -RelativeScriptPath (Get-TargetScriptRelativePath -ScriptName $Script)
    $scriptArgs = @{}

    switch ($Script) {
        "preflight" {
            if (-not [string]::IsNullOrWhiteSpace($Template)) { $scriptArgs.Template = $Template }
            $scriptArgs.Phase = $Phase
            if ($FailOnMissing) { $scriptArgs.FailOnMissing = $true }
        }

        "setup-toolchain" {
            if (-not [string]::IsNullOrWhiteSpace($Template)) { $scriptArgs.Template = $Template }
            $scriptArgs.Phase = $Phase
            if ($Tools.Count -gt 0) { $scriptArgs.Tools = $Tools }
            if ($IncludeOptional) { $scriptArgs.IncludeOptional = $true }
            $scriptArgs.InstallMissing = $InstallMissing
            $scriptArgs.UpgradeExisting = $UpgradeExisting
            if (-not [string]::IsNullOrWhiteSpace($PythonVersion)) { $scriptArgs.PythonVersion = $PythonVersion }
            if (-not [string]::IsNullOrWhiteSpace($JavaVersion)) { $scriptArgs.JavaVersion = $JavaVersion }
            if (-not [string]::IsNullOrWhiteSpace($GradleVersion)) { $scriptArgs.GradleVersion = $GradleVersion }
            $scriptArgs.PackageManager = $PackageManager
            $scriptArgs.RefreshEnvironment = $RefreshEnvironment
            if ($OpenNewShell) { $scriptArgs.OpenNewShell = $true }
            if (-not [string]::IsNullOrWhiteSpace($ShellCommand)) { $scriptArgs.ShellCommand = $ShellCommand }
            if ($FailOnError) { $scriptArgs.FailOnError = $true }
            if ($DryRun) { $scriptArgs.DryRun = $true }
            if ($UpdatePackageManagers) { $scriptArgs.UpdatePackageManagers = $true }
            if ($PackageManagersOnly) { $scriptArgs.PackageManagersOnly = $true }
            if ($AllowBootstrapScript) { $scriptArgs.AllowBootstrapScript = $true }
        }
    }

    Push-Location $targetScript.RepoRoot
    try {
        & $targetScript.ScriptPath @scriptArgs
    }
    finally {
        Pop-Location
    }
}
finally {
    if (-not $KeepDownloadedFiles -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    } elseif ($KeepDownloadedFiles) {
        Write-Output "Kept extracted repo at '$tempRoot'."
    }
}
