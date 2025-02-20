param (
    [Parameter(Mandatory = $true)]
    [string[]]$libraryFilePaths  # Array of SCAD library file paths
)

# Check if running in GitHub Actions
$isGitHubActions = $env:GITHUB_ACTIONS -eq 'true'

# Initialize a hashset to store SCAD files to search in
$scadFiles = @()

# Initialize a hash table to store referencing files per library
$referencingFilesMap = @{}

foreach ($libraryFilePath in $libraryFilePaths) {
    # Get the library file object
    $libraryFile = Get-Item -Path $libraryFilePath

    # Get parent and grandparent directories
    $parentDirectory = $libraryFile.Directory
    $grandParentDirectory = if ($parentDirectory) { $parentDirectory.Parent } else { $null }

    # Add SCAD files from parent directory (excluding the library file)
    $scadFiles += Get-ChildItem -Path $parentDirectory.FullName -Filter "*.scad" -Recurse |
                  Where-Object { $_.FullName -ne $libraryFile.FullName } |
                  Select-Object -ExpandProperty FullName

    # Add SCAD files from grandparent directory (excluding parent directory)
    if ($grandParentDirectory) {
        $scadFiles += Get-ChildItem -Path $grandParentDirectory.FullName -Filter "*.scad" -Recurse |
                      Where-Object { $_.FullName -notlike "$parentDirectory\*" } |
                      Select-Object -ExpandProperty FullName
    }

    # Regex pattern to detect "include" or "use" statements referencing the library file
    $regexPattern = "include\s*<[^>]*$($libraryFile.Name)>|use\s*<[^>]*$($libraryFile.Name)>"

    # Initialize an array to store referencing files for this library
    $referencingFilesMap[$libraryFile.FullName] = @()

    # Search for include and use statements
    foreach ($filePath in $scadFiles) {
        $fileContent = Get-Content -Path $filePath -Raw
        if ($fileContent -match $regexPattern) {
            $referencingFilesMap[$libraryFile.FullName] += $filePath
        }
    }
}

# Output results
foreach ($libraryFilePath in $libraryFilePaths) {
    $libraryFile = Get-Item -Path $libraryFilePath
    $referencingFiles = $referencingFilesMap[$libraryFile.FullName]

    if ($referencingFiles.Count -gt 0) {
        Write-Host "The following files reference the library file '$($libraryFile.Name)':"
        foreach ($file in $referencingFiles) {
            Write-Host $file
        }
    } else {
        Write-Host "No files reference the library file '$($libraryFile.Name)'."
    }

    # Set output for GitHub Actions
    if ($isGitHubActions) {
        $referencingFilesString = $referencingFiles -join ","
        Write-Output "::set-output name=referencing_files::$referencingFilesString"
    }
}