#
# Find Boomi Custom Scripts (Windows PowerShell)
#
# This script scans Boomi component XML files and outputs a CSV report
# identifying which components contain custom scripts (Groovy or JavaScript).
#
# Supported component types:
#   - process (Data Process shapes with scripts)
#   - transform.map (Map components with Scripting function steps)
#   - transform.function (Map Function components with Scripting function steps)
#
# Usage:
#   .\find-boomi-custom-scripts.ps1 <processes_folder>
#
# Example:
#   .\find-boomi-custom-scripts.ps1 C:\boomi\Boomi_AtomSphere\Atom\Atom_runtime\processes
#
# Output: CSV format (one line per custom script)
#   component_id,component_name,component_type,shape_name,script_language,folder
#
# Script languages:
#   - "groovy" in XML = Groovy 1.5
#   - "groovy2" in XML = Groovy 2.4
#   - "javascript" in XML = JavaScript
#
# Notes:
#   - Sub-processes may appear in multiple parent process folders; this script deduplicates them
#   - For processes: shape_name is formatted as "{shapetype}-{userlabel} (before {next_shapetype})"
#   - For maps/functions: shape_name is the FunctionStep name (e.g., "Scripting")
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

        # Check if file contains scripts: either dataprocessscript (processes) or Scripting (maps/functions)
        if ($content -match '(dataprocessscript.*language="(groovy|javascript)|<Scripting language="(groovy|javascript))') {

            # Extract the component ID from <Id> tag
            $componentId = $null
            if ($content -match '<Id>([^<]+)</Id>') {
                $componentId = $Matches[1]
            }

            # Extract the component Name from <Name> tag
            $componentName = ""
            if ($content -match '<Name>([^<]+)</Name>') {
                $componentName = $Matches[1]
                # Escape any commas in the name for CSV safety
                $componentName = $componentName -replace ',', ';'
            }

            # Extract the component Type from <Type> tag
            $componentType = ""
            if ($content -match '<Type>([^<]+)</Type>') {
                $componentType = $Matches[1]
            }

            # Extract the Boomi folder path from FolderId name attribute
            $folder = ""
            if ($content -match '<FolderId name="([^"]*)"') {
                $folder = $Matches[1]
            }

            # For processes: extract from shape elements with dataprocessscript
            if ($componentType -eq "process" -or $componentType -eq "process.process") {
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
                        $uniqueKey = "$componentId|$shapeName"

                        # Skip if we've already processed this entry
                        if ($processedEntries.ContainsKey($uniqueKey)) {
                            continue
                        }
                        $processedEntries[$uniqueKey] = $true

                        # Add to results
                        $results += [PSCustomObject]@{
                            component_id = $componentId
                            component_name = $componentName
                            component_type = $componentType
                            shape_name = $shapeName
                            script_language = $scriptLanguage
                            folder = $folder
                        }
                    }
                }
            }
            # For maps and functions: extract from FunctionStep elements with Scripting
            elseif ($componentType -eq "transform.map" -or $componentType -eq "transform.function") {
                # Find all FunctionStep elements containing Scripting
                $functionStepMatches = [regex]::Matches($content, '<FunctionStep\s+([^>]*)>(.*?)</FunctionStep>', [System.Text.RegularExpressions.RegexOptions]::Singleline)

                foreach ($functionStepMatch in $functionStepMatches) {
                    $fsAttrs = $functionStepMatch.Groups[1].Value
                    $fsBody = $functionStepMatch.Groups[2].Value

                    # Check if this FunctionStep contains a Scripting configuration
                    if ($fsBody -match '<Scripting\s+language="([^"]*)"') {
                        $language = $Matches[1]

                        # Extract name from FunctionStep attributes
                        $shapeName = "Scripting"
                        if ($fsAttrs -match 'name="([^"]*)"') {
                            $shapeName = $Matches[1]
                        }

                        # Map language to display name
                        $scriptLanguage = switch ($language) {
                            "groovy"     { "Groovy 1.5" }
                            "groovy2"    { "Groovy 2.4" }
                            "javascript" { "JavaScript" }
                            default      { $language }
                        }

                        # Create unique key for deduplication
                        $uniqueKey = "$componentId|$shapeName"

                        # Skip if we've already processed this entry
                        if ($processedEntries.ContainsKey($uniqueKey)) {
                            continue
                        }
                        $processedEntries[$uniqueKey] = $true

                        # Add to results
                        $results += [PSCustomObject]@{
                            component_id = $componentId
                            component_name = $componentName
                            component_type = $componentType
                            shape_name = $shapeName
                            script_language = $scriptLanguage
                            folder = $folder
                        }
                    }
                }
            }
        }
    } catch {
        Write-Warning "Error processing file: $($xmlFile.FullName) - $_"
    }
}

# Output CSV header
Write-Output "component_id,component_name,component_type,shape_name,script_language,folder"

# Output sorted results
$results | Sort-Object -Property component_id, shape_name | ForEach-Object {
    Write-Output "$($_.component_id),`"$($_.component_name)`",`"$($_.component_type)`",`"$($_.shape_name)`",`"$($_.script_language)`",`"$($_.folder)`""
}
