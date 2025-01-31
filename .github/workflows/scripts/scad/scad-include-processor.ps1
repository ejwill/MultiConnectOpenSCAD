param (
    [Parameter(Mandatory = $true)]
    [string]$path,  # The input path (file or folder)

    [Parameter(Mandatory = $false)]
    [string]$outputFolderPath # Default to "output" folder in the same directory as the input file
)

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

    Write-Host "Processing file: $filePath"

    # Read the file content and put it in a Scadfile object
    $fileContent = Get-Content -Path $filePath -Raw
    # $scadFile = [Scadfile]::new($filePath, $fileContent)
    $scadFile = New-Object ScadFile -ArgumentList $filePath, $fileContent

    if (-not $scadFile) {
        Write-Error "Failed to create ScadFile object for file: $filePath"
        return
    }

    # Get the include names from the file content
    $scadFile.Includes = Get-Includes-From-ScadFile -scadFile $scadFile

    # Read the content of each include and put it in an Include object
    $includeFiles = Read-IncludeFiles -scadFile $scadFile

    # Write the new content to the file
    $newScadFile = New-ScadFile -scadFile $scadFile -includeFiles $includeFiles

    # Write the new content to a new file in the output folder
    Publish-ScadFile-To-Output -scadFile $newScadFile -outputFolderPath $outputFolderPath

    Write-Host "Finished Processing file: $scadFile.Name"
    
}

function Publish-ScadFile-To-Output {
    param (
        [ScadFile]$scadFile,
        [string]$outputFolderPath
    )

    $outputFilePath = Join-Path -Path $OutputFolderPath -ChildPath (Split-Path -Leaf $scadFile.Path)
    Write-Host "Publishing file to: $outputFilePath"

    # Create the output folder if it does not exist
    Test-FolderExists -folderPath $outputFolderPath

    # Write the new content to the output file
    Set-Content -Path $outputFilePath -Value $scadFile.Content -Force
    
}

function New-ScadFile {
    param (
        [ScadFile]$scadFile,
        [Include[]]$includeFiles
    )

    $newContent = $scadFile.Content

    # Remove the include line from the content of the ScadFile where the include was found only if the include has content
    foreach ($include in $includeFiles) {
        if ($include.Content) {
            # $newContent = $newContent -replace "include\s*<${include.Name}>", ""
            $pattern = "include\s+<($($include.Name -join '|'))>\s*(\r?\n|\r)?"

            # Remove matches while preserving line endings
            $newContent = $newContent -replace $pattern, ''

            # Add the content of the include to the new content at the end of the file start with a new line and a comment line with the include name for reference 
            $newContent += "`n// Include: $($include.Name)"
            $newContent += "`n$($include.Content)"
        }
    }

    $scadFile.Content = $newContent
    $scadFile.IsProcessed = $true

    return $scadFile
}

function Read-IncludeFiles {
    param (
        [ScadFile]$scadFile
    )

    $scadDirectory = Split-Path -Path $scadFile.Path

    $includeArrary = @()

    foreach ($includeName in $scadFile.Includes) {
        try {
            $foundInclude = Find-Include-File -scadDirectory $scadDirectory -includeFileName $includeName

            # check that $foundInclude is not null and is and Include object
            if ($foundInclude -and $foundInclude -is [Include]) {
                $includeArrary += $foundInclude
            }
        } catch {
            Write-Warning "Could not read file: $includeName. $_"
        }
    }

    return $includeArrary
}

function Find-Include-File {
    param (
        [Parameter(Mandatory = $true)]
        [string]$scadDirectory,

        [Parameter(Mandatory = $true)]
        [string]$includeFileName
    )

    # Define the parent directory
    $parentDirectory = Split-Path -Parent $scadDirectory

    # Define search locations
    $searchLocations = @(
        # Same folder as the file
        $scadDirectory,

        # Subfolders within the current folder (recursive)
        (Get-ChildItem -Path $scadDirectory -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }),

        # Sibling folders in the same parent directory
        (Get-ChildItem -Path $parentDirectory -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }),

        # Repository root
        (Get-PSDrive -Name ((Get-Item -Path $scadDirectory).PSDrive.Name)).Root
    )

    try {
        foreach ($location in $searchLocations) {
            # Skip null or invalid paths
            if (-not $location -or -not (Test-Path -Path $location)) {
                continue
            }

            # Search for the file in the current location
            $found = Get-ChildItem -Path $location -Filter $includeFileName -File -ErrorAction SilentlyContinue |
                     Select-Object -First 1

            if ($found) {
                Write-Verbose "Found include file: $includeFileName at $($found.FullName)"

                # Create and populate an Include object
                $include = [Include]::new($includeFileName)
                $include.Path = $found.FullName
                $include.Content = Get-Content -Path $found.FullName -Raw

                return $include
            }
        }

        # Log a warning if the file was not found
        Write-Warning "No file found for include: $includeFileName"
        return $null
    }
    catch {
        # Handle unexpected errors
        Write-Warning "Error searching for include file '$includeFileName': $_"
        return $null
    }
}

function Get-Includes-From-ScadFile {
    param (
        [ScadFile]$scadFile
    )

    $includeArray = @()

     # Split content into lines and find all matches
    $includeMatches = $scadFile.Content | Select-String -Pattern 'include\s+<(.+?)>' -AllMatches

    # Extract each match
    foreach ($match in $includeMatches) {
        foreach ($group in $match.Matches) {
            # Add the include to the array of includes. create an Include object with the name of the include
            $includeName = $group.Groups[1].Value
            # Add the include to the array of includes
            $includeArray += $includeName
        }
    }
    
    Write-Verbose "Total includes found: $($includeArray.Count)"
    return $includeArray
}

function Test-FolderExists {
    param (
        [string]$folderPath
    )
    if (-not (Test-Path -Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath | Out-Null
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

class ScadFile {
    [string]$Path
    [string]$Content
    [string]$Name
    [bool]$IsProcessed
    [array]$Includes

    # Default constructor
    ScadFile() {}

    # Constructor with path and content
    ScadFile([string]$path, [string]$content) {
        $this.Path = $path
        $this.Content = $content
        $this.Name = Split-Path $path -Leaf
        $this.IsProcessed = $false
        $this.Includes = @()
    }
}

class Include {
    [string]$Content
    [string]$Name
    [string]$Path

    # Default constructor
    Include([string]$name) {
        $this.Name = $name
        $this.Content = $null
        $this.Path = $null
    }

    Include([string]$name, [string]$content, [string]$path) {
        $this.Name = $name
        $this.Content = $content
        $this.Path = $path
    }
}