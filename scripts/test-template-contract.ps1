[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

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

$failures = New-Object System.Collections.Generic.List[string]

foreach ($templateName in ($templates.Keys | Sort-Object)) {
    $config = $templates[$templateName]
    $templatePath = Join-Path $repoRoot ("templates\" + $templateName)

    if (-not (Test-Path -LiteralPath $templatePath -PathType Container)) {
        $failures.Add("[$templateName] template directory missing: $templatePath")
        continue
    }

    $requiredFiles = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @("README.md", ".gitignore", ".gitattributes")) {
        [void]$requiredFiles.Add($file)
    }
    foreach ($file in @($config.required_files)) {
        if (-not [string]::IsNullOrWhiteSpace("$file")) {
            [void]$requiredFiles.Add("$file")
        }
    }
    if (-not [string]::IsNullOrWhiteSpace("$($config.entrypoint)")) {
        [void]$requiredFiles.Add("$($config.entrypoint)")
    }
    if (-not [string]::IsNullOrWhiteSpace("$($config.test_file)")) {
        [void]$requiredFiles.Add("$($config.test_file)")
    }

    foreach ($relativePath in ($requiredFiles | Sort-Object)) {
        $fullPath = Join-Path $templatePath $relativePath
        if (-not (Test-Path -LiteralPath $fullPath)) {
            $failures.Add("[$templateName] missing required file: $relativePath")
        }
    }

    $textFiles = Get-ChildItem -LiteralPath $templatePath -Recurse -File | Where-Object {
        $_.Extension -in @(".md", ".txt", ".toml", ".json", ".yaml", ".yml", ".ps1", ".psm1", ".cmd", ".bat", ".ini", ".go", ".mod", ".sum", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".py", ".dart", ".kt", ".kts", ".html", ".css", ".env", ".gradle", ".xml") -or $_.Name -in @(".gitignore", ".env.example", "Makefile")
    }

    $allText = ""
    foreach ($file in $textFiles) {
        $allText += "`n" + (Get-Content -LiteralPath $file.FullName -Raw)
    }

    if ($allText -notmatch "\{\{project_name\}\}") {
        $failures.Add("[$templateName] missing token '{{project_name}}' in template text files")
    }
    if ($allText -notmatch "\{\{project_slug\}\}") {
        $failures.Add("[$templateName] missing token '{{project_slug}}' in template text files")
    }

    $requiresModuleToken = [bool]$config.python_module_template -or "$($config.install_strategy)" -eq "flutter_full"
    if ($requiresModuleToken -and $allText -notmatch "\{\{project_module\}\}") {
        $failures.Add("[$templateName] expected token '{{project_module}}' not found")
    }
}

if ($failures.Count -gt 0) {
    Write-Output "Template contract checks failed:"
    foreach ($failure in $failures) {
        Write-Output "- $failure"
    }
    exit 1
}

Write-Output "Template contract checks passed for $($templates.Count) templates."
