# Boomi Migration Factory - Utilities

This document describes the utility scripts available in the `src/utilities/` directory.

## Find Boomi Custom Scripts

Scans Boomi component XML files and generates a CSV report identifying which components contain custom scripts (Groovy or JavaScript) and their versions.

### Supported Component Types

- **process** - Data Process shapes with scripts
- **transform.map** - Map components with Scripting function steps
- **transform.function** - Map Function components with Scripting function steps

### Purpose

When migrating or auditing Boomi components, it's important to know which ones use custom scripts and what scripting language they use (Groovy 1.5, Groovy 2.4, or JavaScript). This utility automates that discovery by scanning the Atom's `processes` folder.

### Files

| Platform | File | Location |
|----------|------|----------|
| Linux/macOS | `find-boomi-components.sh` | `src/utilities/` |
| Windows | `find-boomi-components.ps1` | `src/utilities/` |
| Windows | `find-boomi-components.bat` | `src/utilities/` |

### Usage

#### Linux/macOS

```bash
./find-boomi-components.sh <processes_folder>
```

**Example:**
```bash
./find-boomi-components.sh /data/boomi/Boomi_AtomSphere/Atom/Atom_runtime_basic_ec2_linux/processes
```

#### Windows (Command Prompt)

```batch
find-boomi-components.bat <processes_folder>
```

**Example:**
```batch
find-boomi-components.bat C:\boomi\Boomi_AtomSphere\Atom\Atom_runtime\processes
```

#### Windows (PowerShell)

```powershell
.\find-boomi-components.ps1 <processes_folder>
```

**Example:**
```powershell
.\find-boomi-components.ps1 C:\boomi\Boomi_AtomSphere\Atom\Atom_runtime\processes
```

### Output Format

The script outputs CSV format to stdout with **one line per custom script per owning process**:

```csv
process_id,process_name,component_id,component_name,component_type,shape_name,component,folder
5041adc7-8c59-4628-be7e-625da0f88014,"This is an old process",5041adc7-8c59-4628-be7e-625da0f88014,"This is an old process","process","dataprocess (before documentproperties)","Groovy 1.5","Boomi_Account/Project/Legacy"
5041adc7-8c59-4628-be7e-625da0f88014,"This is an old process",5041adc7-8c59-4628-be7e-625da0f88014,"This is an old process","process","dataprocess (before stop)","Groovy 1.5","Boomi_Account/Project/Legacy"
545ed398-71f8-4683-b26b-5443b3e907f7,"This is a main process",545ed398-71f8-4683-b26b-5443b3e907f7,"This is a main process","process","dataprocess (before documentproperties)","Groovy 2.4","Boomi_Account/PSO/Customers/CDL"
5e102ab6-36c5-477b-89f2-d21ad4c65efd,"Process with Map",a1b2c3d4-5e6f-7890-abcd-ef1234567890,"Customer Mapping","transform.map","Scripting","Groovy 2.4","Boomi_Account/PSO/Customers/CDL"
911c099b-127c-4f50-8fcf-81bb3b88ca86,"This is a sub-process",911c099b-127c-4f50-8fcf-81bb3b88ca86,"This is a sub-process","process","dataprocess (before stop)","Groovy 1.5","Boomi_Account/PSO/Customers/CDL"
f1437ef8-3ef0-4013-a890-c1d65205b9e6,"One process with JavaScript",f1437ef8-3ef0-4013-a890-c1d65205b9e6,"One process with JavaScript","process","dataprocess-JS Shape (before stop)","JavaScript","Boomi_Account/PSO/Customers/CDL"
```

| Column | Description |
|--------|-------------|
| `process_id` | The owning process ID. For processes: same as `component_id`. For maps/functions: resolved by tracing `<References>` chains back to the owning process. When a component is used by multiple processes, one row is emitted per process. |
| `process_name` | The name of the owning process (commas replaced with semicolons for CSV safety) |
| `component_id` | The Boomi component ID (UUID) |
| `component_name` | The component name (commas replaced with semicolons for CSV safety) |
| `component_type` | The component type: `process`, `transform.map`, or `transform.function` |
| `shape_name` | For processes: `{shapetype}-{userlabel} (before {next_shapetype})`. For maps/functions: the FunctionStep name (e.g., "Scripting") |
| `component` | `Groovy 1.5`, `Groovy 2.4`, or `JavaScript` |
| `folder` | The Boomi folder path from the FolderId element |

### Saving Output to File

```bash
# Linux/macOS
./find-boomi-components.sh /path/to/processes > custom-scripts-report.csv

# Windows
find-boomi-components.bat C:\path\to\processes > custom-scripts-report.csv
```

### Script Language Detection

The script detects scripting languages by examining the `language` attribute in:
- `<dataprocessscript>` elements (for processes)
- `<Scripting>` elements (for maps and functions)

**Component Override Handling:** When a `dataprocessscript` has a `componentId` attribute (indicating a referenced script component), the language is extracted from the referenced component's `<ProcessingScript>` element instead of the inline `language` attribute. This ensures the reported language reflects the actual script being used.

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
powershell -File ..\..\utilities\find-boomi-components.ps1 .\processes
```

The test scripts will run the utilities against the sample processes in `src/test/boomi/processes/` and display the results.

### Notes

- **One line per script per owning process**: Each custom script shape generates one row per owning process. Maps and functions used by multiple processes produce multiple rows with different `process_id` values.
- **Deduplication**: Sub-processes and shared maps may appear in multiple parent folders. The script automatically deduplicates results based on process ID, component ID, and shape name.
- **Typical processes folder locations**:
  - Linux: `/data/boomi/Boomi_AtomSphere/Atom/<atom_name>/processes`
  - Windows: `C:\boomi\Boomi_AtomSphere\Atom\<atom_name>\processes`
