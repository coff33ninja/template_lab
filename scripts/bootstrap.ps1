[CmdletBinding(DefaultParameterSetName = "Template")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Template")]
    [string]$Template,

    [Parameter(Mandatory = $true, ParameterSetName = "Stack")]
    [string]$Stack,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    [string]$Destination = (Get-Location).Path,

    [string]$Repo = "coff33ninja/template_lab",

    [string]$Ref = "v1.0.4",

    [ValidateSet("tag", "branch")]
    [string]$RefType = "tag",

    [string]$ArchiveSha256,

    [switch]$AllowMutableRef,

    [switch]$AllowUnverified,

    [switch]$Force,

    [switch]$InstallDeps,

    [switch]$RunChecks,

    [switch]$DryRun,

    [switch]$SkipChecksOnMissingTool,

    [string[]]$AdditionalPackages = @(),

    [string]$DependencySpecFile,

    [ValidateSet("auto", "uv", "venv")]
    [string]$PythonEnvManager = "auto",

    [string]$PythonVenvName = ".venv",

    [string]$PythonVersion,

    [switch]$InitGit,

    [string]$InitialCommitMessage = "chore: initial commit",

    [string]$DefaultBranch = "main",

    [switch]$CreateGitHub,

    [string]$GitHubRepo,

    [ValidateSet("private", "public", "internal")]
    [string]$Visibility = "private",

    [switch]$Push,

    [switch]$IncludeLicense,

    [ValidateSet("MIT", "Apache-2.0", "BSD-3-Clause", "Unlicense")]
    [string]$LicenseType = "MIT",

    [switch]$IncludeContributing,

    [switch]$IncludeCodeOfConduct,

    [string]$PostCreateScript,

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

$tempRoot = Join-Path $env:TEMP ("template-lab-" + [guid]::NewGuid().ToString("N"))
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

    $scriptCandidates = [System.Collections.Generic.List[string]]::new()

    $rootCandidate = Join-Path $tempRoot "scripts\new-project.ps1"
    if (Test-Path -LiteralPath $rootCandidate -PathType Leaf) {
        $scriptCandidates.Add($rootCandidate)
    }

    Get-ChildItem -LiteralPath $tempRoot -Directory |
        Where-Object { $_.Name -ne "__MACOSX" } |
        ForEach-Object {
            $candidate = Join-Path $_.FullName "scripts\new-project.ps1"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $scriptCandidates.Add($candidate)
            }
        }

    if ($scriptCandidates.Count -eq 0) {
        throw "new-project.ps1 not found in extracted archive."
    }

    $newProjectScript = $scriptCandidates[0]

    $specPath = $null
    if (-not [string]::IsNullOrWhiteSpace($DependencySpecFile)) {
        $specPath = (Resolve-Path -LiteralPath $DependencySpecFile).Path
    }

    $newProjectArgs = @{
        Name                 = $Name
        Destination          = $Destination
        PythonEnvManager     = $PythonEnvManager
        PythonVenvName       = $PythonVenvName
        InitialCommitMessage = $InitialCommitMessage
        DefaultBranch        = $DefaultBranch
        Visibility           = $Visibility
    }

    if ($PSCmdlet.ParameterSetName -eq "Stack") {
        $newProjectArgs.Stack = $Stack
    } else {
        $newProjectArgs.Template = $Template
    }

    if ($Force) { $newProjectArgs.Force = $true }
    if ($InstallDeps) { $newProjectArgs.InstallDeps = $true }
    if ($RunChecks) { $newProjectArgs.RunChecks = $true }
    if ($DryRun) { $newProjectArgs.DryRun = $true }
    if ($SkipChecksOnMissingTool) { $newProjectArgs.SkipChecksOnMissingTool = $true }
    if ($AdditionalPackages.Count -gt 0) { $newProjectArgs.AdditionalPackages = $AdditionalPackages }
    if ($specPath) { $newProjectArgs.DependencySpecFile = $specPath }
    if (-not [string]::IsNullOrWhiteSpace($PythonVersion)) { $newProjectArgs.PythonVersion = $PythonVersion }
    if ($InitGit) { $newProjectArgs.InitGit = $true }
    if ($CreateGitHub) { $newProjectArgs.CreateGitHub = $true }
    if (-not [string]::IsNullOrWhiteSpace($GitHubRepo)) { $newProjectArgs.GitHubRepo = $GitHubRepo }
    if ($Push) { $newProjectArgs.Push = $true }
    if ($IncludeLicense) { $newProjectArgs.IncludeLicense = $true; $newProjectArgs.LicenseType = $LicenseType }
    if ($IncludeContributing) { $newProjectArgs.IncludeContributing = $true }
    if ($IncludeCodeOfConduct) { $newProjectArgs.IncludeCodeOfConduct = $true }
    if (-not [string]::IsNullOrWhiteSpace($PostCreateScript)) { $newProjectArgs.PostCreateScript = $PostCreateScript }

    & $newProjectScript @newProjectArgs
}
finally {
    if (-not $KeepDownloadedFiles -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
