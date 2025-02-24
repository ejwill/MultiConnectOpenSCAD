# Params for the script
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string[]]$pathArray,  # The input path (file or folder)

    [Parameter(Mandatory = $false)]
    [string]$outputFolderPath # Default to "output" folder in the same directory as the input file
)

$VerbosePreference = 'Continue'
$DEFAULT_OUTPUT_FOLDER = "output"

$global:ProcessedFiles = @{}  # Track processed files globally

enum ImportType {
    Unknown
    Include
    Use
}

enum LogicType {
    Unknown
    Module
    Function
}


class ScadFile {
    [string]$Path
    [string]$Content
    [string]$Name
    [bool]$IsProcessed
    [Import[]]$Imports
    # [Import[]]$Includes
    # [Import[]]$Uses
    [Logic[]]$Modules
    [Logic[]]$Functions

    # Default constructor
    ScadFile() {}

    # Constructor with path and content
    ScadFile([string]$path, [string]$content) {
        $this.Path = $path
        $this.Content = $content
        $this.Name = Split-Path $path -Leaf
        $this.IsProcessed = $false
        $this.Imports = @()
        # $this.Includes = @()
        # $this.Uses = @()
        $this.Modules = @()
        $this.Functions = @()
    }
}

class Import {
    [string]$Content
    [string]$Name
    [string]$Path
    [Logic[]]$Modules
    [Logic[]]$Functions
    [ImportType]$Type
    [string]$ImportReference
    

    # Default constructor
    Import([string]$name, [ImportType]$type) {
        $this.Name = $name
        $this.Content = $null
        $this.Path = $null
        $this.Modules = @()
        $this.Functions = @()
        $this.Type = $type
    }

    Import([string]$name, [string]$content, [string]$path, [ImportType]$type) {
        $this.Name = $name
        $this.Content = $content
        $this.Path = $path
        $this.Modules = @()
        $this.Functions = @()
        $this.Type = $type
    }
}

class Logic {
    [string]$Name
    [string]$Content
    [LogicType]$Type

    Logic() {}

    Logic([string]$name, [string]$content, [LogicType]$type) {
        $this.Name = $name
        $this.Content = $content
        $this.Type = $type
    }
}

function Invoke-ProcessScadFilesInFolder {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$folderPath,
        [Parameter(Mandatory = $true)]
        [string]$outputFolderPath
    )

    $scadFiles = Get-ChildItem -Path $folderPath -Filter "*.scad" -Recurse -ErrorAction SilentlyContinue
    if (-not $scadFiles) {
        Write-Warning "No .scad files found in: $folderPath"
        return
    }

    foreach ($scadFile in $scadFiles) {
        Invoke-ProcessScadFile -filePath $scadFile.FullName -outputFolderPath $outputFolderPath
    }
}

function Invoke-ProcessScadFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$filePath,
        [Parameter(Mandatory = $true)]
        [string]$outputFolderPath
    )

    Write-Verbose "Processing file: $filePath"

    $fileDetails = Get-Item -Path $filePath

    # Read the file content and put it in a Scadfile object
    $fileContent = Get-Content -Path $filePath -Raw

    $scadFile = New-Object ScadFile -ArgumentList $fileDetails.FullName, $fileContent

    if (-not $scadFile) {
        Write-Error "Failed to create ScadFile object for file: $filePath"
        return
    }

    $logic = Get-LogicPartsFromScadContent -Content $fileContent

    $scadFile.Modules = $logic.Modules
    $scadFile.Functions = $logic.Functions

    Write-Verbose "Retrived Logic Parts"
    
    # Get the import names from the file content

    $scadFile.Imports = Get-ImportsFromScadFile -scadFile $scadFile

    Write-Verbose "Retrived Imports"

    $imports = Get-ImportDetails -scadFile $scadFile
    if (-not $imports) {
        $imports = @()
    }
    $scadFile.Imports = $imports

    # Write the new content to the file
    $newScadFile = Expand-ScadFileImports -scadFile $scadFile
    Write-Verbose "Scad File Expanded"

    # Write the new content to a new file in the output folder
    Save-ScadFile -scadFile $newScadFile -outputFolderPath $outputFolderPath

    Write-Verbose "Finished Processing file: $($scadFile.Name)" 
}

