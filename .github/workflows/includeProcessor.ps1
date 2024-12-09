param (
    [Parameter(Mandatory = $true)]
    [string]$path,  # The input path (file or folder)

    [Parameter(Mandatory = $false)]
    [string]$sharedFolderPath = "Underware/shared/"  # Default to "Underware/shared/" if not specified
)

function Get-Includes {
    param (
        [string]$filePath
    )

    $includeArray = @()

    # Read the file line by line and extract includes
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

function Read-IncludeFiles {
    param (
        [string[]]$includePaths,
        [string]$sharedFolderPath
    )

    $includeData = @()

    foreach ($includeFile in $includePaths) {
        try {
            # Fix the path concatenation using forward slashes for Linux compatibility
            $fileContent = Get-Content -Path (Join-Path $sharedFolderPath $includeFile) -ErrorAction Stop
            $includeData += $fileContent
        } catch {
            Write-Warning "Could not read file: $includeFile. $_"
        }
    }

    return $includeData
}

function Remove-IncludesFromFile {
    param (
        [string]$filePath,
        [string[]]$includePaths
    )

    # Normalize paths in $includePaths to avoid case sensitivity issues
    $normalizedIncludePaths = $includePaths | ForEach-Object { $_.ToLowerInvariant() }

    # Read all lines from the SCAD file
    $lines = Get-Content -Path $filePath

    # Filter out lines that match the normalized include paths
    $filteredLines = $lines | Where-Object {
        # Match include lines
        if ($_ -match 'include\s+<([^>]+)>') {
            $includePath = $matches[1].ToLowerInvariant()
            # Exclude lines that match any normalized path
            $normalizedIncludePaths -notcontains $includePath
        } else {
            $true  # Keep non-include lines
        }
    }

    # Overwrite the SCAD file with filtered content
    Set-Content -Path $filePath -Value $filteredLines
}

function Append-IncludeData {
    param (
        [string]$filePath,
        [string[]]$includeData
    )

    try {
        # Write a separator line
        Add-Content -Path $filePath -Value "`n// Appended Includes Start"

        # Append each item in includeData
        foreach ($fileContent in $includeData) {
            Add-Content -Path $filePath -Value $fileContent
        }

        # Write a closing separator
        Add-Content -Path $filePath -Value "// Appended Includes End`n"
        Write-Host "Successfully appended included file content to $filePath."
    } catch {
        Write-Error "Failed to append content to the file: $filePath. $_"
    }
}

function Process-ScadFile {
    param (
        [string]$filePath,
        [string]$sharedFolderPath
    )

    Write-Host "Processing file: $filePath"

    # Step 1: Extract includes from the SCAD file
    $includeArray = Get-Includes -filePath $filePath
    Write-Host "Found includes in $filePath: $includeArray"

    # Step 2: Read content of the included files
    $includeData = Read-IncludeFiles -includePaths $includeArray -sharedFolderPath $sharedFolderPath
    Write-Host "Read include file content for $filePath."

    # Step 3: Remove the includes from the SCAD file
    Remove-IncludesFromFile -filePath $filePath -includePaths $includeArray
    Write-Host "Removed includes from $filePath."

    # Step 4: Append the include data to the SCAD file
    Append-IncludeData -filePath $filePath -includeData $includeData
    Write-Host "Appended include data to $filePath."
}

function Process-ScadFilesInFolder {
    param (
        [string]$folderPath,
        [string]$sharedFolderPath
    )

    # Get all SCAD files in the folder
    $scadFiles = Get-ChildItem -Path $folderPath -Filter "*.scad" -Recurse

    foreach ($scadFile in $scadFiles) {
        Process-ScadFile -filePath $scadFile.FullName -sharedFolderPath $sharedFolderPath
    }
}

# Check if the provided path is a file or a folder
if (Test-Path $path) {
    if (Test-Path $path -PathType Leaf) {
        # It's a file, process it
        Process-ScadFile -filePath $path -sharedFolderPath $sharedFolderPath
    } elseif (Test-Path $path -PathType Container) {
        # It's a folder, process all SCAD files in the folder
        Process-ScadFilesInFolder -folderPath $path -sharedFolderPath $sharedFolderPath
    } else {
        Write-Error "The path is neither a valid file nor a folder: $path"
    }
} else {
    Write-Error "The provided path does not exist: $path"
}
