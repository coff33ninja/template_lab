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
        $_.Extension -in @(".md", ".txt", ".toml", ".json", ".yaml", ".yml", ".ps1", ".psm1", ".cmd", ".bat", ".ini", ".go", ".mod", ".sum", ".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".py", ".dart", ".kt", ".kts", ".html", ".css", ".env", ".gradle", ".xml") -or $_.Name -in @(".gitignore", ".env.example", "Makefile")
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

$stackCount = 0
if ($manifest.ContainsKey("stacks")) {
    $stacks = $manifest.stacks
    $stackCount = @($stacks.Keys).Count

    foreach ($stackName in ($stacks.Keys | Sort-Object)) {
        $stackConfig = $stacks[$stackName]
        $components = @($stackConfig.components)

        if ($components.Count -eq 0) {
            $failures.Add("[stack:$stackName] no components defined")
            continue
        }

        $componentPaths = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        $position = 0
        foreach ($component in $components) {
            $position++

            $templateRef = "$($component.template)"
            if ([string]::IsNullOrWhiteSpace($templateRef)) {
                $failures.Add("[stack:$stackName] component #$position missing template")
                continue
            }
            if (-not $templates.ContainsKey($templateRef)) {
                $failures.Add("[stack:$stackName] component #$position references unknown template '$templateRef'")
            }

            $pathRef = if ($component.ContainsKey("path") -and -not [string]::IsNullOrWhiteSpace("$($component.path)")) {
                "$($component.path)".Replace("/", "\").Trim("\")
            } else {
                $templateRef
            }
            if ([string]::IsNullOrWhiteSpace($pathRef)) {
                $failures.Add("[stack:$stackName] component #$position has empty path")
                continue
            }
            if (-not $componentPaths.Add($pathRef)) {
                $failures.Add("[stack:$stackName] duplicate component path '$pathRef'")
            }
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Output "Template contract checks failed:"
    foreach ($failure in $failures) {
        Write-Output "- $failure"
    }
    exit 1
}

Write-Output "Template contract checks passed for $($templates.Count) templates and $stackCount stacks."
