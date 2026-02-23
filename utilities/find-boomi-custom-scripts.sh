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
#   process_id,process_name,component_id,component_name,component_type,shape_name,script_language,folder
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
#   - When a dataprocessscript has a componentId attribute (referencing a script component),
#     the language is taken from the referenced component's ProcessingScript element
#   - process_id identifies the owning process for maps/functions by tracing References chains

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

# Create temporary files for results and reference map
temp_file=$(mktemp)
ref_map_file=$(mktemp)
trap "rm -f $temp_file $ref_map_file" EXIT

# ==========================================
# Pass 1: Scan all XMLs to build reference maps
# ==========================================
# Output format: one line per XML with TYPE, NAME, and REF entries
#   TYPE <component_id> <component_type>
#   NAME <component_id> <component_name>
#   REF <source_id> <source_type> <target_id>
find "$PROCESSES_FOLDER" -name "*.xml" -type f -exec perl -0777 -ne '
    my $id = "";
    my $type = "";
    my $name = "";
    if (/<Id>([^<]*)<\/Id>/) { $id = $1; }
    if (/<Type>([^<]*)<\/Type>/) { $type = $1; }
    if (/<Name>([^<]*)<\/Name>/) { $name = $1; $name =~ s/,/;/g; }
    next unless $id && $type;
    print "TYPE $id $type\n";
    print "NAME $id $name\n" if $name ne "";
    # Extract all Ref compId entries from References
    while (/<Ref\s+[^>]*compId="([^"]*)"[^>]*>/g) {
        print "REF $id $type $1\n";
    }
' {} + > "$ref_map_file"

# lookup_process_ids: Given a component_id and component_type, output process_id(s)
# For processes: process_id = component_id
# For maps: find processes that reference this map
# For functions: find processes that directly reference this function,
#   OR find maps that reference this function, then find processes referencing those maps
lookup_process_ids() {
    local comp_id="$1"
    local comp_type="$2"

    if [ "$comp_type" = "process" ] || [ "$comp_type" = "process.process" ]; then
        echo "$comp_id"
        return
    fi

    local found_any=false

    if [ "$comp_type" = "transform.map" ]; then
        # Find processes referencing this map
        grep "^REF .* process $comp_id\$" "$ref_map_file" 2>/dev/null | while read -r _ src_id _ _; do
            echo "$src_id"
        done
        # Check if we found any
        if grep -q "^REF .* process $comp_id\$" "$ref_map_file" 2>/dev/null; then
            found_any=true
        fi
    elif [ "$comp_type" = "transform.function" ]; then
        # First: find processes that directly reference this function
        grep "^REF .* process $comp_id\$" "$ref_map_file" 2>/dev/null | while read -r _ src_id _ _; do
            echo "$src_id"
        done
        if grep -q "^REF .* process $comp_id\$" "$ref_map_file" 2>/dev/null; then
            found_any=true
        fi

        # Second: find maps referencing this function, then processes referencing those maps
        grep "^REF .* transform\.map $comp_id\$" "$ref_map_file" 2>/dev/null | while read -r _ map_id _ _; do
            grep "^REF .* process $map_id\$" "$ref_map_file" 2>/dev/null | while read -r _ proc_id _ _; do
                echo "$proc_id"
            done
        done
        if grep -q "^REF .* transform\.map $comp_id\$" "$ref_map_file" 2>/dev/null; then
            found_any=true
        fi
    fi

    # If no process found, output empty line so we still get a row
    if [ "$found_any" = false ]; then
        echo ""
    fi
}

# lookup_name: Given a component_id, output its name from the ref_map_file
lookup_name() {
    local comp_id="$1"
    grep "^NAME $comp_id " "$ref_map_file" 2>/dev/null | head -1 | sed "s/^NAME $comp_id //"
}

# ==========================================
# Pass 2: Find scripts in components (existing logic, augmented with process_id)
# ==========================================
find "$PROCESSES_FOLDER" -name "*.xml" -type f | while read -r xml_file; do
    # Check if file contains scripts: either dataprocessscript (processes) or Scripting (maps/functions)
    # Use separate checks to handle multi-line XML tags
    if grep -q 'dataprocessscript' "$xml_file" 2>/dev/null && grep -qE 'language="(groovy|javascript)' "$xml_file" 2>/dev/null || \
       grep -qE '<Scripting language="(groovy|javascript)' "$xml_file" 2>/dev/null; then

        # Extract the component ID from <Id> tag
        component_id=$(grep -o '<Id>[^<]*</Id>' "$xml_file" | head -1 | sed 's/<Id>//;s/<\/Id>//')

        # Extract the component Name from <Name> tag
        # Escape any commas in the name for CSV safety
        component_name=$(grep -o '<Name>[^<]*</Name>' "$xml_file" | head -1 | sed 's/<Name>//;s/<\/Name>//' | sed 's/,/;/g')

        # Extract the component Type from <Type> tag
        component_type=$(grep -o '<Type>[^<]*</Type>' "$xml_file" | head -1 | sed 's/<Type>//;s/<\/Type>//')

        # Extract the Boomi folder path from FolderId name attribute
        folder=$(grep -o '<FolderId name="[^"]*"' "$xml_file" | head -1 | sed 's/<FolderId name="//;s/"$//')

        # Get the directory of the current XML file (for looking up referenced components)
        xml_dir=$(dirname "$xml_file")

        # Read the file content
        content=$(cat "$xml_file")

        # Use perl to extract scripts from processes (dataprocessscript) and maps/functions (Scripting)
        # This handles both single-line and multi-line XML
        # Pass the directory path as an argument for looking up referenced components
        echo "$content" | perl -0777 -sne '
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

                    # Check if there is a componentId override - if so, get language from referenced component
                    if ($body =~ /<dataprocessscript[^>]*?componentId="([^"]*)"/) {
                        my $ref_component_id = $1;
                        my $ref_file = "$xml_dir/$ref_component_id.xml";
                        if (-f $ref_file) {
                            open(my $fh, "<", $ref_file) or next;
                            my $ref_content = do { local $/; <$fh> };
                            close($fh);
                            # Extract language from ProcessingScript element
                            if ($ref_content =~ /<ProcessingScript\s+language="([^"]*)"/) {
                                $language = $1;
                            }
                        }
                    }

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
        ' -- -xml_dir="$xml_dir" | while IFS=$'\t' read -r shape_name script_language; do
            # Look up process_id(s) and emit one row per process
            lookup_process_ids "$component_id" "$component_type" | sort -u | while read -r process_id; do
                process_name=$(lookup_name "$process_id")
                echo "${process_id},\"${process_name}\",${component_id},\"${component_name}\",\"${component_type}\",\"${shape_name}\",\"${script_language}\",\"${folder}\"" >> "$temp_file"
            done
        done
    fi
done

# Print CSV header
echo "process_id,process_name,component_id,component_name,component_type,shape_name,script_language,folder"

# Deduplicate by process_id+component_id+shape_name (columns 1, 3 and 6) and output sorted results
if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
    sort -t',' -k1,1 -k3,3 -k6,6 -u "$temp_file"
fi
