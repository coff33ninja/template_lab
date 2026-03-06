[CmdletBinding()]
param(
    [string]$Template,

    [ValidateSet("install", "check", "all")]
    [string]$Phase = "all",

    [switch]$FailOnMissing
)

$ErrorActionPreference = "Stop"

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

function Test-Tool {
    param([Parameter(Mandatory = $true)][string]$Tool)

    switch ($Tool.ToLowerInvariant()) {
        "python" {
            return [bool](Get-Command "python" -ErrorAction SilentlyContinue) -or [bool](Get-Command "py" -ErrorAction SilentlyContinue)
        }
        "java" {
            return [bool](Get-Command "java" -ErrorAction SilentlyContinue)
        }
        "gradle" {
            return [bool](Get-GradleCommandPath)
        }
        default {
            return [bool](Get-Command $Tool -ErrorAction SilentlyContinue)
        }
    }
}

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

$templateNames = if ([string]::IsNullOrWhiteSpace($Template)) {
    @($templates.Keys | Sort-Object)
} else {
    if (-not $templates.ContainsKey($Template)) {
        throw "Unknown template '$Template'."
    }
    @($Template)
}

$requiredTools = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
[void]$requiredTools.Add("git")

foreach ($templateName in $templateNames) {
    $cfg = $templates[$templateName]

    if ($Phase -in @("install", "all")) {
        foreach ($tool in @($cfg.required_tools.install)) {
            if (-not [string]::IsNullOrWhiteSpace("$tool")) {
                [void]$requiredTools.Add("$tool")
            }
        }
    }

    if ($Phase -in @("check", "all")) {
        foreach ($tool in @($cfg.required_tools.check)) {
            if (-not [string]::IsNullOrWhiteSpace("$tool")) {
                [void]$requiredTools.Add("$tool")
            }
        }
    }
}

$results = @()
$missing = @()

foreach ($tool in ($requiredTools | Sort-Object)) {
    $available = Test-Tool -Tool $tool
    $results += [pscustomobject]@{
        Tool      = $tool
        Available = $available
    }

    if (-not $available) {
        $missing += $tool
    }
}

$results | Format-Table -AutoSize | Out-String | Write-Output

if ($missing.Count -gt 0) {
    $message = "Missing tools: $($missing -join ', ')"
    if ($FailOnMissing) {
        throw $message
    }

    Write-Warning $message
    Write-Output "Tip: run 'pwsh -File .\scripts\setup-toolchain.ps1 -Phase $Phase -InstallMissing:$true -UpgradeExisting:$false' to bootstrap missing tools."
} else {
    Write-Output "All required tools are available for phase '$Phase'."
}

$optionalTools = @("uv", "docker", "gh", "pwsh")
$optionalResults = foreach ($tool in $optionalTools) {
    [pscustomobject]@{
        Tool      = $tool
        Available = (Test-Tool -Tool $tool)
    }
}

Write-Output ""
Write-Output "Optional tools (for richer workflows):"
$optionalResults | Format-Table -AutoSize | Out-String | Write-Output