function Get-LogicPartsFromScadContent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $logicArray = @()
    $currentLogic = $null
    $currentContent = @()
    $type = $null

    # Ensure regex captures leading spaces (avoiding partial matches)
    $moduleRegex = '^\s*module\s+(\w+)\s*\((.*?)\)\s*{'
    $functionRegex = '^\s*function\s+(\w+)\s*\((.*?)\)\s*{' 

    # Read content line by line
    $lines = $Content -split "`r?`n"

    foreach ($line in $lines) {
        if ($line -match $moduleRegex) {
            # Save previous function/module if we were processing one
            if ($currentLogic) {
                $logicArray += New-Object Logic -ArgumentList $currentLogic, ($currentContent -join "`n"), $type
            }
            # Start new logic block
            $currentLogic = $matches[1]  # Capture module name
            $currentContent = @($line)
            $type = [LogicType]::Module
        } elseif ($line -match $functionRegex) {
            if ($currentLogic) {
                $logicArray += New-Object Logic -ArgumentList $currentLogic, ($currentContent -join "`n"), $type
            }
            $currentLogic = $matches[1]  # Capture function name
            $currentContent = @($line)
            $type = [LogicType]::Function
        } elseif ($currentLogic) {
            # Append multi-line content
            $currentContent += $line
        }
    }

    # Save last logic block
    if ($currentLogic) {
        $logicArray += New-Object Logic -ArgumentList $currentLogic, ($currentContent -join "`n"), $type
    }

    return $logicArray
}

function Get-ImportsFromScadFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ScadFile]$scadFile
    )

    $importTypes = [ImportType]::GetValues([ImportType])
    $importArray = @()

    foreach ($type in $importTypes) {
        if ($type -eq [ImportType]::Unknown) {
            continue
        }
    
        $pattern = if ($type -eq [ImportType]::Include) {
            # '^\s*include\s+<(.+?)>\s*(;|\s*)$'  # Matches 'include' with optional semicolon or spaces
            '(?i)include\s+<(.+?)>'
        } elseif ($type -eq [ImportType]::Use) {
            '(?i)use\s+<(.+?)>'
            # '^\s*use\s+<(.+?)>\s*(;|\s*)$'  # Matches 'use' with optional semicolon or spaces
        } else {
            continue
        }

        # $pattern = if ($type -eq [ImportType]::Include) {
        #     '^\s*include\s+<([^>]+)>\s*;'
        # } elseif ($type -eq [ImportType]::Use) {
        #     '^\s*use\s+<([^>]+)>\s*;'
        # } else {
        #     continue
        # }

        $regexMatches = $scadFile.Content | Select-String -Pattern $pattern -AllMatches
        foreach ($match in $regexMatches) {
            foreach ($group in $match.Matches) {
                $importReference = $group.Groups[1].Value
                $absolutePath = Resolve-Path -Path (Join-Path -Path (Split-Path $scadFile.Path) -ChildPath $importReference) -ErrorAction SilentlyContinue
                $name = if ($absolutePath) { Split-Path -Leaf $absolutePath } else { $importReference }

                $import = New-Object Import -ArgumentList @($name, $type)
                $import.ImportReference = $importReference
                $import.Path = $absolutePath
                $importArray += $import
            }
        }
    }

    return $importArray
}

function Get-ImportDetails {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ScadFile]$scadFile
    )

    $scadDirectory = Split-Path -Path $scadFile.Path

    $importArray = @()

    foreach ($import in $scadFile.Imports) {
        try {
            $found = Find-File -directory $scadDirectory -fileName $import.ImportReference

            if ($found) {
                Write-Verbose "Found include file: $import.Name at $($found.FullName)"

                $foundImport = [Import]::new($import.Name, $import.Type)
                $foundImport.Path = $found.FullName
                $foundImport.Content = Get-Content -Path $found.FullName -Raw
                $logicParts = Get-LogicPartsFromScadContent -Content $foundImport.Content
                $foundImport.Modules = $logicParts.Modules
                $foundImport.Functions = $logicParts.Functions
                $foundImport.ImportReference = $import.ImportReference

                $importArray += $foundImport
            }
        } catch {
            Write-Warning "Could not read file: $($import.Name) . $_"
        }
    }

    return $importArray
}

