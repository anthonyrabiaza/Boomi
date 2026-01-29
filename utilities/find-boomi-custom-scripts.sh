#!/bin/bash
#
# Find Boomi Custom Scripts
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
#   ./find-boomi-custom-scripts.sh <processes_folder>
#
# Example:
#   ./find-boomi-custom-scripts.sh /data/boomi/Boomi_AtomSphere/Atom/Atom_runtime_basic_ec2_linux/processes
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

set -e

# Check if folder argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <processes_folder>" >&2
    echo "Example: $0 /data/boomi/Boomi_AtomSphere/Atom/Atom_runtime_basic_ec2_linux/processes" >&2
    echo "" >&2
    echo "Detects: Groovy 1.5, Groovy 2.4, JavaScript" >&2
    exit 1
fi

PROCESSES_FOLDER="$1"

# Check if folder exists
if [ ! -d "$PROCESSES_FOLDER" ]; then
    echo "Error: Folder not found: $PROCESSES_FOLDER" >&2
    exit 1
fi

# Create a temporary file to store results before deduplication
temp_file=$(mktemp)
trap "rm -f $temp_file" EXIT

# Find all XML files and process them
find "$PROCESSES_FOLDER" -name "*.xml" -type f | while read -r xml_file; do
    # Check if file contains scripts: either dataprocessscript (processes) or Scripting (maps/functions)
    if grep -qE '(dataprocessscript.*language="(groovy|javascript)|<Scripting language="(groovy|javascript))' "$xml_file" 2>/dev/null; then

        # Extract the component ID from <Id> tag
        component_id=$(grep -o '<Id>[^<]*</Id>' "$xml_file" | head -1 | sed 's/<Id>//;s/<\/Id>//')

        # Extract the component Name from <Name> tag
        # Escape any commas in the name for CSV safety
        component_name=$(grep -o '<Name>[^<]*</Name>' "$xml_file" | head -1 | sed 's/<Name>//;s/<\/Name>//' | sed 's/,/;/g')

        # Extract the component Type from <Type> tag
        component_type=$(grep -o '<Type>[^<]*</Type>' "$xml_file" | head -1 | sed 's/<Type>//;s/<\/Type>//')

        # Extract the Boomi folder path from FolderId name attribute
        folder=$(grep -o '<FolderId name="[^"]*"' "$xml_file" | head -1 | sed 's/<FolderId name="//;s/"$//')

        # Read the file content
        content=$(cat "$xml_file")

        # Use perl to extract scripts from processes (dataprocessscript) and maps/functions (Scripting)
        # This handles both single-line and multi-line XML
        echo "$content" | perl -0777 -ne '
            my $component_type = "";
            if (/<Type>([^<]*)<\/Type>/) {
                $component_type = $1;
            }

            # For processes: extract from shape elements with dataprocessscript
            if ($component_type eq "process" || $component_type eq "process.process") {
                # First, build a map of shape name to shapetype
                my %shape_types;
                while (/<shape\s+([^>]*)>/gs) {
                    my $attrs = $1;
                    my $name = "";
                    my $shapetype = "";
                    if ($attrs =~ /name="([^"]*)"/) { $name = $1; }
                    if ($attrs =~ /shapetype="([^"]*)"/) { $shapetype = $1; }
                    $shape_types{$name} = $shapetype if $name;
                }

                # Now find all shape elements containing dataprocessscript
                while (/<shape\s+([^>]*)>(.*?)<\/shape>/gs) {
                    my $attrs = $1;
                    my $body = $2;

                    # Check if this shape contains a dataprocessscript
                    next unless $body =~ /<dataprocessscript[^>]*?language="([^"]*)"/;
                    my $language = $1;

                    # Extract attributes from shape tag (they can be in any order)
                    my $shape_name_attr = "";
                    my $userlabel = "";
                    my $shapetype = "";
                    if ($attrs =~ /name="([^"]*)"/) { $shape_name_attr = $1; }
                    if ($attrs =~ /userlabel="([^"]*)"/) { $userlabel = $1; }
                    if ($attrs =~ /shapetype="([^"]*)"/) { $shapetype = $1; }

                    # Find the toShape from dragpoint to determine next shape
                    my $next_shapetype = "";
                    if ($body =~ /toShape="([^"]*)"/) {
                        my $to_shape = $1;
                        $next_shapetype = $shape_types{$to_shape} // "";
                    }

                    # Build shape_name
                    my $shape_name = $shapetype;
                    if ($userlabel ne "") {
                        $shape_name = "$shapetype-$userlabel";
                    }
                    if ($next_shapetype ne "") {
                        $shape_name = "$shape_name (before $next_shapetype)";
                    }

                    # Map language to display name
                    my $script_language;
                    if ($language eq "groovy") {
                        $script_language = "Groovy 1.5";
                    } elsif ($language eq "groovy2") {
                        $script_language = "Groovy 2.4";
                    } elsif ($language eq "javascript") {
                        $script_language = "JavaScript";
                    } else {
                        $script_language = $language;
                    }

                    print "$shape_name\t$script_language\n";
                }
            }
            # For maps and functions: extract from FunctionStep elements with Scripting
            elsif ($component_type eq "transform.map" || $component_type eq "transform.function") {
                # Find all FunctionStep elements containing Scripting
                while (/<FunctionStep\s+([^>]*)>(.*?)<\/FunctionStep>/gs) {
                    my $attrs = $1;
                    my $body = $2;

                    # Check if this FunctionStep contains a Scripting configuration
                    next unless $body =~ /<Scripting\s+language="([^"]*)"/;
                    my $language = $1;

                    # Extract name from FunctionStep attributes
                    my $shape_name = "Scripting";
                    if ($attrs =~ /name="([^"]*)"/) {
                        $shape_name = $1;
                    }

                    # Map language to display name
                    my $script_language;
                    if ($language eq "groovy") {
                        $script_language = "Groovy 1.5";
                    } elsif ($language eq "groovy2") {
                        $script_language = "Groovy 2.4";
                    } elsif ($language eq "javascript") {
                        $script_language = "JavaScript";
                    } else {
                        $script_language = $language;
                    }

                    print "$shape_name\t$script_language\n";
                }
            }
        ' | while IFS=$'\t' read -r shape_name script_language; do
            # Output to temp file for deduplication
            echo "${component_id},\"${component_name}\",\"${component_type}\",\"${shape_name}\",\"${script_language}\",\"${folder}\"" >> "$temp_file"
        done
    fi
done

# Print CSV header
echo "component_id,component_name,component_type,shape_name,script_language,folder"

# Deduplicate by component_id+shape_name (columns 1 and 4) and output sorted results
if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
    sort -t',' -k1,1 -k4,4 -u "$temp_file"
fi
