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

    [switch]$Push
)

$ErrorActionPreference = "Stop"

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Invoke-CommandChecked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }
}

function Install-TemplateDependencies {
    param(
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [string[]]$UserPackages = @(),
        [string]$PythonVenv = ".venv",
        [string]$PythonManager = "auto",
        [string]$PythonTargetVersion
    )

    $projectFullPath = (Resolve-Path -LiteralPath $ProjectPath).Path

    switch ($TemplateName) {
        "python-tool" {
            Push-Location $projectFullPath
            try {
                $uvAvailable = Get-Command "uv" -ErrorAction SilentlyContinue
                $useUv = $false
                switch ($PythonManager) {
                    "uv" {
                        if (-not $uvAvailable) {
                            throw "PythonEnvManager is 'uv' but 'uv' command is not available."
                        }
                        $useUv = $true
                    }
                    "venv" {
                        $useUv = $false
                    }
                    default {
                        $useUv = [bool]$uvAvailable
                    }
                }

                if ($useUv) {
                    Write-Output "Installing Python deps with uv..."
                    $uvVenvArgs = @("venv", $PythonVenv)
                    if (-not [string]::IsNullOrWhiteSpace($PythonTargetVersion)) {
                        $uvVenvArgs += @("--python", $PythonTargetVersion)
                    }
                    Invoke-CommandChecked -Command "uv" -Arguments $uvVenvArgs -FailureMessage "uv venv failed."
                    $uvPython = Join-Path $projectFullPath ($PythonVenv + "\Scripts\python.exe")
                    if (-not (Test-Path -Path $uvPython -PathType Leaf)) {
                        throw "Virtual environment python not found at $uvPython"
                    }

                    Invoke-CommandChecked -Command "uv" -Arguments @("pip", "install", "--python", $uvPython, "-e", ".[dev]") -FailureMessage "uv pip install failed."
                    if ($UserPackages.Count -gt 0) {
                        Write-Output "Installing extra Python packages..."
                        Invoke-CommandChecked -Command "uv" -Arguments (@("pip", "install", "--python", $uvPython) + $UserPackages) -FailureMessage "uv pip install extra packages failed."
                    }
                    return
                }

                $pythonAvailable = Get-Command "python" -ErrorAction SilentlyContinue
                $pyAvailable = Get-Command "py" -ErrorAction SilentlyContinue
                if (-not $pythonAvailable -and -not $pyAvailable) {
                    throw "Neither 'uv', 'python', nor 'py' is available for Python dependency install."
                }

                Write-Output "Installing Python deps with venv + pip..."
                if (-not [string]::IsNullOrWhiteSpace($PythonTargetVersion) -and $pyAvailable) {
                    Invoke-CommandChecked -Command "py" -Arguments @("-$PythonTargetVersion", "-m", "venv", $PythonVenv) -FailureMessage "py -$PythonTargetVersion -m venv failed."
                } elseif ($pythonAvailable) {
                    Invoke-CommandChecked -Command "python" -Arguments @("-m", "venv", $PythonVenv) -FailureMessage "python -m venv failed."
                } else {
                    Invoke-CommandChecked -Command "py" -Arguments @("-3", "-m", "venv", $PythonVenv) -FailureMessage "py -3 -m venv failed."
                }

                $venvPython = Join-Path $projectFullPath ($PythonVenv + "\Scripts\python.exe")
                if (-not (Test-Path -Path $venvPython -PathType Leaf)) {
                    throw "Virtual environment python not found at $venvPython"
                }

                Invoke-CommandChecked -Command $venvPython -Arguments @("-m", "pip", "install", "--upgrade", "pip") -FailureMessage "pip upgrade failed."
                Invoke-CommandChecked -Command $venvPython -Arguments @("-m", "pip", "install", "-e", ".[dev]") -FailureMessage "pip install failed."
                if ($UserPackages.Count -gt 0) {
                    Write-Output "Installing extra Python packages..."
                    Invoke-CommandChecked -Command $venvPython -Arguments (@("-m", "pip", "install") + $UserPackages) -FailureMessage "pip install extra packages failed."
                }
            }
            finally {
                Pop-Location
            }
        }
        "node-api" {
            Require-Command -Name "npm"
            Push-Location $projectFullPath
            try {
                Write-Output "Installing Node deps with npm..."
                Invoke-CommandChecked -Command "npm" -Arguments @("install") -FailureMessage "npm install failed."
                if ($UserPackages.Count -gt 0) {
                    Write-Output "Installing extra Node packages..."
                    Invoke-CommandChecked -Command "npm" -Arguments (@("install") + $UserPackages) -FailureMessage "npm install extra packages failed."
                }
            }
            finally {
                Pop-Location
            }
        }
        "go-service" {
            Require-Command -Name "go"
            Push-Location $projectFullPath
            try {
                Write-Output "Resolving Go modules..."
                Invoke-CommandChecked -Command "go" -Arguments @("mod", "tidy") -FailureMessage "go mod tidy failed."
                foreach ($moduleSpec in $UserPackages) {
                    Invoke-CommandChecked -Command "go" -Arguments @("get", $moduleSpec) -FailureMessage "go get failed for '$moduleSpec'."
                }
                if ($UserPackages.Count -gt 0) {
                    Invoke-CommandChecked -Command "go" -Arguments @("mod", "tidy") -FailureMessage "go mod tidy failed after extra module installs."
                }
            }
            finally {
                Pop-Location
            }
        }
        "flutter-app" {
            Require-Command -Name "flutter"
            Push-Location $projectFullPath
            try {
                Write-Output "Fetching Flutter packages..."
                Invoke-CommandChecked -Command "flutter" -Arguments @("pub", "get") -FailureMessage "flutter pub get failed."
                foreach ($flutterSpec in $UserPackages) {
                    Invoke-CommandChecked -Command "flutter" -Arguments @("pub", "add", $flutterSpec) -FailureMessage "flutter pub add failed for '$flutterSpec'."
                }
            }
            finally {
                Pop-Location
            }
        }
        "kotlin-android" {
            if ($UserPackages.Count -gt 0) {
                throw "Additional package install is not yet automated for kotlin-android template."
            }
            $gradleWrapper = Join-Path $projectFullPath "gradlew.bat"
            if (Test-Path -Path $gradleWrapper -PathType Leaf) {
                Push-Location $projectFullPath
                try {
                    Write-Output "Resolving Android dependencies..."
                    Invoke-CommandChecked -Command $gradleWrapper -Arguments @("dependencies") -FailureMessage "gradlew dependencies failed."
                }
                finally {
                    Pop-Location
                }
            } else {
                Write-Warning "Skipping dependency install for kotlin-android: no gradlew.bat in template."
            }
        }
        default {
            if ($UserPackages.Count -gt 0) {
                throw "Additional package install is not defined for template '$TemplateName'."
            }
            Write-Output "No dependency install step defined for template '$TemplateName'."
        }
    }
}

