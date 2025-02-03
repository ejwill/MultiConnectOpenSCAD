# Function to extract modules from a .scad file
function Get-ModulesFromFile {
    param (
        [string]$filePath
    )

    $modules = @{}
    $currentModule = $null
    $currentContent = @()

    foreach ($line in Get-Content -Path $filePath) {
        if ($line -match 'module\s+(\w+)\s*\(') {
            if ($currentModule) {
                $modules[$currentModule] = $currentContent -join "`n"
            }
            $currentModule = $matches[1]
            $currentContent = @($line)
        } elseif ($currentModule) {
            $currentContent += $line
        }
    }

    if ($currentModule) {
        $modules[$currentModule] = $currentContent -join "`n"
    }

    return $modules
}

# Function to compare modules across files
function Compare-Modules {
    param (
        [string[]]$filePaths
    )

    $allModules = @{}

    foreach ($filePath in $filePaths) {
        $modules = Get-ModulesFromFile -filePath $filePath
        foreach ($moduleName in $modules.Keys) {
            if (-not $allModules.ContainsKey($moduleName)) {
                $allModules[$moduleName] = @{}
            }
            $allModules[$moduleName][$filePath] = $modules[$moduleName]
        }
    }

    $duplicateModules = @{}

    foreach ($moduleName in $allModules.Keys) {
        $moduleContents = $allModules[$moduleName].Values | Sort-Object -Unique
        if ($moduleContents.Count -gt 1) {
            $duplicateModules[$moduleName] = $allModules[$moduleName]
        }
    }

    return $duplicateModules
}

# Get all .scad files in the current directory and subdirectories
$scadFiles = Get-ChildItem -Path . -Filter "*.scad" -Recurse | Select-Object -ExpandProperty FullName

# Compare modules across .scad files
$duplicateModules = Compare-Modules -filePaths $scadFiles

# Output duplicate modules
foreach ($moduleName in $duplicateModules.Keys) {
    Write-Host "Duplicate module: $moduleName"
    foreach ($filePath in $duplicateModules[$moduleName].Keys) {
        Write-Host "  Found in: $filePath"
    }
}