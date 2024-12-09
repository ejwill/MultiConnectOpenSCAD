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

# may need to check includes for includes so a recursive loop
function Read-IncludeFiles {
    param (
        [string[]]$includePaths
    )

    $includeData = @()

    foreach ($includeFile in $includePaths) {
        try {
            $fileContent = Get-Content -Path $includeFile -ErrorAction Stop
            $includeData += $fileContent
        } catch {
            Write-Warning "Could not read file: $includeFile. $_"
        }
    }

    return $includeData
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

# Step 3: Append include data to the original file
Append-IncludeData -filePath $scadFilePath -includeData $includeData
