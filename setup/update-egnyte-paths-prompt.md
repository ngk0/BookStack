# Claude Code Prompt: Update Equipment Class Egnyte Paths in Bookstack

## Task
Scan the local filesystem for equipment documentation files and update the Bookstack pages with the actual Egnyte paths, replacing all `[PENDING]` placeholders.

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

## Step 1: Find the Egnyte Root

First, locate where Egnyte syncs on this Windows PC. Common locations:
- `C:\Users\<username>\Egnyte\`
- `E:\Egnyte\`
- Check for mounted Egnyte drive letters

Ask me where the Egnyte sync folder is located if you can't find it.

## Step 2: Locate Equipment Documentation

Look for equipment documentation folders. Likely structures:
- `<Egnyte>/Shared/Engineering/Equipment/`
- `<Egnyte>/Shared/E&IC/Equipment Libraries/`
- `<Egnyte>/Private/<company>/Equipment/`

For each equipment class, look for subfolders containing:
- `*.xlsx` files (selection tables)
- `Datasheets/` folder
- `Manuals/` folder
- `CAD/` or `Drawings/` folder
- `Specs/` or `Specifications/` folder

## Step 3: Build Path Mapping

For each equipment library, record the Egnyte web paths. Convert local paths like:
```
C:\Users\joe\Egnyte\Shared\Engineering\Equipment\AB_PLC_IO\Datasheets
```
To Egnyte web paths like:
```
https://laporte.egnyte.com/navigate/folder/<folder-id>
```
Or simple folder paths like:
```
/Shared/Engineering/Equipment/AB_PLC_IO/Datasheets
```

## Step 4: Update Bookstack Pages

Use the Bookstack API to update each page. 

**API Endpoint:** `https://learn.lceic.com/api`

**Authentication:** Token-based
```
Authorization: Token <TOKEN_ID>:<TOKEN_SECRET>
```

**To update a page:**
```
PUT /api/pages/{id}
Content-Type: application/json

{
  "markdown": "<updated markdown content>"
}
```

**Process:**
1. GET the current page content: `GET /api/pages/{id}`
2. Replace `**[PENDING]**` with actual paths in the markdown
3. PUT the updated content back

## Step 5: Format for Egnyte Links

Use this format in the markdown tables:
```markdown
| Master Selection Table | [View in Egnyte](https://laporte.egnyte.com/navigate/folder/xxxxx) |
```
Or if using folder paths:
```markdown
| Datasheets | `/Shared/Engineering/Equipment/AB_PLC_IO/Datasheets` |
```

## Bookstack API Credentials

```
BOOKSTACK_URL=https://learn.lceic.com
BOOKSTACK_TOKEN_ID=NdkVs6LLfMdCZjzA34MdNjRoIG2n6ITr
BOOKSTACK_TOKEN_SECRET=NQEY7UeIROLGGFGnEC5UjTfPcLlpuYF1
```

## Output

After completing, provide a summary:
- Number of pages updated
- Any equipment classes where files were not found
- Any errors encountered

## Notes

- If a documentation folder doesn't exist for an equipment class, leave it as `[PENDING]` or mark as `[NOT FOUND]`
- Prefer Egnyte web links over local file paths