function Run-TemplateChecks {
    param(
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [string]$PythonVenv = ".venv",
        [string]$PythonTargetVersion
    )

    $projectFullPath = (Resolve-Path -LiteralPath $ProjectPath).Path

    switch ($TemplateName) {
        "python-tool" {
            Push-Location $projectFullPath
            try {
                $venvPython = Join-Path $projectFullPath ($PythonVenv + "\Scripts\python.exe")
                if (Test-Path -Path $venvPython -PathType Leaf) {
                    Write-Output "Running Python checks with virtual environment..."
                    Invoke-CommandChecked -Command $venvPython -Arguments @("-m", "pytest", "-q") -FailureMessage "Python tests failed."
                    return
                }

                $pythonAvailable = Get-Command "python" -ErrorAction SilentlyContinue
                $pyAvailable = Get-Command "py" -ErrorAction SilentlyContinue
                if ($pythonAvailable) {
                    Write-Output "Running Python checks with system python..."
                    Invoke-CommandChecked -Command "python" -Arguments @("-m", "pytest", "-q") -FailureMessage "Python tests failed."
                } elseif ($pyAvailable) {
                    Write-Output "Running Python checks with py launcher..."
                    if (-not [string]::IsNullOrWhiteSpace($PythonTargetVersion)) {
                        Invoke-CommandChecked -Command "py" -Arguments @("-$PythonTargetVersion", "-m", "pytest", "-q") -FailureMessage "Python tests failed."
                    } else {
                        Invoke-CommandChecked -Command "py" -Arguments @("-3", "-m", "pytest", "-q") -FailureMessage "Python tests failed."
                    }
                } else {
                    throw "No Python interpreter available for checks."
                }
            }
            finally {
                Pop-Location
            }
        }
        "node-api" {
            Require-Command -Name "npm"
            Push-Location $projectFullPath
            try {
                Write-Output "Running Node checks..."
                Invoke-CommandChecked -Command "npm" -Arguments @("test") -FailureMessage "Node tests failed."
            }
            finally {
                Pop-Location
            }
        }
        "go-service" {
            Require-Command -Name "go"
            Push-Location $projectFullPath
            try {
                Write-Output "Running Go checks..."
                Invoke-CommandChecked -Command "go" -Arguments @("test", "./...") -FailureMessage "Go tests failed."
            }
            finally {
                Pop-Location
            }
        }
        "flutter-app" {
            Require-Command -Name "flutter"
            Push-Location $projectFullPath
            try {
                Write-Output "Running Flutter checks..."
                Invoke-CommandChecked -Command "flutter" -Arguments @("test") -FailureMessage "Flutter tests failed."
            }
            finally {
                Pop-Location
            }
        }
        "kotlin-android" {
            $gradleWrapper = Join-Path $projectFullPath "gradlew.bat"
            if (Test-Path -Path $gradleWrapper -PathType Leaf) {
                Push-Location $projectFullPath
                try {
                    Write-Output "Running Kotlin/Android checks..."
                    Invoke-CommandChecked -Command $gradleWrapper -Arguments @("test") -FailureMessage "Gradle tests failed."
                }
                finally {
                    Pop-Location
                }
            } else {
                Write-Warning "Skipping checks for kotlin-android: no gradlew.bat in template."
            }
        }
        default {
            Write-Output "No checks defined for template '$TemplateName'."
        }
    }
}

