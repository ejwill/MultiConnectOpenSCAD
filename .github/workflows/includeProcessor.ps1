param (
    [Parameter(Mandatory = $true)]
    [string]$path,  # The input path (file or folder)

    [Parameter(Mandatory = $false)]
    [string]$sharedFolderPath = "Underware/shared/"  # Default to "Underware/shared/" if not specified
)

# Function to extract include statements from a SCAD file
function Get-Includes {
    param (
        [string]$filePath
    )

    $includeArray = @()

    # Read the file line by line and extract include statements
    Get-Content -Path $filePath | ForEach-Object {
        if ($_ -match 'include\s+<([^>]+)>') {
            $includePath = $matches[1]
            if ($includePath -notlike "*BOSL2*") {
                $includeArray += $includePath
            }
        }
    }

    return $includeArray
}

# Function to read the content of include files
function Read-IncludeFiles {
    param (
        [string[]]$includePaths,
        [string]$sharedFolderPath
    )

    $includeData = @()

    foreach ($includeFile in $includePaths) {
        try {
            # Join shared folder path and include file name
            $filePath = Join-Path -Path $sharedFolderPath -ChildPath $includeFile
            $fileContent = Get-Content -Path $filePath -ErrorAction Stop
            $includeData += $fileContent
        } catch {
            Write-Warning "Could not read file: $includeFile. $_"
        }
    }

    return $includeData
}

# Function to remove include statements from the SCAD file
function Remove-IncludesFromFile {
    param (
        [string]$filePath,
        [string[]]$includePaths
    )

    # Normalize include paths to avoid case sensitivity issues
    $normalizedIncludePaths = $includePaths | ForEach-Object { $_.ToLowerInvariant() }

    # Filter out include lines matching the include paths
    $lines = Get-Content -Path $filePath
    $filteredLines = $lines | Where-Object {
        if ($_ -match 'include\s+<([^>]+)>') {
            $includePath = $matches[1].ToLowerInvariant()
            $normalizedIncludePaths -notcontains $includePath
        } else {
            $true  # Keep non-include lines
        }
    }

    # Overwrite the SCAD file with filtered content
    Set-Content -Path $filePath -Value $filteredLines
}

# Function to append include data to the SCAD file
function Append-IncludeData {
    param (
        [string]$filePath,
        [string[]]$includeData
    )

    try {
        Add-Content -Path $filePath -Value "`n// Appended Includes Start"
        Add-Content -Path $filePath -Value $includeData
        Add-Content -Path $filePath -Value "// Appended Includes End`n"
        Write-Host "Successfully appended included file content to $filePath."
    } catch {
        Write-Error "Failed to append content to the file: $filePath. $_"
    }
}

# Function to process a single SCAD file
function Process-ScadFile {
    param (
        [string]$filePath,
        [string]$sharedFolderPath
    )

    Write-Host "Processing file: $filePath"

    $includeArray = Get-Includes -filePath $filePath
    Write-Host "Found includes in $filePath: $($includeArray -join ', ')"

    $includeData = Read-IncludeFiles -includePaths $includeArray -sharedFolderPath $sharedFolderPath
    Write-Host "Read include file content for $filePath."

    Remove-IncludesFromFile -filePath $filePath -includePaths $includeArray
    Write-Host "Removed includes from $filePath."

    Append-IncludeData -filePath $filePath -includeData $includeData
    Write-Host "Appended include data to $filePath."
}

# Function to process all SCAD files in a folder
function Process-ScadFilesInFolder {
    param (
        [string]$folderPath,
        [string]$sharedFolderPath
    )

    $scadFiles = Get-ChildItem -Path $folderPath -Filter "*.scad" -Recurse
    foreach ($scadFile in $scadFiles) {
        Process-ScadFile -filePath $scadFile.FullName -sharedFolderPath $sharedFolderPath
    }
}

# Main execution block
if (Test-Path $path) {
    if (Test-Path $path -PathType Leaf) {
        Process-ScadFile -filePath $path -sharedFolderPath $sharedFolderPath
    } elseif (Test-Path $path -PathType Container) {
        Process-ScadFilesInFolder -folderPath $path -sharedFolderPath $sharedFolderPath
    } else {
        Write-Error "The path is neither a valid file nor a folder: $path"
    }
} else {
    Write-Error "The provided path does not exist: $path"
}
