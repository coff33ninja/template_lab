[CmdletBinding()]
param(
    [string]$Path = (Get-Location).Path,

    [string]$InitialCommitMessage = "chore: initial commit",

    [string]$DefaultBranch = "main",

    [switch]$CreateGitHub,

    [string]$GitHubRepo,

    [ValidateSet("private", "public", "internal")]
    [string]$Visibility = "private",

    [switch]$Push
)

$ErrorActionPreference = "Stop"

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

Require-Command -Name "git"

$projectPath = (Resolve-Path -LiteralPath $Path).Path
Push-Location $projectPath

try {
    if (-not (Test-Path -Path ".git" -PathType Container)) {
        & git init -b $DefaultBranch 2>$null
        if ($LASTEXITCODE -ne 0) {
            & git init
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to initialize git repository."
            }
            & git branch -M $DefaultBranch
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to set default branch to '$DefaultBranch'."
            }
        }
        Write-Output "Initialized git repository on branch '$DefaultBranch'."
    }

    & git add -A
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to stage files."
    }

    & git rev-parse --verify HEAD *> $null
    $hasCommit = $LASTEXITCODE -eq 0

    & git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        $hasStagedChanges = $false
    } elseif ($LASTEXITCODE -eq 1) {
        $hasStagedChanges = $true
    } else {
        throw "Unable to determine staged change status."
    }

    if ($hasStagedChanges) {
        & git commit -m $InitialCommitMessage
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create commit."
        }
    } elseif (-not $hasCommit) {
        & git commit --allow-empty -m $InitialCommitMessage
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create initial empty commit."
        }
    } else {
        Write-Output "No staged changes detected; commit skipped."
    }

    if ($CreateGitHub) {
        Require-Command -Name "gh"

        $repoName = if ([string]::IsNullOrWhiteSpace($GitHubRepo)) {
            Split-Path -Leaf $projectPath
        } else {
            $GitHubRepo
        }

        & git remote get-url origin *> $null
        $hasOrigin = $LASTEXITCODE -eq 0

        $ghArgs = @(
            "repo", "create", $repoName,
            "--$Visibility",
            "--source", $projectPath
        )
        if (-not $hasOrigin) {
            $ghArgs += @("--remote", "origin")
        }
        if ($Push) {
            $ghArgs += "--push"
        }

        & gh @ghArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create GitHub repository."
        }

        Write-Output "GitHub repository ready: $repoName"
    } elseif ($Push) {
        & git remote get-url origin *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "Push requested but no 'origin' remote is configured."
        }
        & git push -u origin $DefaultBranch
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to push to origin."
        }
    }

    Write-Output "Repository setup complete at '$projectPath'."
}
finally {
    Pop-Location
}
