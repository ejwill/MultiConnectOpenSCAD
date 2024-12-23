<#
.SYNOPSIS
Processes OpenSCAD files by replacing include statements with their file contents.

.DESCRIPTION
This script processes OpenSCAD files by reading include statements, extracting the referenced file contents,
and appending the contents to the processed file. The processed files are saved in the specified output directory.
This is a work around to MakerWorld not support user libraries 

.PARAMETER path
Specifies the input path to a file or folder containing OpenSCAD files to process.

.PARAMETER outputFolderPath
Specifies the output directory where processed files are saved. Defaults to a folder named `processed` in the working directory.

.EXAMPLE
.\script.ps1 -path "inputFiles"
Processes files in the `inputFiles` folder and saves the results in the `processed` folder.

.EXAMPLE
.\script.ps1 -path "inputFiles" -outputFolderPath "output/processed"
Processes files and saves the results in the `output/processed` folder.

.EXAMPLE
.\script.ps1 -path "inputFiles" -outputFolderPath "C:\OutputFiles"
Processes files and saves the results in `C:\OutputFiles`.

#>

param (
    [Parameter(Mandatory = $true)]
    [string]$path,  # The input path (file or folder)

    [Parameter(Mandatory = $false)]
    [string]$outputFolderPath # Default to "processed" folder
)

# Explanation for `outputFolderPath`:
# - This parameter specifies the directory where processed files will be saved.
# - You can provide an absolute or relative path.
# - If not specified, the script will default to a folder named "processed" in the current directory.
# Example usages:
#   - Use default: Run the script without specifying this parameter.
#   - Specify a relative path: `-outputFolderPath "output/processed"`
#   - Specify an absolute path: `-outputFolderPath "C:\Projects\ProcessedFiles"`

function Get-Includes {
    param (
        [string]$filePath
    )

    $includeArray = @()

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
        [string]$scadFilePath
    )

    $includeData = @()
    $scadDirectory = Split-Path -Path $scadFilePath

    foreach ($includeFile in $includePaths) {
        try {
            # Step 1: Check in the same folder
            $foundFile = Find-FileInSameFolder -scadDirectory $scadDirectory -includeFile $includeFile
            if ($foundFile) {
                $fileContent = Get-Content -Path $foundFile -ErrorAction Stop
                $includeData += $fileContent
                continue
            }

            # Step 2: Check in sibling folders
            $foundFile = Find-FileInSiblingFolders -scadDirectory $scadDirectory -includeFile $includeFile
            if ($foundFile) {
                $fileContent = Get-Content -Path $foundFile -ErrorAction Stop
                $includeData += $fileContent
                continue
            }

            # Step 3: Fallback to repository search
            $foundFile = Find-ClosestFileInRepository -includeFile $includeFile
            if ($foundFile) {
                $fileContent = Get-Content -Path $foundFile.FullName -ErrorAction Stop
                $includeData += $fileContent
                continue
            }

            Write-Warning "No file found for include: $includeFile"

        } catch {
            Write-Warning "Could not read file: $includeFile. $_"
        }
    }

    return $includeData
}

function Find-FileInSameFolder {
    param (
        [string]$scadDirectory,
        [string]$includeFile
    )
    $localFile = Join-Path -Path $scadDirectory -ChildPath $includeFile
    if (Test-Path -Path $localFile) {
        return $localFile
    }
    return $null
}

function Find-FileInSiblingFolders {
    param (
        [string]$scadDirectory,
        [string]$includeFile
    )
    $siblingFolders = Get-ChildItem -Path (Split-Path -Parent $scadDirectory) -Directory
    foreach ($folder in $siblingFolders) {
        $potentialFile = Join-Path -Path $folder.FullName -ChildPath $includeFile
        if (Test-Path -Path $potentialFile) {
            return $potentialFile
        }
    }
    return $null
}

