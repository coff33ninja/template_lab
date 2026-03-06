[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Template,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    [string]$Destination = (Get-Location).Path,

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

    [string]$PostCreateScript
)

$ErrorActionPreference = "Stop"
$script:AuditLog = [System.Collections.Generic.List[string]]::new()
$script:DryRunMode = [bool]$DryRun
$script:SkipMissingTools = [bool]$SkipChecksOnMissingTool
$script:ScaffoldRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "scaffolds"

function Add-AuditEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffK"
    $script:AuditLog.Add("$timestamp | $Message")
}

function Write-AuditFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )

    if ($script:DryRunMode) {
        return
    }

    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
        return
    }

    $logPath = Join-Path $ProjectPath "scaffold.log"
    [System.IO.File]::WriteAllLines($logPath, $script:AuditLog, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-StringArray {
    param(
        $Value
    )

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return @()
        }
        return @($Value)
    }

    $items = @()
    foreach ($item in $Value) {
        $valueText = "$item"
        if (-not [string]::IsNullOrWhiteSpace($valueText)) {
            $items += $valueText
        }
    }
    return $items
}

function Format-CommandForLog {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @()
    )

    $renderedArguments = foreach ($arg in $Arguments) {
        if ($arg -match '[\s"]') {
            '"' + ($arg -replace '"', '\\"') + '"'
        } else {
            $arg
        }
    }

    if ($renderedArguments.Count -eq 0) {
        return $Command
    }

    return "$Command $($renderedArguments -join ' ')"
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    $renderedCommand = Format-CommandForLog -Command $Command -Arguments $Arguments
    Add-AuditEntry -Message "command: $renderedCommand"

    if ($script:DryRunMode) {
        Write-Output "[DryRun] $renderedCommand"
        return
    }

    & $Command @Arguments
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) {
        $exitCode = 0
    }

    if ($exitCode -ne 0) {
        throw "$FailureMessage (exit code $exitCode)"
    }
}

function Get-TemplateManifest {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $manifestPath = Join-Path $RepoRoot "templates\manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Missing template manifest: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
    if ($null -eq $manifest -or -not $manifest.ContainsKey("templates")) {
        throw "Template manifest is invalid: $manifestPath"
    }

    Add-AuditEntry -Message "manifest: $manifestPath"
    return $manifest
}

function Get-TemplateConfig {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$TemplateName
    )

    $templates = $Manifest["templates"]
    if (-not $templates.ContainsKey($TemplateName)) {
        $validTemplates = @($templates.Keys | Sort-Object) -join ", "
        throw "Unknown template '$TemplateName'. Valid templates: $validTemplates"
    }

    return $templates[$TemplateName]
}

function Test-ToolAvailable {
    param(
        [Parameter(Mandatory = $true)][string]$Tool,
        [string]$ProjectPath
    )

    switch ($Tool.ToLowerInvariant()) {
        "python" {
            return [bool](Get-Command "python" -ErrorAction SilentlyContinue) -or [bool](Get-Command "py" -ErrorAction SilentlyContinue)
        }
        "gradle" {
            $wrapperPath = if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $null } else { Join-Path $ProjectPath "gradlew.bat" }
            return (Test-Path -LiteralPath $wrapperPath -PathType Leaf) -or [bool](Get-Command "gradle" -ErrorAction SilentlyContinue)
        }
        default {
            return [bool](Get-Command $Tool -ErrorAction SilentlyContinue)
        }
    }
}

function Test-ToolsAvailableForPhase {
    param(
        [string[]]$Tools = @(),
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$ProjectPath
    )

    $toolList = ConvertTo-StringArray -Value $Tools
    if ($toolList.Count -eq 0) {
        return $true
    }

    $missingTools = @()
    foreach ($tool in $toolList) {
        if (-not (Test-ToolAvailable -Tool $tool -ProjectPath $ProjectPath)) {
            $missingTools += $tool
        }
    }

    if ($missingTools.Count -eq 0) {
        return $true
    }

    $message = "Missing required tool(s) for $Phase on template '$TemplateName': $($missingTools -join ', ')."
    if ($script:SkipMissingTools) {
        Write-Warning "$message Skipping $Phase."
        Add-AuditEntry -Message "skip-${Phase}: $($missingTools -join ',')"
        return $false
    }

    throw $message
}
function Resolve-UserPackage {
    param(
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$SpecFilePath,
        [string[]]$InlinePackages = @()
    )

    $packages = @()

    if (-not [string]::IsNullOrWhiteSpace($SpecFilePath)) {
        $resolvedSpecPath = (Resolve-Path -LiteralPath $SpecFilePath).Path
        $spec = Get-Content -LiteralPath $resolvedSpecPath -Raw | ConvertFrom-Json -AsHashtable

        if ($null -eq $spec) {
            throw "Dependency spec file is empty or invalid JSON: $resolvedSpecPath"
        }

        if ($spec.ContainsKey($TemplateName)) {
            $entry = $spec[$TemplateName]
            if ($entry -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($entry)) {
                    $packages += $entry
                }
            } else {
                foreach ($item in (ConvertTo-StringArray -Value $entry)) {
                    $packages += $item
                }
            }
        }
    }

    foreach ($pkg in (ConvertTo-StringArray -Value $InlinePackages)) {
        $packages += $pkg
    }

    if ($packages.Count -eq 0) {
        return @()
    }

    return @($packages | Select-Object -Unique)
}

