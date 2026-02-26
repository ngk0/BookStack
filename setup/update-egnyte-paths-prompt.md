# Claude Code Prompt: Update Equipment Class Egnyte Paths in Bookstack

## Task
Scan the local filesystem for equipment documentation files and update the Bookstack pages with the actual Egnyte paths, replacing all `[PENDING]` placeholders.

## Step 0: Clone the Repository

First, clone the eic-equip repository to the designated path:

```powershell
cd "I:\LCC\06-Projects\9 - E&IC\BOD Equip"
git clone https://github.com/ngk0/eic-equip.git .
```

Or if already cloned, pull latest:
```powershell
cd "I:\LCC\06-Projects\9 - E&IC\BOD Equip"
git pull
```

**Working Directory:** `I:\LCC\06-Projects\9 - E&IC\BOD Equip`

## Context
There are 22 equipment class pages in Bookstack that need Egnyte file paths populated. Each page has placeholder tables for:
- Selection Spreadsheets (Master Selection Table, Quick Reference Guide)
- Product Documentation (Datasheets, Installation Manuals, User Guides, Brochures)
- Design Resources (CAD Blocks/Symbols, Specifications, Application Notes)

## Equipment Libraries to Map

| Library Folder Name | Bookstack Page ID | Display Name |
|---------------------|-------------------|--------------|
| AB_PLC_IO_Library | 1872 | Allen-Bradley PLC & I/O Systems |
| CENTERLINE2100_MCC_Library | 1873 | CENTERLINE 2100 Motor Control Centers |
| Conduit_Selection_Library | 1874 | Conduit Selection Guide |
| E300_FVNR_Starter_Library | 1875 | E300 FVNR Motor Starters |
| Eaton_BLine_CableTray_Library | 1876 | Eaton B-Line Cable Tray Systems |
| Eaton_EmergencyInverter_Library | 1877 | Eaton Emergency Inverters |
| Eaton_SmartRack_Library | 1878 | Eaton SmartRack Enclosures |
| Eaton_UPS_Library | 1879 | Eaton UPS Systems |
| GP_Disconnect_Library | 1880 | General Purpose Disconnect Switches |
| Hubbell_Receptacle_Library | 1881 | Hubbell Electrical Receptacles |
| IFM_IOLink_Library | 1882 | IFM IO-Link Masters & I/O |
| Kohler_Generator_ATS_Library | 1883 | Kohler Generators & ATS |
| MSA_GasDetection_Library | 1884 | MSA Gas Detection Systems |
| Maddox_Transformer_Library | 1885 | Maddox Transformers |
| PowerFlex525_VFD_Library | 1886 | PowerFlex 525 VFDs |
| PowerFlex755_VFD_Library | 1887 | PowerFlex 755 VFDs |
| SMCFlex_SoftStarter_Library | 1888 | SMC Flex Soft Starters |
| SquareD_Panelboard_Library | 1889 | Square D Panelboards |
| Stratix_Switch_Library | 1890 | Stratix Industrial Ethernet Switches |
| VFD_Disconnect_Library | 1891 | VFD-Rated Disconnects |
| Wire_Cable_Library | 1892 | Wire & Cable Selection |
| nVent_Raychem_HeatTrace_Library | 1893 | nVent Raychem Heat Trace |

## Step 1: Scan Equipment Library Folders

Each library folder in `I:\LCC\06-Projects\9 - E&IC\BOD Equip` contains:
- `README.md` - Library documentation
- `Unified_Master_Selection_Table.xlsx` or similar - Selection spreadsheet
- Possibly subfolders for datasheets, manuals, etc.

Scan each library folder and note what files/folders exist.

## Step 2: Find Egnyte Documentation

Look for corresponding Egnyte folders. The Egnyte sync location is likely:
- `C:\Users\<username>\Egnyte\`
- Or a mapped drive like `E:\` or `Y:\`

Search for equipment documentation folders containing:
- Datasheets
- Manuals/Installation Guides
- CAD blocks/symbols
- Specifications

Ask me where Egnyte syncs if you can't find it.

## Step 3: Build Path Mapping

For each equipment library, map local Egnyte paths to web URLs:

Local path example:
```
C:\Users\joe\Egnyte\Shared\Engineering\Equipment\AB_PLC_IO\Datasheets
```

Convert to Egnyte web path:
```
/Shared/Engineering/Equipment/AB_PLC_IO/Datasheets
```

## Step 4: Update Bookstack Pages

**API Endpoint:** `https://learn.lceic.com/api`

**Authentication:**
```
Authorization: Token NdkVs6LLfMdCZjzA34MdNjRoIG2n6ITr:NQEY7UeIROLGGFGnEC5UjTfPcLlpuYF1
```

**Process for each page:**
1. `GET /api/pages/{id}` - Get current content
2. Replace `**[PENDING]**` with actual Egnyte paths
3. `PUT /api/pages/{id}` with `{"markdown": "<updated content>"}`

## Step 5: Link Format

Use this format in markdown tables:
```markdown
| Master Selection Table | `/Shared/Engineering/Equipment/AB_PLC_IO/Selection_Table.xlsx` |
| Datasheets | `/Shared/Engineering/Equipment/AB_PLC_IO/Datasheets/` |
```

Or with clickable links:
```markdown
| Datasheets | [Open Folder](https://laporte.egnyte.com/app/index.do#storage/files/1/Shared/Engineering/Equipment/AB_PLC_IO/Datasheets) |
```

## Output

Provide summary:
- Pages updated
- Equipment classes with missing documentation
- Any errors

## Notes

- Leave as `**[PENDING]**` if documentation doesn't exist yet
- The repo path is: `I:\LCC\06-Projects\9 - E&IC\BOD Equip`
