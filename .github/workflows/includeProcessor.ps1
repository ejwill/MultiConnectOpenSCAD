param (
    [Parameter(Mandatory = $true)]
    [string]$scadFilePath
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
        [string[]]$includePaths
    )

    $includeData = @()

    foreach ($includeFile in $includePaths) {
        try {
            # Make sure to use forward slashes for Linux compatibility
            $fileContent = Get-Content -Path ("Underware/" + $includeFile) -ErrorAction Stop
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

# Main Script Logic
Write-Host "Processing file: $scadFilePath"

# Step 1: Extract includes
$includeArray = Get-Includes -filePath $scadFilePath
Write-Host "Found includes:" $includeArray

# Step 2: Read include files
$includeData = Read-IncludeFiles -includePaths $includeArray
Write-Host "Read include file content."

# Step 3: Remove include lines from the original SCAD file
Remove-IncludesFromFile -filePath $scadFilePath -includePaths $includeArray
Write-Host "Removed include lines from $scadFilePath."

# Step 4: Append include data to the original SCAD file
Append-IncludeData -filePath $scadFilePath -includeData $includeData
