# Claude Code Prompt: Update Equipment Class Egnyte Paths in Bookstack

## Task
Scan the Egnyte folder for equipment documentation files and update the Bookstack pages with the actual paths, replacing all `[PENDING]` placeholders.

## Egnyte Folder Location

```
I:\LCC\06-Projects\9 - E&IC\BOD Equip
```

Scan this folder for equipment documentation organized by library/manufacturer.

## Context
There are 22 equipment class pages in Bookstack that need Egnyte file paths populated. Each page has placeholder tables for:
- Selection Spreadsheets (Master Selection Table, Quick Reference Guide)
- Product Documentation (Datasheets, Installation Manuals, User Guides, Brochures)
- Design Resources (CAD Blocks/Symbols, Specifications, Application Notes)

## Equipment Libraries to Map

| Library Name | Bookstack Page ID | Display Name |
|--------------|-------------------|--------------|
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

## Step 1: Scan the Egnyte Folder

Scan `I:\LCC\06-Projects\9 - E&IC\BOD Equip` and list all subfolders and files.

Look for folders matching the library names above, or manufacturer-based organization like:
- `Allen-Bradley/` or `Rockwell/`
- `Eaton/`
- `Square D/` or `Schneider/`
- `Kohler/`
- `IFM/`
- etc.

For each equipment class, find:
- Selection spreadsheets (`.xlsx` files)
- Datasheets folder
- Manuals folder
- CAD/drawings folder
- Specifications folder

## Step 2: Map Paths

For each equipment library, record the Egnyte paths found. Convert Windows paths to Egnyte web paths:

Windows path:
```
I:\LCC\06-Projects\9 - E&IC\BOD Equip\Allen-Bradley\PLC_IO\Datasheets
```

Egnyte path (remove drive letter, use forward slashes):
```
/LCC/06-Projects/9 - E&IC/BOD Equip/Allen-Bradley/PLC_IO/Datasheets
```

## Step 3: Update Bookstack Pages

**API Endpoint:** `https://learn.lceic.com/api`

**Authentication:**
```
Authorization: Token NdkVs6LLfMdCZjzA34MdNjRoIG2n6ITr:NQEY7UeIROLGGFGnEC5UjTfPcLlpuYF1
```

**For each page:**
1. `GET /api/pages/{id}` - Get current markdown content
2. Replace each `**[PENDING]**` with the actual Egnyte path
3. `PUT /api/pages/{id}` with `{"markdown": "<updated content>"}`

## Step 4: Path Format in Markdown

Use this format in the tables:
```markdown
| Master Selection Table | `/LCC/06-Projects/9 - E&IC/BOD Equip/Allen-Bradley/PLC_IO/Selection_Table.xlsx` |
| Datasheets | `/LCC/06-Projects/9 - E&IC/BOD Equip/Allen-Bradley/PLC_IO/Datasheets/` |
```

## Output

After completing, provide:
- Number of pages updated
- List of equipment classes where documentation was NOT found
- Any errors encountered

## Notes

- If a folder/file doesn't exist for an equipment class, leave it as `**[PENDING]**`
- Use forward slashes in paths for consistency
- The Egnyte root is: `I:\LCC\06-Projects\9 - E&IC\BOD Equip`