function Get-ProjectIdentity {
    param([Parameter(Mandatory = $true)][string]$ProjectName)

    $slug = ($ProjectName.ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-")
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = "project"
    }

    $module = ($ProjectName.ToLowerInvariant() -replace "[^a-z0-9]+", "_").Trim("_")
    if ([string]::IsNullOrWhiteSpace($module)) {
        $module = "app"
    }
    if ($module -match "^[0-9]") {
        $module = "app_$module"
    }

    return @{
        slug = $slug
        module = $module
    }
}

function Invoke-PythonModulePathAlignment {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$ModuleName,
        [bool]$IsPythonModuleTemplate = $false
    )

    if (-not $IsPythonModuleTemplate) {
        return
    }

    if ($ModuleName -eq "app") {
        return
    }

    $defaultPackagePath = Join-Path $ProjectPath "src\app"
    $modulePackagePath = Join-Path $ProjectPath ("src\" + $ModuleName)

    if (-not (Test-Path -LiteralPath $defaultPackagePath -PathType Container)) {
        return
    }

    Add-AuditEntry -Message "python-module-rename: src/app -> src/$ModuleName"
    if ($script:DryRunMode) {
        Write-Output "[DryRun] Would rename Python package path src/app -> src/$ModuleName"
        return
    }

    if (Test-Path -LiteralPath $modulePackagePath -PathType Container) {
        Remove-Item -LiteralPath $modulePackagePath -Recurse -Force -ErrorAction Stop
    }

    Copy-Item -LiteralPath $defaultPackagePath -Destination $modulePackagePath -Recurse -Force
    Remove-Item -LiteralPath $defaultPackagePath -Recurse -Force -ErrorAction Stop
}

function Invoke-PythonGitIgnoreUpdate {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$VenvName
    )

    $gitignorePath = Join-Path $ProjectPath ".gitignore"
    if (-not (Test-Path -LiteralPath $gitignorePath -PathType Leaf)) {
        return
    }

    $venvIgnoreEntry = $VenvName.Replace("\", "/").Trim()
    $venvIgnoreEntry = $venvIgnoreEntry -replace "^\./", ""
    if ([string]::IsNullOrWhiteSpace($venvIgnoreEntry)) {
        return
    }

    if (-not $venvIgnoreEntry.EndsWith("/")) {
        $venvIgnoreEntry += "/"
    }

    $ignoreLines = Get-Content -LiteralPath $gitignorePath
    if ($ignoreLines -contains $venvIgnoreEntry) {
        return
    }

    Add-AuditEntry -Message "gitignore-add: $venvIgnoreEntry"
    if ($script:DryRunMode) {
        Write-Output "[DryRun] Would append '$venvIgnoreEntry' to .gitignore"
        return
    }

    Add-Content -LiteralPath $gitignorePath -Value $venvIgnoreEntry
}

function Invoke-TemplateTokenReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)]$Tokens
    )

    $textExtensions = @(
        ".md", ".txt", ".toml", ".json", ".yaml", ".yml",
        ".ps1", ".psm1", ".cmd", ".bat", ".ini",
        ".go", ".mod", ".sum",
        ".js", ".mjs", ".cjs", ".ts", ".tsx",
        ".py", ".dart", ".kt", ".kts",
        ".html", ".css", ".env", ".gradle", ".xml"
    )
    $textNames = @(".gitignore", ".env.example", "Makefile")

    Get-ChildItem -LiteralPath $ProjectPath -Recurse -File | ForEach-Object {
        $isText = ($textExtensions -contains $_.Extension.ToLowerInvariant()) -or ($textNames -contains $_.Name)
        if (-not $isText) {
            return
        }

        $content = Get-Content -LiteralPath $_.FullName -Raw
        $updated = $content
        foreach ($token in $Tokens.Keys) {
            $updated = $updated -replace [regex]::Escape($token), $Tokens[$token]
        }

        if ($updated -eq $content) {
            return
        }

        Add-AuditEntry -Message "token-replace: $($_.FullName)"
        if ($script:DryRunMode) {
            Write-Output "[DryRun] Would replace tokens in $($_.FullName)"
            return
        }

        [System.IO.File]::WriteAllText($_.FullName, $updated, [System.Text.UTF8Encoding]::new($false))
    }
}

