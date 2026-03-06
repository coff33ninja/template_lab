[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "python-tool",
        "node-api",
        "go-service",
        "flutter-app",
        "kotlin-android",
        "powershell-tool",
        "web-static",
        "mad-lab"
    )]
    [string]$Template,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    [string]$Destination = (Get-Location).Path,

    [string]$Repo = "coff33ninja/template_lab",

    [string]$Ref = "main",

    [switch]$Force,

    [switch]$InstallDeps,

    [switch]$RunChecks,

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

    [switch]$KeepDownloadedFiles
)

$ErrorActionPreference = "Stop"

$tempRoot = Join-Path $env:TEMP ("template-lab-" + [guid]::NewGuid().ToString("N"))
$archivePath = Join-Path $tempRoot "template_lab.zip"

New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    $archiveUrl = "https://github.com/$Repo/archive/refs/heads/$Ref.zip"
    Write-Output "Downloading template archive from $archiveUrl ..."
    Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath

    Write-Output "Extracting archive ..."
    Expand-Archive -Path $archivePath -DestinationPath $tempRoot -Force

    $extracted = Get-ChildItem -Path $tempRoot -Directory | Where-Object { $_.Name -ne "__MACOSX" } | Select-Object -First 1
    if ($null -eq $extracted) {
        throw "Could not find extracted template folder."
    }

    $newProjectScript = Join-Path $extracted.FullName "scripts\new-project.ps1"
    if (-not (Test-Path -Path $newProjectScript -PathType Leaf)) {
        throw "new-project.ps1 not found in extracted archive."
    }

    $specPath = $null
    if (-not [string]::IsNullOrWhiteSpace($DependencySpecFile)) {
        $specPath = (Resolve-Path -LiteralPath $DependencySpecFile).Path
    }

    $newProjectArgs = @{
        Template             = $Template
        Name                 = $Name
        Destination          = $Destination
        PythonEnvManager     = $PythonEnvManager
        PythonVenvName       = $PythonVenvName
        InitialCommitMessage = $InitialCommitMessage
        DefaultBranch        = $DefaultBranch
        Visibility           = $Visibility
    }

    if ($Force) { $newProjectArgs.Force = $true }
    if ($InstallDeps) { $newProjectArgs.InstallDeps = $true }
    if ($RunChecks) { $newProjectArgs.RunChecks = $true }
    if ($AdditionalPackages.Count -gt 0) { $newProjectArgs.AdditionalPackages = $AdditionalPackages }
    if ($specPath) { $newProjectArgs.DependencySpecFile = $specPath }
    if (-not [string]::IsNullOrWhiteSpace($PythonVersion)) { $newProjectArgs.PythonVersion = $PythonVersion }
    if ($InitGit) { $newProjectArgs.InitGit = $true }
    if ($CreateGitHub) { $newProjectArgs.CreateGitHub = $true }
    if (-not [string]::IsNullOrWhiteSpace($GitHubRepo)) { $newProjectArgs.GitHubRepo = $GitHubRepo }
    if ($Push) { $newProjectArgs.Push = $true }

    & $newProjectScript @newProjectArgs
}
finally {
    if (-not $KeepDownloadedFiles -and (Test-Path -Path $tempRoot)) {
        Remove-Item -Path $tempRoot -Recurse -Force
    }
}
