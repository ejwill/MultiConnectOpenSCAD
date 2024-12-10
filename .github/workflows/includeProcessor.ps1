<#
.SYNOPSIS
Processes OpenSCAD files by replacing include statements with their file contents.

.DESCRIPTION
This script processes OpenSCAD files by reading include statements, extracting the referenced file contents,
and appending the contents to the processed file. The processed files are saved in the specified output directory.
This is a work around to MakerWorld not support user libraries 

.PARAMETER path
Specifies the input path to a file or folder containing OpenSCAD files to process.

.PARAMETER sharedFolderPath
Specifies the directory containing shared include files. Defaults to `Underware/shared/`.

.PARAMETER processedFolderPath
Specifies the output directory where processed files are saved. Defaults to a folder named `processed` in the working directory.

.EXAMPLE
.\script.ps1 -path "inputFiles"
Processes files in the `inputFiles` folder and saves the results in the `processed` folder.

.EXAMPLE
.\script.ps1 -path "inputFiles" -processedFolderPath "output/processed"
Processes files and saves the results in the `output/processed` folder.

.EXAMPLE
.\script.ps1 -path "inputFiles" -processedFolderPath "C:\ProcessedFiles"
Processes files and saves the results in `C:\ProcessedFiles`.

#>

param (
    [Parameter(Mandatory = $true)]
    [string]$path,  # The input path (file or folder)

    [Parameter(Mandatory = $false)]
    [string]$sharedFolderPath = "Underware/shared/",  # Default to "Underware/shared/" if not specified

    [Parameter(Mandatory = $false)]
    [string]$processedFolderPath = "processed"  # Default to "processed" folder
)

# Explanation for `processedFolderPath`:
# - This parameter specifies the directory where processed files will be saved.
# - You can provide an absolute or relative path.
# - If not specified, the script will default to a folder named "processed" in the current directory.
# Example usages:
#   - Use default: Run the script without specifying this parameter.
#   - Specify a relative path: `-processedFolderPath "output/processed"`
#   - Specify an absolute path: `-processedFolderPath "C:\Projects\ProcessedFiles"`

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
        [string]$sharedFolderPath
    )

    $includeData = @()

    foreach ($includeFile in $includePaths) {
        try {
            $filePath = Join-Path -Path $sharedFolderPath -ChildPath $includeFile
            $fileContent = Get-Content -Path $filePath -ErrorAction Stop
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
        [string]$processedFolderPath
    )

    # Determine the output file path
    if (-not (Test-Path -Path $processedFolderPath)) {
        New-Item -ItemType Directory -Path $processedFolderPath | Out-Null
    }

    $outputFilePath = Join-Path -Path $processedFolderPath -ChildPath (Split-Path -Leaf $originalFilePath)

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

function Process-ScadFile {
    param (
        [string]$filePath,
        [string]$sharedFolderPath,
        [string]$processedFolderPath
    )

    # Ensure the processed folder exists
    if (-not (Test-Path -Path $processedFolderPath)) {
        New-Item -Path $processedFolderPath -ItemType Directory | Out-Null
        Write-Host "Created processed folder: $processedFolderPath"
    }

    # Extract the file name from the file path
    $fileName = [System.IO.Path]::GetFileName($filePath)

    # Construct the output file path
    $outputFilePath = Join-Path -Path $processedFolderPath -ChildPath $fileName

    Write-Host "Processing file: $filePath"

    # Step 1: Extract includes from the SCAD file
    $includeArray = Get-Includes -filePath $filePath
    Write-Host "Found includes in $($filePath): $($includeArray -join ', ')"

    # Step 2: Read content of the included files
    $includeData = Read-IncludeFiles -includePaths $includeArray -sharedFolderPath $sharedFolderPath
    Write-Host "Read include file content for $filePath."

    # Step 3: Write the processed content to the new file
    Write-ToProcessedFile -originalFilePath $filePath -outputFilePath $outputFilePath -includeData $includeData
}


function Process-ScadFilesInFolder {
    param (
        [string]$folderPath,
        [string]$sharedFolderPath,
        [string]$processedFolderPath
    )

    $scadFiles = Get-ChildItem -Path $folderPath -Filter "*.scad" -Recurse
    foreach ($scadFile in $scadFiles) {
        Process-ScadFile -filePath $scadFile.FullName -sharedFolderPath $sharedFolderPath -processedFolderPath $processedFolderPath
    }
}

if (Test-Path $path) {
    if (Test-Path $path -PathType Leaf) {
        Process-ScadFile -filePath $path -sharedFolderPath $sharedFolderPath -processedFolderPath $processedFolderPath
    } elseif (Test-Path $path -PathType Container) {
        Process-ScadFilesInFolder -folderPath $path -sharedFolderPath $sharedFolderPath -processedFolderPath $processedFolderPath
    } else {
        Write-Error "The path is neither a valid file nor a folder: $path"
    }
} else {
    Write-Error "The provided path does not exist: $path"
}