function Invoke-PythonPytest {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$PythonVenv,
        [string]$PythonTargetVersion,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    $venvPython = Join-Path $ProjectPath ($PythonVenv + "\Scripts\python.exe")
    if (Test-Path -LiteralPath $venvPython -PathType Leaf) {
        Invoke-ExternalCommand -Command $venvPython -Arguments @("-m", "pytest", "-q") -FailureMessage $FailureMessage
        return
    }

    if (Get-Command "python" -ErrorAction SilentlyContinue) {
        Invoke-ExternalCommand -Command "python" -Arguments @("-m", "pytest", "-q") -FailureMessage $FailureMessage
        return
    }

    if (Get-Command "py" -ErrorAction SilentlyContinue) {
        if (-not [string]::IsNullOrWhiteSpace($PythonTargetVersion)) {
            Invoke-ExternalCommand -Command "py" -Arguments @("-$PythonTargetVersion", "-m", "pytest", "-q") -FailureMessage $FailureMessage
        } else {
            Invoke-ExternalCommand -Command "py" -Arguments @("-3", "-m", "pytest", "-q") -FailureMessage $FailureMessage
        }
        return
    }

    throw "No Python interpreter available for checks."
}
function Install-TemplateDependenciesByStrategy {
    param(
        [Parameter(Mandatory = $true)][string]$Strategy,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [string[]]$UserPackages = @(),
        [string]$PythonVenv = ".venv",
        [ValidateSet("auto", "uv", "venv")][string]$PythonManager = "auto",
        [string]$PythonTargetVersion,
        [string]$ProjectModule = "app"
    )

    $projectFullPath = (Resolve-Path -LiteralPath $ProjectPath).Path
    Add-AuditEntry -Message "install-strategy: $TemplateName -> $Strategy"

    switch ($Strategy) {
        "none" {
            Write-Output "No dependency install step defined for template '$TemplateName'."
            return
        }

        "python_pyproject" {
            Push-Location $projectFullPath
            try {
                $uvAvailable = [bool](Get-Command "uv" -ErrorAction SilentlyContinue)
                $useUv = $false
                switch ($PythonManager) {
                    "uv" {
                        if (-not $uvAvailable) {
                            throw "PythonEnvManager is 'uv' but uv is not available."
                        }
                        $useUv = $true
                    }
                    "venv" {
                        $useUv = $false
                    }
                    default {
                        $useUv = $uvAvailable
                    }
                }

                if ($useUv) {
                    $uvVenvArgs = @("venv", $PythonVenv)
                    if (-not [string]::IsNullOrWhiteSpace($PythonTargetVersion)) {
                        $uvVenvArgs += @("--python", $PythonTargetVersion)
                    }

                    Invoke-ExternalCommand -Command "uv" -Arguments $uvVenvArgs -FailureMessage "uv venv failed."
                    $uvPython = Join-Path $projectFullPath ($PythonVenv + "\Scripts\python.exe")
                    Invoke-ExternalCommand -Command "uv" -Arguments @("pip", "install", "--python", $uvPython, "-e", ".[dev]") -FailureMessage "uv pip install failed."
                    if ($UserPackages.Count -gt 0) {
                        Invoke-ExternalCommand -Command "uv" -Arguments (@("pip", "install", "--python", $uvPython) + $UserPackages) -FailureMessage "uv pip install extra packages failed."
                    }
                    return
                }

                if (-not (Get-Command "python" -ErrorAction SilentlyContinue) -and -not (Get-Command "py" -ErrorAction SilentlyContinue)) {
                    throw "Neither python nor py is available for dependency install."
                }

                if (-not [string]::IsNullOrWhiteSpace($PythonTargetVersion) -and (Get-Command "py" -ErrorAction SilentlyContinue)) {
                    Invoke-ExternalCommand -Command "py" -Arguments @("-$PythonTargetVersion", "-m", "venv", $PythonVenv) -FailureMessage "py venv creation failed."
                } elseif (Get-Command "python" -ErrorAction SilentlyContinue) {
                    Invoke-ExternalCommand -Command "python" -Arguments @("-m", "venv", $PythonVenv) -FailureMessage "python venv creation failed."
                } else {
                    Invoke-ExternalCommand -Command "py" -Arguments @("-3", "-m", "venv", $PythonVenv) -FailureMessage "py venv creation failed."
                }

                $venvPython = Join-Path $projectFullPath ($PythonVenv + "\Scripts\python.exe")
                Invoke-ExternalCommand -Command $venvPython -Arguments @("-m", "pip", "install", "--upgrade", "pip") -FailureMessage "pip upgrade failed."
                Invoke-ExternalCommand -Command $venvPython -Arguments @("-m", "pip", "install", "-e", ".[dev]") -FailureMessage "pip install failed."
                if ($UserPackages.Count -gt 0) {
                    Invoke-ExternalCommand -Command $venvPython -Arguments (@("-m", "pip", "install") + $UserPackages) -FailureMessage "pip install extra packages failed."
                }
            }
            finally {
                Pop-Location
            }
            return
        }

        "python_requirements" {
            Push-Location $projectFullPath
            try {
                $uvAvailable = [bool](Get-Command "uv" -ErrorAction SilentlyContinue)
                $useUv = $false
                switch ($PythonManager) {
                    "uv" {
                        if (-not $uvAvailable) {
                            throw "PythonEnvManager is 'uv' but uv is not available."
                        }
                        $useUv = $true
                    }
                    "venv" {
                        $useUv = $false
                    }
                    default {
                        $useUv = $uvAvailable
                    }
                }

                if ($useUv) {
                    $uvVenvArgs = @("venv", $PythonVenv)
                    if (-not [string]::IsNullOrWhiteSpace($PythonTargetVersion)) {
                        $uvVenvArgs += @("--python", $PythonTargetVersion)
                    }

                    Invoke-ExternalCommand -Command "uv" -Arguments $uvVenvArgs -FailureMessage "uv venv failed."
                    $uvPython = Join-Path $projectFullPath ($PythonVenv + "\Scripts\python.exe")
                    Invoke-ExternalCommand -Command "uv" -Arguments @("pip", "install", "--python", $uvPython, "-r", "requirements.txt", "-r", "requirements-dev.txt") -FailureMessage "uv pip install requirements failed."
                    if ($UserPackages.Count -gt 0) {
                        Invoke-ExternalCommand -Command "uv" -Arguments (@("pip", "install", "--python", $uvPython) + $UserPackages) -FailureMessage "uv pip install extra packages failed."
                    }
                    return
                }

                if (-not (Get-Command "python" -ErrorAction SilentlyContinue) -and -not (Get-Command "py" -ErrorAction SilentlyContinue)) {
                    throw "Neither python nor py is available for dependency install."
                }

                if (-not [string]::IsNullOrWhiteSpace($PythonTargetVersion) -and (Get-Command "py" -ErrorAction SilentlyContinue)) {
                    Invoke-ExternalCommand -Command "py" -Arguments @("-$PythonTargetVersion", "-m", "venv", $PythonVenv) -FailureMessage "py venv creation failed."
                } elseif (Get-Command "python" -ErrorAction SilentlyContinue) {
                    Invoke-ExternalCommand -Command "python" -Arguments @("-m", "venv", $PythonVenv) -FailureMessage "python venv creation failed."
                } else {
                    Invoke-ExternalCommand -Command "py" -Arguments @("-3", "-m", "venv", $PythonVenv) -FailureMessage "py venv creation failed."
                }

                $venvPython = Join-Path $projectFullPath ($PythonVenv + "\Scripts\python.exe")
                Invoke-ExternalCommand -Command $venvPython -Arguments @("-m", "pip", "install", "--upgrade", "pip") -FailureMessage "pip upgrade failed."
                Invoke-ExternalCommand -Command $venvPython -Arguments @("-m", "pip", "install", "-r", "requirements.txt", "-r", "requirements-dev.txt") -FailureMessage "pip install requirements failed."
                if ($UserPackages.Count -gt 0) {
                    Invoke-ExternalCommand -Command $venvPython -Arguments (@("-m", "pip", "install") + $UserPackages) -FailureMessage "pip install extra packages failed."
                }
            }
            finally {
                Pop-Location
            }
            return
        }

        { $_ -in @("npm", "npm_workspace") } {
            Push-Location $projectFullPath
            try {
                Invoke-ExternalCommand -Command "npm" -Arguments @("install") -FailureMessage "npm install failed."
                if ($UserPackages.Count -gt 0) {
                    Invoke-ExternalCommand -Command "npm" -Arguments (@("install") + $UserPackages) -FailureMessage "npm extra package install failed."
                }
            }
            finally {
                Pop-Location
            }
            return
        }

        "go" {
            Push-Location $projectFullPath
            try {
                Invoke-ExternalCommand -Command "go" -Arguments @("mod", "tidy") -FailureMessage "go mod tidy failed."
                foreach ($moduleSpec in $UserPackages) {
                    Invoke-ExternalCommand -Command "go" -Arguments @("get", $moduleSpec) -FailureMessage "go get failed for '$moduleSpec'."
                }
                if ($UserPackages.Count -gt 0) {
                    Invoke-ExternalCommand -Command "go" -Arguments @("mod", "tidy") -FailureMessage "go mod tidy failed after extra modules."
                }
            }
            finally {
                Pop-Location
            }
            return
        }

        "flutter" {
            Push-Location $projectFullPath
            try {
                Invoke-ExternalCommand -Command "flutter" -Arguments @("pub", "get") -FailureMessage "flutter pub get failed."
                foreach ($pkg in $UserPackages) {
                    Invoke-ExternalCommand -Command "flutter" -Arguments @("pub", "add", $pkg) -FailureMessage "flutter pub add failed for '$pkg'."
                }
            }
            finally {
                Pop-Location
            }
            return
        }

        "flutter_full" {
            Push-Location $projectFullPath
            try {
                $androidBuild = Join-Path $projectFullPath "android\app\build.gradle"
                $androidBuildKts = Join-Path $projectFullPath "android\app\build.gradle.kts"
                if (-not (Test-Path -LiteralPath $androidBuild -PathType Leaf) -and -not (Test-Path -LiteralPath $androidBuildKts -PathType Leaf)) {
                    Invoke-ExternalCommand -Command "flutter" -Arguments @("create", "--project-name", $ProjectModule, "--platforms=android,ios,web,windows,linux,macos", ".") -FailureMessage "flutter create failed for flutter_full."
                }

                Invoke-ExternalCommand -Command "flutter" -Arguments @("pub", "get") -FailureMessage "flutter pub get failed."
                foreach ($pkg in $UserPackages) {
                    Invoke-ExternalCommand -Command "flutter" -Arguments @("pub", "add", $pkg) -FailureMessage "flutter pub add failed for '$pkg'."
                }
            }
            finally {
                Pop-Location
            }
            return
        }

        "gradle" {
            if ($UserPackages.Count -gt 0) {
                throw "Additional packages are not automated for '$TemplateName'."
            }

            Push-Location $projectFullPath
            try {
                $gradleWrapper = Join-Path $projectFullPath "gradlew.bat"
                if (Test-Path -LiteralPath $gradleWrapper -PathType Leaf) {
                    Invoke-ExternalCommand -Command $gradleWrapper -Arguments @("dependencies") -FailureMessage "gradlew dependencies failed."
                } else {
                    Invoke-ExternalCommand -Command "gradle" -Arguments @("dependencies") -FailureMessage "gradle dependencies failed."
                }
            }
            finally {
                Pop-Location
            }
            return
        }

        default {
            throw "Unknown install strategy '$Strategy' for template '$TemplateName'."
        }
    }
}
function Invoke-TemplateChecksByStrategy {
    param(
        [Parameter(Mandatory = $true)][string]$Strategy,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [string]$PythonVenv = ".venv",
        [string]$PythonTargetVersion
    )

    $projectFullPath = (Resolve-Path -LiteralPath $ProjectPath).Path
    Add-AuditEntry -Message "check-strategy: $TemplateName -> $Strategy"

    switch ($Strategy) {
        "none" {
            Write-Output "No checks defined for template '$TemplateName'."
            return
        }

        "cmd_smoke" {
            Push-Location $projectFullPath
            try {
                Invoke-ExternalCommand -Command "cmd" -Arguments @("/c", "tool.cmd", "--check") -FailureMessage "CMD smoke check failed."
            }
            finally {
                Pop-Location
            }
            return
        }

        "python_pytest" {
            Push-Location $projectFullPath
            try {
                Invoke-PythonPytest -ProjectPath $projectFullPath -PythonVenv $PythonVenv -PythonTargetVersion $PythonTargetVersion -FailureMessage "Python tests failed."
            }
            finally {
                Pop-Location
            }
            return
        }

        "python_pytest_docker" {
            Push-Location $projectFullPath
            try {
                Invoke-PythonPytest -ProjectPath $projectFullPath -PythonVenv $PythonVenv -PythonTargetVersion $PythonTargetVersion -FailureMessage "Python tests failed."

                if (Get-Command "docker" -ErrorAction SilentlyContinue) {
                    $envFilePath = Join-Path $projectFullPath ".env"
                    $envExamplePath = Join-Path $projectFullPath ".env.example"
                    if (-not (Test-Path -LiteralPath $envFilePath -PathType Leaf) -and (Test-Path -LiteralPath $envExamplePath -PathType Leaf)) {
                        Add-AuditEntry -Message "docker-env-seed: .env from .env.example"
                        Copy-Item -LiteralPath $envExamplePath -Destination $envFilePath -Force
                    }

                    Invoke-ExternalCommand -Command "docker" -Arguments @("compose", "config", "-q") -FailureMessage "docker compose config validation failed."
                } else {
                    $message = "Skipping Docker compose validation because docker is not installed."
                    if ($script:SkipMissingTools) {
                        Write-Warning $message
                        Add-AuditEntry -Message "docker-check-skipped"
                    } else {
                        throw "$message Use -SkipChecksOnMissingTool to skip this check explicitly."
                    }
                }
            }
            finally {
                Pop-Location
            }
            return
        }

        "npm_test" {
            Push-Location $projectFullPath
            try {
                Invoke-ExternalCommand -Command "npm" -Arguments @("test") -FailureMessage "Node tests failed."
            }
            finally {
                Pop-Location
            }
            return
        }

        "ts_npm" {
            Push-Location $projectFullPath
            try {
                Invoke-ExternalCommand -Command "npm" -Arguments @("run", "build") -FailureMessage "TypeScript build failed."
                Invoke-ExternalCommand -Command "npm" -Arguments @("test") -FailureMessage "TypeScript tests failed."
            }
            finally {
                Pop-Location
            }
            return
        }

        "npm_workspace_test" {
            Push-Location $projectFullPath
            try {
                Invoke-ExternalCommand -Command "npm" -Arguments @("run", "test", "-ws", "--if-present") -FailureMessage "Workspace tests failed."
            }
            finally {
                Pop-Location
            }
            return
        }

        "go_test" {
            Push-Location $projectFullPath
            try {
                Invoke-ExternalCommand -Command "go" -Arguments @("test", "./...") -FailureMessage "Go tests failed."
            }
            finally {
                Pop-Location
            }
            return
        }

        "go_cli" {
            Push-Location $projectFullPath
            try {
                Invoke-ExternalCommand -Command "go" -Arguments @("test", "./...") -FailureMessage "Go tests failed."
                Invoke-ExternalCommand -Command "go" -Arguments @("build", "./cmd/app") -FailureMessage "Go CLI build failed."
            }
            finally {
                Pop-Location
            }
            return
        }

        "flutter_test" {
            Push-Location $projectFullPath
            try {
                Invoke-ExternalCommand -Command "flutter" -Arguments @("test") -FailureMessage "Flutter tests failed."
            }
            finally {
                Pop-Location
            }
            return
        }

        "gradle_test" {
            Push-Location $projectFullPath
            try {
                $gradleWrapper = Join-Path $projectFullPath "gradlew.bat"
                if (Test-Path -LiteralPath $gradleWrapper -PathType Leaf) {
                    Invoke-ExternalCommand -Command $gradleWrapper -Arguments @("test") -FailureMessage "Gradle tests failed."
                } else {
                    Invoke-ExternalCommand -Command "gradle" -Arguments @("test") -FailureMessage "Gradle tests failed."
                }
            }
            finally {
                Pop-Location
            }
            return
        }

        "gradle_help" {
            Push-Location $projectFullPath
            try {
                $gradleWrapper = Join-Path $projectFullPath "gradlew.bat"
                if (Test-Path -LiteralPath $gradleWrapper -PathType Leaf) {
                    Invoke-ExternalCommand -Command $gradleWrapper -Arguments @("help") -FailureMessage "Gradle help failed."
                } else {
                    Invoke-ExternalCommand -Command "gradle" -Arguments @("help") -FailureMessage "Gradle help failed."
                }
            }
            finally {
                Pop-Location
            }
            return
        }

        default {
            throw "Unknown check strategy '$Strategy' for template '$TemplateName'."
        }
    }
}