function Resolve-UserPackages {
    param(
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$SpecFilePath,
        [string[]]$InlinePackages = @()
    )

    $packages = @()
    if (-not [string]::IsNullOrWhiteSpace($SpecFilePath)) {
        $resolvedSpecPath = (Resolve-Path -LiteralPath $SpecFilePath).Path
        $spec = Get-Content -Path $resolvedSpecPath -Raw | ConvertFrom-Json -AsHashtable

        if ($null -eq $spec) {
            throw "Dependency spec file is empty or invalid JSON: $resolvedSpecPath"
        }

        if ($spec.ContainsKey($TemplateName)) {
            $entry = $spec[$TemplateName]
            if ($entry -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($entry)) {
                    $packages += $entry
                }
            } elseif ($entry -is [System.Collections.IEnumerable]) {
                foreach ($item in $entry) {
                    $s = "$item"
                    if (-not [string]::IsNullOrWhiteSpace($s)) {
                        $packages += $s
                    }
                }
            } elseif ($null -ne $entry) {
                throw "Dependency spec entry for '$TemplateName' must be a string or array of strings."
            }
        }
    }

    foreach ($pkg in $InlinePackages) {
        if (-not [string]::IsNullOrWhiteSpace($pkg)) {
            $packages += $pkg
        }
    }

    if ($packages.Count -eq 0) {
        return @()
    }

    return @($packages | Select-Object -Unique)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$templatePath = Join-Path $repoRoot ("templates\" + $Template)

if (-not (Test-Path -Path $templatePath -PathType Container)) {
    throw "Template not found: $Template"
}

if (-not (Test-Path -Path $Destination -PathType Container)) {
    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
}

$targetPath = Join-Path $Destination $Name
if (Test-Path -Path $targetPath) {
    if (-not $Force) {
        throw "Target already exists: $targetPath. Use -Force to overwrite."
    }
    Remove-Item -Path $targetPath -Recurse -Force -ErrorAction Stop
}

Copy-Item -Path $templatePath -Destination $targetPath -Recurse -Force

$slug = ($Name.ToLower() -replace "[^a-z0-9]+", "-").Trim("-")
$module = ($Name.ToLower() -replace "[^a-z0-9]+", "_").Trim("_")
if ([string]::IsNullOrWhiteSpace($module)) {
    $module = "app"
}
if ($module -match "^[0-9]") {
    $module = "app_$module"
}

if ($Template -eq "python-tool") {
    $defaultPackagePath = Join-Path $targetPath "src\app"
    $modulePackagePath = Join-Path $targetPath ("src\" + $module)
    if ($module -ne "app" -and (Test-Path -Path $defaultPackagePath -PathType Container)) {
        if (Test-Path -Path $modulePackagePath -PathType Container) {
            Remove-Item -Path $modulePackagePath -Recurse -Force -ErrorAction Stop
        }
        Copy-Item -Path $defaultPackagePath -Destination $modulePackagePath -Recurse -Force
        Remove-Item -Path $defaultPackagePath -Recurse -Force -ErrorAction Stop
    }

    $pythonGitignorePath = Join-Path $targetPath ".gitignore"
    if (Test-Path -Path $pythonGitignorePath -PathType Leaf) {
        $venvIgnoreEntry = $PythonVenvName.Replace("\", "/").Trim()
        $venvIgnoreEntry = $venvIgnoreEntry -replace "^\./", ""
        if (-not [string]::IsNullOrWhiteSpace($venvIgnoreEntry)) {
            if (-not $venvIgnoreEntry.EndsWith("/")) {
                $venvIgnoreEntry += "/"
            }

            $ignoreLines = Get-Content -Path $pythonGitignorePath
            if (-not ($ignoreLines -contains $venvIgnoreEntry)) {
                Add-Content -Path $pythonGitignorePath -Value $venvIgnoreEntry
            }
        }
    }
}

$tokens = @{
    "{{project_name}}"   = $Name
    "{{project_slug}}"   = $slug
    "{{project_module}}" = $module
}

$textExtensions = @(
    ".md", ".txt", ".toml", ".json", ".yaml", ".yml",
    ".ps1", ".psm1", ".go", ".mod", ".sum", ".js", ".mjs", ".cjs",
    ".py", ".dart", ".kt", ".kts", ".html", ".css",
    ".env", ".gradle", ".xml"
)
$textNames = @(".gitignore", ".env.example", "Makefile")

Get-ChildItem -Path $targetPath -Recurse -File | ForEach-Object {
    $extension = $_.Extension.ToLower()
    $name = $_.Name
    $isText = ($textExtensions -contains $extension) -or ($textNames -contains $name)
    if (-not $isText) {
        return
    }

    $content = Get-Content -Path $_.FullName -Raw
    $updated = $content

    foreach ($token in $tokens.Keys) {
        $updated = $updated -replace [regex]::Escape($token), $tokens[$token]
    }

    if ($updated -ne $content) {
        Set-Content -Path $_.FullName -Value $updated
    }
}

if ($InstallDeps) {
    $userPackages = Resolve-UserPackages -TemplateName $Template -SpecFilePath $DependencySpecFile -InlinePackages $AdditionalPackages
    Install-TemplateDependencies `
        -TemplateName $Template `
        -ProjectPath $targetPath `
        -UserPackages $userPackages `
        -PythonVenv $PythonVenvName `
        -PythonManager $PythonEnvManager `
        -PythonTargetVersion $PythonVersion
}

if ($RunChecks) {
    Run-TemplateChecks `
        -TemplateName $Template `
        -ProjectPath $targetPath `
        -PythonVenv $PythonVenvName `
        -PythonTargetVersion $PythonVersion
}

if ($InitGit -or $CreateGitHub -or $Push) {
    $initScriptPath = Join-Path $PSScriptRoot "init-repo.ps1"
    if (-not (Test-Path -Path $initScriptPath -PathType Leaf)) {
        throw "Missing bootstrap script: $initScriptPath"
    }

    $initArgs = @{
        Path                 = $targetPath
        InitialCommitMessage = $InitialCommitMessage
        DefaultBranch        = $DefaultBranch
        Visibility           = $Visibility
    }

    if ($CreateGitHub) {
        $initArgs.CreateGitHub = $true
    }
    if ($Push) {
        $initArgs.Push = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($GitHubRepo)) {
        $initArgs.GitHubRepo = $GitHubRepo
    }

    & $initScriptPath @initArgs
}

Write-Output "Created template '$Template' at '$targetPath'."