function Find-File {
    param (
        [Parameter(Mandatory = $true)]
        [string]$directory,
        [Parameter(Mandatory = $true)]
        [string]$fileName
    )

    if (-not (Test-Path -Path $directory -PathType Container)) {
        Write-Warning "The directory '$directory' does not exist."
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        Write-Warning "File name cannot be null or empty."
        return $null
    }

    # 1️⃣ Extract `../` occurrences from the file name
    $parentDir = $directory
    if ($fileName -match '^(\.\./)+') {
        $numLevelsUp = ($fileName -split '/').Where({$_ -eq ".."}).Count
        for ($i = 0; $i -lt $numLevelsUp; $i++) {
            $parentDir = Split-Path -Path $parentDir -Parent
        }
        $fileName = $fileName -replace '^(\.\./)+', ''
    
        # Ensure the final path is valid
        $resolvedPath = Join-Path -Path $parentDir -ChildPath $fileName
        if (-not (Test-Path -Path $resolvedPath -PathType Leaf)) {
            Write-Warning "Resolved path does not exist: $resolvedPath"
            return $null
        }
    }

    # 2️⃣ Start with prioritized search paths
    $searchPaths = @($directory, $parentDir)

    # 3️⃣ Add subdirectories recursively
    $subdirs = Get-ChildItem -Path $directory -Directory -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    $searchPaths += $subdirs

    # 4️⃣ Add sibling directories **only if** the file hasn't already been found
    $parentDirectory = Split-Path -Path $directory -Parent
    if ($parentDirectory -and -not (Test-Path -Path (Join-Path -Path $parentDirectory -ChildPath $fileName) -PathType Leaf)) {
        $siblingDirs = Get-ChildItem -Path $parentDirectory -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        $searchPaths += $siblingDirs
    }

    # 🚀 Now, iterate through paths and find the file
    foreach ($path in $searchPaths) {
        $found = Get-ChildItem -Path $path -Filter $fileName -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            Write-Verbose "Found file: $($found.FullName)"
            return $found
        }
    }

    Write-Warning "File not found: $fileName"
    return $null
}

function Expand-ScadFileImports {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ScadFile]$scadFile
    )

    if ($scadFile.Imports.Count -eq 0) {
        Write-Verbose "No imports found for $($scadFile.Name). Returning original content."
        $scadFile.IsProcessed = $true
        return $scadFile
    }

    $newContent = $scadFile.Content

    foreach ($import in $scadFile.Imports) {
        # 🔴 ADD THIS CHECK TO PREVENT INFINITE LOOP
        if ($global:ProcessedFiles.ContainsKey($import.Path)) {
            Write-Verbose "Skipping already processed import: $($import.Name)"
            continue
        }

        if ($import.Content) {
            Write-Verbose "Expanding import: $($import.Name)"

            # ✅ Mark file as processed to prevent infinite loops
            $global:ProcessedFiles[$import.Path] = $true

            # ✅ Recursively process imports in this file
            $importScadFile = New-Object ScadFile -ArgumentList $import.Path, $import.Content
            $importScadFile.Imports = Get-ImportsFromScadFile -scadFile $importScadFile
            $importScadFile = Expand-ScadFileImports -scadFile $importScadFile  # Recursive call

            # Escape the import reference to be used in the regex
            $escapedImportReference = [Regex]::Escape($import.ImportReference)

            # ✅ Merge content based on type
            if ($import.Type -eq [ImportType]::Include) {
                # $pattern = "(?s)^\s*include\s+<($escapedImportReference)>\s*"
                $pattern = "(?i)include\s+<($($import.ImportReference))>\s*(\r?\n|\r)?"
                $replacement = "`n// === Include: $($import.Name) === `n$($importScadFile.Content)`n// === End Include: $($import.Name) ===`n"
            }
            elseif ($import.Type -eq [ImportType]::Use) {
                # $pattern = "^\s*use\s+<($escapedImportReference)>\s*"
                $pattern = "(?i)use\s+<($($import.ImportReference))>\s*(\r?\n|\r)?"
                $moduleContent = $importScadFile.Modules | ForEach-Object { $_.Content } -join "`n"
                $functionContent = $importScadFile.Functions | ForEach-Object { $_.Content } -join "`n"
                $replacement = "`n// === Use: $($import.Name) === `n$moduleContent`n$functionContent`n// === End Use: $($import.Name) ===`n"
            }
            else {
                Write-Warning "Unknown import type: $($import.Type)"
                continue
            }

            $patternMatches = Select-String -InputObject $newContent -Pattern $pattern -AllMatches
            if ($patternMatches.Count -gt 1) {
                Write-Warning "Multiple matches found for import: $($import.Name). This may indicate a potential issue."
            }

            $testMatches = $newContent -match $pattern

            # ✅ Replace the import statement with the expanded content
            $newContent = $newContent -replace $pattern, $replacement
        }
    }

    $scadFile.Content = $newContent
    $scadFile.IsProcessed = $true
    return $scadFile
}

# TODO: Handle recursive imports
# function Expand-ScadFileImports {
#     [CmdletBinding()]
#     param (
#         [Parameter(Mandatory = $true)]
#         [ScadFile]$scadFile
#     )