function Find-ClosestFileInRepository {
    param (
        [string]$includeFile
    )
    $fileCandidates = Get-ChildItem -Path "." -Recurse -Filter $includeFile
    if ($fileCandidates.Count -gt 0) {
        return $fileCandidates | Sort-Object -Property { $_.FullName.Split('\').Count } | Select-Object -First 1
    }
    return $null
}

function Remove-IncludesFromFile {
    param (
        [string]$filePath,
        [string[]]$includePaths
    )

    # Check if includePaths is not null or empty before proceeding
    if ($null -eq $includePaths -or $includePaths.Count -eq 0) {
        Write-Warning "No include paths provided for $filePath. Skipping removal of includes."
        return (Get-Content -Path $filePath)  # Return the original file content if no includes
    }

    $normalizedIncludePaths = $includePaths | ForEach-Object { $_.ToLowerInvariant() }

    $lines = Get-Content -Path $filePath
    $filteredLines = $lines | Where-Object {
        if ($_ -match 'include\s+<([^>]+)>') {
            $includePath = $matches[1].ToLowerInvariant()
            $normalizedIncludePaths -notcontains $includePath
        } else {
            $true
        }
    }

    return $filteredLines
}

function Write-ToProcessedFile {
    param (
        [string]$originalFilePath,
        [string[]]$filteredLines,
        [string[]]$includeData,
        [string]$outputFolderPath
    )

    # Ensure the processed folder exists
    Ensure-FolderExists -folderPath $outputFolderPath

    # Determine the output file path
    $outputFilePath = Join-Path -Path $outputFolderPath -ChildPath (Split-Path -Leaf $originalFilePath)

    try {
        # Write filtered content and appended include data to the new file
        Set-Content -Path $outputFilePath -Value $filteredLines
        Add-Content -Path $outputFilePath -Value "`n// === Appended Includes Start ==="
        Add-Content -Path $outputFilePath -Value $includeData
        Add-Content -Path $outputFilePath -Value "// === Appended Includes End ===`n"
        Write-Host "Successfully wrote processed file to $outputFilePath."
    } catch {
        Write-Error "Failed to write processed file: $outputFilePath. $_"
    }
}

function Ensure-FolderExists {
    param (
        [string]$folderPath
    )
    if (-not (Test-Path -Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath | Out-Null
    }
}

function Invoke-ProcessScadFile {
    param (
        [string]$filePath,
        [string]$outputFolderPath
    )

    # If outputFolderPath is not provided, create it relative to the original file's folder
    if (-not $outputFolderPath) {
        $originalDirectory = Split-Path -Parent $filePath
        $outputFolderPath = Join-Path -Path $originalDirectory -ChildPath 'output'
    }

    # Ensure the processed folder exists
    if (-not (Test-Path -Path $outputFolderPath)) {
        New-Item -Path $outputFolderPath -ItemType Directory -Force | Out-Null
        Write-Host "Created processed folder: $outputFolderPath"
    }

    # Extract the file name from the file path
    $fileName = [System.IO.Path]::GetFileName($filePath)

    # Construct the output file path for the processed file
    $outputFilePath = Join-Path -Path $outputFolderPath -ChildPath $fileName

    Write-Host "Processing file: $filePath"

    # Step 1: Extract includes from the SCAD file
    $includeArray = Get-Includes -filePath $filePath
    Write-Host "Found includes in $($filePath): $($includeArray -join ', ')"

    # Step 2: Read content of the included files
    $includeData = Read-IncludeFiles -includePaths $includeArray
    Write-Host "Read include file content for $filePath."

    # Step 3: Write the processed content to the new file
    Write-ToProcessedFile -originalFilePath $filePath -filteredLines (Remove-IncludesFromFile -filePath $filePath -includePaths $includeArray) -includeData $includeData -outputFolderPath $outputFolderPath
}

function Invoke-ProcessScadFilesInFolder {
    param (
        [string]$folderPath,
        [string]$outputFolderPath
    )

    $scadFiles = Get-ChildItem -Path $folderPath -Filter "*.scad" -Recurse
    foreach ($scadFile in $scadFiles) {
        Invoke-ProcessScadFile -filePath $scadFile.FullName -outputFolderPath $outputFolderPath
    }
}

if (Test-Path $path) {
    if (Test-Path $path -PathType Leaf) {
        Invoke-ProcessScadFile -filePath $path -outputFolderPath $outputFolderPath
    } elseif (Test-Path $path -PathType Container) {
        Invoke-ProcessScadFilesInFolder -folderPath $path -outputFolderPath $outputFolderPath
    } else {
        Write-Error "The path is neither a valid file nor a folder: $path"
    }
} else {
    Write-Error "The provided path does not exist: $path"
}