function Copy-ScaffoldDocument {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFileName,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$DestinationFileName,
        [Parameter(Mandatory = $true)]$Tokens
    )

    $sourcePath = Join-Path $script:ScaffoldRoot $SourceFileName
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Missing scaffold source file: $sourcePath"
    }

    $targetPath = Join-Path $ProjectPath $DestinationFileName
    Add-AuditEntry -Message "scaffold-copy: $SourceFileName -> $DestinationFileName"

    if ($script:DryRunMode) {
        Write-Output "[DryRun] Would write $DestinationFileName"
        return
    }

    $content = Get-Content -LiteralPath $sourcePath -Raw
    foreach ($token in $Tokens.Keys) {
        $content = $content -replace [regex]::Escape($token), $Tokens[$token]
    }

    [System.IO.File]::WriteAllText($targetPath, $content, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-PostCreateHook {
    param(
        [string]$HookPath,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$TemplateName
    )

    if ([string]::IsNullOrWhiteSpace($HookPath)) {
        return
    }

    $resolvedHook = $null
    if (Test-Path -LiteralPath $HookPath -PathType Leaf) {
        $resolvedHook = (Resolve-Path -LiteralPath $HookPath).Path
    } else {
        $candidate = Join-Path (Get-Location).Path $HookPath
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $resolvedHook = (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    if ($null -eq $resolvedHook) {
        throw "Post create script not found: $HookPath"
    }

    Add-AuditEntry -Message "post-create-hook: $resolvedHook"

    $extension = [System.IO.Path]::GetExtension($resolvedHook).ToLowerInvariant()
    switch ($extension) {
        ".ps1" {
            $rendered = "& '$resolvedHook' '$ProjectPath' '$TemplateName'"
            Add-AuditEntry -Message "command: $rendered"
            if ($script:DryRunMode) {
                Write-Output "[DryRun] $rendered"
                return
            }

            & $resolvedHook $ProjectPath $TemplateName
            $exitCode = $LASTEXITCODE
            if ($null -ne $exitCode -and $exitCode -ne 0) {
                throw "Post create PowerShell script failed with exit code $exitCode."
            }
            return
        }
        ".cmd" {
            Invoke-ExternalCommand -Command "cmd" -Arguments @("/c", $resolvedHook, $ProjectPath, $TemplateName) -FailureMessage "Post create CMD script failed."
            return
        }
        ".bat" {
            Invoke-ExternalCommand -Command "cmd" -Arguments @("/c", $resolvedHook, $ProjectPath, $TemplateName) -FailureMessage "Post create BAT script failed."
            return
        }
        default {
            Invoke-ExternalCommand -Command $resolvedHook -Arguments @($ProjectPath, $TemplateName) -FailureMessage "Post create hook failed."
            return
        }
    }
}

function Show-DryRunPlan {
    param(
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [Parameter(Mandatory = $true)][string]$TemplatePath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$InstallStrategy,
        [Parameter(Mandatory = $true)][string]$CheckStrategy,
        [string[]]$InstallTools = @(),
        [string[]]$CheckTools = @(),
        [string[]]$Packages = @(),
        [hashtable]$Tokens
    )

    Write-Output "[DryRun] Template: $TemplateName"
    Write-Output "[DryRun] Source:   $TemplatePath"
    Write-Output "[DryRun] Target:   $TargetPath"
    Write-Output "[DryRun] Install strategy: $InstallStrategy"
    Write-Output "[DryRun] Check strategy:   $CheckStrategy"
    Write-Output "[DryRun] Install tools: $(($InstallTools | Sort-Object -Unique) -join ', ')"
    Write-Output "[DryRun] Check tools:   $(($CheckTools | Sort-Object -Unique) -join ', ')"

    if ($Packages.Count -gt 0) {
        Write-Output "[DryRun] Additional packages: $($Packages -join ', ')"
    }

    Write-Output "[DryRun] Token values: project_name='$($Tokens["{{project_name}}"] )', project_slug='$($Tokens["{{project_slug}}"] )', project_module='$($Tokens["{{project_module}}"] )'"

    if ($InstallDeps) {
        Write-Output "[DryRun] Would run install step."
    }
    if ($RunChecks) {
        Write-Output "[DryRun] Would run checks."
    }
    if ($IncludeLicense) {
        Write-Output "[DryRun] Would inject LICENSE ($LicenseType)."
    }
    if ($IncludeContributing) {
        Write-Output "[DryRun] Would inject CONTRIBUTING.md."
    }
    if ($IncludeCodeOfConduct) {
        Write-Output "[DryRun] Would inject CODE_OF_CONDUCT.md."
    }
    if (-not [string]::IsNullOrWhiteSpace($PostCreateScript)) {
        Write-Output "[DryRun] Would run post-create hook: $PostCreateScript"
    }
    if ($InitGit -or $CreateGitHub -or $Push) {
        Write-Output "[DryRun] Would initialize git and optional GitHub remote."
    }
}
$repoRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-TemplateManifest -RepoRoot $repoRoot
$templateConfig = Get-TemplateConfig -Manifest $manifest -TemplateName $Template

$templatePath = Join-Path $repoRoot ("templates\" + $Template)
if (-not (Test-Path -LiteralPath $templatePath -PathType Container)) {
    throw "Template folder not found for '$Template': $templatePath"
}

$identity = Get-ProjectIdentity -ProjectName $Name
$slug = $identity.slug
$module = $identity.module

$targetPath = Join-Path $Destination $Name

$tokens = @{
    "{{project_name}}"   = $Name
    "{{project_slug}}"   = $slug
    "{{project_module}}" = $module
}

$scaffoldTokens = @{
    "{{project_name}}" = $Name
    "{{project_slug}}" = $slug
    "{{project_module}}" = $module
    "{{year}}" = (Get-Date).Year.ToString()
    "{{owner}}" = if ([string]::IsNullOrWhiteSpace($env:GIT_AUTHOR_NAME)) { $env:USERNAME } else { $env:GIT_AUTHOR_NAME }
}

$userPackages = Resolve-UserPackage -TemplateName $Template -SpecFilePath $DependencySpecFile -InlinePackages $AdditionalPackages
$installStrategy = "$($templateConfig.install_strategy)"
$checkStrategy = "$($templateConfig.check_strategy)"
$supportsAdditionalPackages = [bool]$templateConfig.supports_additional_packages
$isPythonModuleTemplate = [bool]$templateConfig.python_module_template

$requiredInstallTools = @()
$requiredCheckTools = @()
if ($templateConfig.ContainsKey("required_tools")) {
    $requiredInstallTools = ConvertTo-StringArray -Value $templateConfig.required_tools.install
    $requiredCheckTools = ConvertTo-StringArray -Value $templateConfig.required_tools.check
}

if (-not $supportsAdditionalPackages -and $userPackages.Count -gt 0) {
    throw "Template '$Template' does not support additional package installs."
}

if ($DryRun) {
    Show-DryRunPlan `
        -TemplateName $Template `
        -TemplatePath $templatePath `
        -TargetPath $targetPath `
        -InstallStrategy $installStrategy `
        -CheckStrategy $checkStrategy `
        -InstallTools $requiredInstallTools `
        -CheckTools $requiredCheckTools `
        -Packages $userPackages `
        -Tokens $tokens
    return
}

$targetCreated = $false

try {
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
        Add-AuditEntry -Message "destination-created: $Destination"
    }

    if (Test-Path -LiteralPath $targetPath) {
        if (-not $Force) {
            throw "Target already exists: $targetPath. Use -Force to overwrite."
        }

        Remove-Item -LiteralPath $targetPath -Recurse -Force -ErrorAction Stop
        Add-AuditEntry -Message "target-removed: $targetPath"
    }

    Copy-Item -LiteralPath $templatePath -Destination $targetPath -Recurse -Force
    $targetCreated = $true
    Add-AuditEntry -Message "template-copied: $Template -> $targetPath"

    Invoke-PythonModulePathAlignment -ProjectPath $targetPath -ModuleName $module -IsPythonModuleTemplate $isPythonModuleTemplate

    if ($installStrategy -in @("python_pyproject", "python_requirements")) {
        Invoke-PythonGitIgnoreUpdate -ProjectPath $targetPath -VenvName $PythonVenvName
    }

    Invoke-TemplateTokenReplacement -ProjectPath $targetPath -Tokens $tokens

    if ($IncludeLicense) {
        $licenseSource = "LICENSE-$LicenseType.txt"
        Copy-ScaffoldDocument -SourceFileName $licenseSource -ProjectPath $targetPath -DestinationFileName "LICENSE" -Tokens $scaffoldTokens
    }
    if ($IncludeContributing) {
        Copy-ScaffoldDocument -SourceFileName "CONTRIBUTING.md" -ProjectPath $targetPath -DestinationFileName "CONTRIBUTING.md" -Tokens $scaffoldTokens
    }
    if ($IncludeCodeOfConduct) {
        Copy-ScaffoldDocument -SourceFileName "CODE_OF_CONDUCT.md" -ProjectPath $targetPath -DestinationFileName "CODE_OF_CONDUCT.md" -Tokens $scaffoldTokens
    }

    if ($InstallDeps) {
        if (Test-ToolsAvailableForPhase -Tools $requiredInstallTools -Phase "install" -TemplateName $Template -ProjectPath $targetPath) {
            Install-TemplateDependenciesByStrategy `
                -Strategy $installStrategy `
                -TemplateName $Template `
                -ProjectPath $targetPath `
                -UserPackages $userPackages `
                -PythonVenv $PythonVenvName `
                -PythonManager $PythonEnvManager `
                -PythonTargetVersion $PythonVersion `
                -ProjectModule $module
        }
    }

    if ($RunChecks) {
        if (Test-ToolsAvailableForPhase -Tools $requiredCheckTools -Phase "check" -TemplateName $Template -ProjectPath $targetPath) {
            Invoke-TemplateChecksByStrategy `
                -Strategy $checkStrategy `
                -TemplateName $Template `
                -ProjectPath $targetPath `
                -PythonVenv $PythonVenvName `
                -PythonTargetVersion $PythonVersion
        }
    }

    Invoke-PostCreateHook -HookPath $PostCreateScript -ProjectPath $targetPath -TemplateName $Template

    if ($InitGit -or $CreateGitHub -or $Push) {
        $initScriptPath = Join-Path $PSScriptRoot "init-repo.ps1"
        if (-not (Test-Path -LiteralPath $initScriptPath -PathType Leaf)) {
            throw "Missing bootstrap script: $initScriptPath"
        }

        $initArgs = @{
            Path                 = $targetPath
            InitialCommitMessage = $InitialCommitMessage
            DefaultBranch        = $DefaultBranch
            Visibility           = $Visibility
        }

        if ($CreateGitHub) { $initArgs.CreateGitHub = $true }
        if ($Push) { $initArgs.Push = $true }
        if (-not [string]::IsNullOrWhiteSpace($GitHubRepo)) { $initArgs.GitHubRepo = $GitHubRepo }

        Add-AuditEntry -Message "init-repo: $initScriptPath"
        & $initScriptPath @initArgs
    }

    Write-AuditFile -ProjectPath $targetPath
    Write-Output "Created template '$Template' at '$targetPath'."
    Write-Output "Audit log written to '$targetPath\scaffold.log'."
}
catch {
    if ($targetCreated -and (Test-Path -LiteralPath $targetPath -PathType Container)) {
        try {
            Write-AuditFile -ProjectPath $targetPath
        }
        catch {
            Write-Warning "Failed to write scaffold audit log: $($_.Exception.Message)"
        }
    }

    throw
}

