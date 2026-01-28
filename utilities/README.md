# Boomi Migration Factory - Utilities

This document describes the utility scripts.

## Find Boomi Custom Scripts

Scans Boomi process XML files and generates a CSV report identifying which processes contain custom scripts (Groovy or JavaScript) and their versions.

### Purpose

When migrating or auditing Boomi processes, it's important to know which processes use custom scripts and what scripting language they use (Groovy 1.5, Groovy 2.4, or JavaScript). This utility automates that discovery by scanning the Runtime's `processes` folder.

### Files

| Platform | File | Location |
|----------|------|----------|
| Linux/macOS | `find-boomi-custom-scripts.sh` | `src/utilities/` |
| Windows | `find-boomi-custom-scripts.ps1` | `src/utilities/` |
| Windows | `find-boomi-custom-scripts.bat` | `src/utilities/` |

### Usage

#### Linux/macOS

```bash
./find-boomi-custom-scripts.sh <processes_folder>
```

**Example:**
```bash
./find-boomi-custom-scripts.sh /data/boomi/Boomi_AtomSphere/Atom/Atom_runtime_basic_ec2_linux/processes
```

#### Windows (Command Prompt)

```batch
find-boomi-custom-scripts.bat <processes_folder>
```

**Example:**
```batch
find-boomi-custom-scripts.bat C:\boomi\Boomi_AtomSphere\Atom\Atom_runtime\processes
```

#### Windows (PowerShell)

```powershell
.\find-boomi-custom-scripts.ps1 <processes_folder>
```

**Example:**
```powershell
.\find-boomi-custom-scripts.ps1 C:\boomi\Boomi_AtomSphere\Atom\Atom_runtime\processes
```

### Output Format

The script outputs CSV format to stdout with **one line per custom script**:

```csv
process_id,process_name,shape_name,script_language,folder
5041adc7-8c59-4628-be7e-625da0f88014,"This is an old process","dataprocess (before documentproperties)","Groovy 1.5","Boomi_Account/Project/Legacy"
5041adc7-8c59-4628-be7e-625da0f88014,"This is an old process","dataprocess (before stop)","Groovy 1.5","Boomi_Account/Project/Legacy"
545ed398-71f8-4683-b26b-5443b3e907f7,"This is a main process","dataprocess (before documentproperties)","Groovy 2.4","Boomi_Account/PSO/Customers/CIDI"
911c099b-127c-4f50-8fcf-81bb3b88ca86,"This is a sub-process","dataprocess (before stop)","Groovy 1.5","Boomi_Account/PSO/Customers/CIDI"
f1437ef8-3ef0-4013-a890-c1d65205b9e6,"One process with JavaScript","dataprocess-JS Shape (before stop)","JavaScript","Boomi_Account/PSO/Customers/CIDI"
f613ef44-fbed-4ca1-9348-75f679bc1095,"(Main) Artefacts Shrinker","dataprocess-ZipShrinker (before documentproperties)","Groovy 1.5","Boomi_Account/Migrations"
```

| Column | Description |
|--------|-------------|
| `process_id` | The Boomi component ID (UUID) |
| `process_name` | The process name (commas replaced with semicolons for CSV safety) |
| `shape_name` | The shape containing the script, formatted as `{shapetype}-{userlabel} (before {next_shapetype})` |
| `script_language` | `Groovy 1.5`, `Groovy 2.4`, or `JavaScript` |
| `folder` | The Boomi folder path from the FolderId element |

### Saving Output to File

```bash
# Linux/macOS
./find-boomi-custom-scripts.sh /path/to/processes > custom-scripts-report.csv

# Windows
find-boomi-custom-scripts.bat C:\path\to\processes > custom-scripts-report.csv
```

### Script Language Detection

The script detects scripting languages by examining the `language` attribute in `<dataprocessscript>` elements:

| XML Attribute | Script Language |
|---------------|-----------------|
| `language="groovy"` | Groovy 1.5 |
| `language="groovy2"` | Groovy 2.4 |
| `language="javascript"` | JavaScript |

### Testing

Test scripts are provided in `src/test/boomi/` to validate the utilities against sample Boomi process data.

#### Linux/macOS - Test Shell Script (.sh)

```bash
cd src/test/boomi
./utilities-tester.sh
```

#### Linux/macOS - Test Windows Script (.bat/.ps1)

Requires PowerShell (`pwsh`) to be installed. Install with `brew install powershell` on macOS.

```bash
cd src/test/boomi
./utilities-tester.bat.sh
```

#### Windows (PowerShell)

```powershell
cd src\test\boomi
.\utilities-tester.bat.sh   # via Git Bash or WSL
# Or run the PowerShell script directly:
powershell -File ..\..\utilities\find-boomi-custom-scripts.ps1 .\processes
```

The test scripts will run the utilities against the sample processes in `src/test/boomi/processes/` and display the results.

### Notes

- **One line per script**: Each custom script shape generates its own row in the output, making it easy to identify individual scripts within a process.
- **Deduplication**: Sub-processes may appear in multiple parent process folders. The script automatically deduplicates results based on process ID and shape name.
- **Typical processes folder locations**:
  - Linux: `/data/boomi/Boomi_AtomSphere/Atom/<atom_name>/processes`
  - Windows: `C:\boomi\Boomi_AtomSphere\Atom\<atom_name>\processes`
