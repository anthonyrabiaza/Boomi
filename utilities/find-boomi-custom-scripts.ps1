#
# Find Boomi Custom Scripts (Windows PowerShell)
#
# This script scans Boomi process XML files and outputs a CSV report
# identifying which processes contain custom scripts (Groovy or JavaScript).
#
# Usage:
#   .\find-boomi-custom-scripts.ps1 <processes_folder>
#
# Example:
#   .\find-boomi-custom-scripts.ps1 C:\boomi\Boomi_AtomSphere\Atom\Atom_runtime\processes
#
# Output: CSV format (one line per custom script)
#   process_id,process_name,shape_name,script_language,folder
#
# Script languages:
#   - "groovy" in XML = Groovy 1.5
#   - "groovy2" in XML = Groovy 2.4
#   - "javascript" in XML = JavaScript
#
# Notes:
#   - Sub-processes may appear in multiple parent process folders; this script deduplicates them
#   - shape_name is formatted as "{shapetype}-{userlabel} (before {next_shapetype})"
#   - folder shows the Boomi folder path from the FolderId element
#

param(
    [Parameter(Position=0)]
    [string]$ProcessesFolder
)

$ErrorActionPreference = "Stop"

# Check if folder argument is provided
if ([string]::IsNullOrEmpty($ProcessesFolder)) {
    Write-Host "Usage: .\find-boomi-custom-scripts.ps1 <processes_folder>" -ForegroundColor Red
    Write-Host "Example: .\find-boomi-custom-scripts.ps1 C:\boomi\Boomi_AtomSphere\Atom\Atom_runtime\processes" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "Detects: Groovy 1.5, Groovy 2.4, JavaScript" -ForegroundColor Red
    exit 1
}

# Check if folder exists
if (-not (Test-Path $ProcessesFolder -PathType Container)) {
    Write-Host "Error: Folder not found: $ProcessesFolder" -ForegroundColor Red
    exit 1
}

# HashSet to track unique entries (for deduplication by process_id + shape_name)
$processedEntries = @{}
$results = @()

# Find all XML files and process them
$xmlFiles = Get-ChildItem -Path $ProcessesFolder -Filter "*.xml" -Recurse -File

foreach ($xmlFile in $xmlFiles) {
    try {
        $content = Get-Content $xmlFile.FullName -Raw

        # Check if file contains dataprocessscript with language attribute (groovy, groovy2, or javascript)
        if ($content -match 'dataprocessscript.*language="(groovy|javascript)') {

            # Extract the component ID from <Id> tag
            $processId = $null
            if ($content -match '<Id>([^<]+)</Id>') {
                $processId = $Matches[1]
            }

            # Extract the component Name from <Name> tag
            $processName = ""
            if ($content -match '<Name>([^<]+)</Name>') {
                $processName = $Matches[1]
                # Escape any commas in the name for CSV safety
                $processName = $processName -replace ',', ';'
            }

            # Extract the Boomi folder path from FolderId name attribute
            $folder = ""
            if ($content -match '<FolderId name="([^"]*)"') {
                $folder = $Matches[1]
            }

            # First, build a map of shape name to shapetype
            $shapeTypes = @{}
            $shapeTagMatches = [regex]::Matches($content, '<shape\s+([^>]*)>')
            foreach ($shapeTagMatch in $shapeTagMatches) {
                $attrs = $shapeTagMatch.Groups[1].Value
                $name = ""
                $shapetype = ""
                if ($attrs -match 'name="([^"]*)"') { $name = $Matches[1] }
                if ($attrs -match 'shapetype="([^"]*)"') { $shapetype = $Matches[1] }
                if ($name) { $shapeTypes[$name] = $shapetype }
            }

            # Find all shape elements and extract those containing dataprocessscript
            $shapeMatches = [regex]::Matches($content, '<shape\s+([^>]*)>(.*?)</shape>', [System.Text.RegularExpressions.RegexOptions]::Singleline)

            foreach ($shapeMatch in $shapeMatches) {
                $shapeAttrs = $shapeMatch.Groups[1].Value
                $shapeBody = $shapeMatch.Groups[2].Value

                # Check if this shape contains a dataprocessscript
                if ($shapeBody -match '<dataprocessscript[^>]*?language="([^"]*)"') {
                    $language = $Matches[1]

                    # Extract attributes from shape tag
                    $userlabel = ""
                    $shapetype = ""
                    if ($shapeAttrs -match 'userlabel="([^"]*)"') { $userlabel = $Matches[1] }
                    if ($shapeAttrs -match 'shapetype="([^"]*)"') { $shapetype = $Matches[1] }

                    # Find the toShape from dragpoint to determine next shape
                    $nextShapetype = ""
                    if ($shapeBody -match 'toShape="([^"]*)"') {
                        $toShape = $Matches[1]
                        if ($shapeTypes.ContainsKey($toShape)) {
                            $nextShapetype = $shapeTypes[$toShape]
                        }
                    }

                    # Build shape_name
                    $shapeName = $shapetype
                    if ($userlabel -ne "") {
                        $shapeName = "$shapetype-$userlabel"
                    }
                    if ($nextShapetype -ne "") {
                        $shapeName = "$shapeName (before $nextShapetype)"
                    }

                    # Map language to display name
                    $scriptLanguage = switch ($language) {
                        "groovy"     { "Groovy 1.5" }
                        "groovy2"    { "Groovy 2.4" }
                        "javascript" { "JavaScript" }
                        default      { $language }
                    }

                    # Create unique key for deduplication
                    $uniqueKey = "$processId|$shapeName"

                    # Skip if we've already processed this entry
                    if ($processedEntries.ContainsKey($uniqueKey)) {
                        continue
                    }
                    $processedEntries[$uniqueKey] = $true

                    # Add to results
                    $results += [PSCustomObject]@{
                        process_id = $processId
                        process_name = $processName
                        shape_name = $shapeName
                        script_language = $scriptLanguage
                        folder = $folder
                    }
                }
            }
        }
    } catch {
        Write-Warning "Error processing file: $($xmlFile.FullName) - $_"
    }
}

# Output CSV header
Write-Output "process_id,process_name,shape_name,script_language,folder"

# Output sorted results
$results | Sort-Object -Property process_id, shape_name | ForEach-Object {
    Write-Output "$($_.process_id),`"$($_.process_name)`",`"$($_.shape_name)`",`"$($_.script_language)`",`"$($_.folder)`""
}