#     if ($scadFile.Imports.Count -eq 0) {
#         Write-Verbose "No imports found for $($scadFile.Name). Returning original content."
#         $scadFile.IsProcessed = $true
#         return $scadFile
#     }

#     $newContent = $scadFile.Content

#     # Remove the import line from the content of the ScadFile where the import was found only if the import has content
#     foreach ($import in $scadFile.Imports) {
#         if ($import.Content) {
            
#             if ($import.Type -eq [ImportType]::Include) {
#                 $pattern = "(?i)include\s+<($($import.ImportReference))>\s*(\r?\n|\r)?"
#                 $replacement = "`n`n// === Include: $($import.Name) === `n`n$($import.Content)`n`n// === End Include: $($import.Name) ===`n`n"
#             }
#             elseif ($import.Type -eq [ImportType]::Use) {
#                 $pattern = "(?i)use\s+<($($import.ImportReference))>\s*(\r?\n|\r)?"
#                 # for use, only need to add the content of modules and functions
#                 $moduleContent = $import.Modules | ForEach-Object { $_.Content } -join "`n"
#                 $functionContent = $import.Functions | ForEach-Object { $_.Content } -join "`n"
#                 $replacement = "`n`n// === Use: $($import.Name) === `n`n$($moduleContent)`n`n$($functionContent)`n`n// === End Use: $($import.Name) ===`n`n"
#             }
#             else {
#                 Write-Warning "Unknown import type: $($import.Type)"
#                 continue
#             }
            
#             # Replace include statement with actual content, preserving the structure
#             $newContent = $newContent -replace $pattern, $replacement
#         }
#     }

#     $scadFile.Content = $newContent
#     $scadFile.IsProcessed = $true

#     return $scadFile
# }

function Save-ScadFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ScadFile]$scadFile,
        [Parameter(Mandatory = $true)]
        [string]$outputFolderPath
    )

    $repoRoot = (Get-Location).Path
    $filePath = $scadFile.Path
    
    # Ensure the file path is absolute
    if (-not (Test-Path -Path $filePath -PathType Leaf)) {
        $filePath = Join-Path -Path $repoRoot -ChildPath $filePath
    }

    if ($filePath.Length -le $repoRoot.Length) {
        Write-Error "The file path is shorter than or equal to the repository root path."
        return
    }

    # Calculate the relative path from the repository root
    $relativePath = $filePath.Substring($repoRoot.Length).TrimStart('\', '/')
    $outputFilePath = Join-Path -Path $outputFolderPath -ChildPath $relativePath
    Write-Verbose "Publishing file to: $outputFilePath"

    # Ensure the directory for the output file exists
    $outputDirectory = Split-Path -Path $outputFilePath -Parent
    if (-not (Test-Path -Path $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    # Write the new content to the output file
    try {
        Set-Content -Path $outputFilePath -Value $scadFile.Content -Force
        Write-Verbose "File saved successfully to: $outputFilePath"
    }
    catch {
        Write-Error "Failed to save file to: $outputFilePath. $_"
    }
}

# Main script logic

# Set default output folder path if not provided
if (-not $outputFolderPath) {
    $repoRoot = (Get-Location).Path
    $outputFolderPath = Join-Path -Path $repoRoot -ChildPath $DEFAULT_OUTPUT_FOLDER
    Write-Verbose "Output folder path not provided. Using default: $outputFolderPath"
}

# Ensure the output folder exists
if (-not (Test-Path -Path $outputFolderPath)) {
    New-Item -ItemType Directory -Path $outputFolderPath | Out-Null
    Write-Verbose "Created output folder: $outputFolderPath"
}

if (-not $pathArray -or $pathArray.Count -eq 0) {
    Write-Error "No paths provided to process."
    exit 1
}

# Check if the path is a file or a folder
Write-Verbose "Processing Files: $($pathArray -join ', ')"

foreach ($path in $pathArray) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-Warning "Skipping empty path."
        continue
    }

    if (Test-Path $path) {
        if (Test-Path $path -PathType Leaf) {
            Write-Verbose "Processing file: $path"
            Invoke-ProcessScadFile -filePath $path -outputFolderPath $outputFolderPath
        } elseif (Test-Path $path -PathType Container) {
            Write-Verbose "Processing folder: $path"
            Invoke-ProcessScadFilesInFolder -folderPath $path -outputFolderPath $outputFolderPath
        } else {
            Write-Warning "The path is neither a valid file or a folder: $path"
        }
    } else {
        Write-Warning "The provided path does not exist: $path"
    }
}

