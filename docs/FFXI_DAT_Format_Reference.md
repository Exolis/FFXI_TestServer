# FFXI DAT File Format Reference

## File Resolution System

### VTABLE / FTABLE

Every game resource is addressed by a **FileID** (0-109,700). The client resolves FileIDs to physical files using two index tables:

```
VTABLE.DAT  - 109,701 bytes (1 byte per FileID)
FTABLE.DAT  - 219,402 bytes (2 bytes per FileID, uint16 LE)
```

**Resolution algorithm:**
```
volume = VTABLE[FileID]
  -> 0 = file does not exist
  -> 1 = file is in ROM/
  -> n = file is in ROM{n}/  (for expansion tables)

fileNum = FTABLE[FileID * 2] as uint16 little-endian
path = ROM/{subfolder}/{fileNum}.DAT
```

For expansions (ROM2-ROM9), each has its own VTABLEn/FTABLEn with the same FileID space.

**ROM folder structure:**
- `ROM/` (main, 49,317 DATs across 387 numbered subfolders, 7.54 GB)
- `ROM2/` through `ROM9/` (expansions, ~2.81 GB combined)
- Each numbered subfolder (0-387) contains DAT files numbered 0-127

### Total game data:
- 52,885 DAT files
- ~10.35 GB total ROM data
- 109,701 addressable FileID slots

---

## DAT File Types

### Zone Geometry DATs

**Header**: 4-byte ASCII magic (e.g., `f_sa`, `f_el`, `f_al`, `r_2s`)

**Structure** (from galkareeve/ffxi and NavMesh Builder):
```
[4-byte magic header + version bytes]
[Zone header with resource counts]
[MMB (Model Mesh Block) table]
  Each MMB contains:
    - Vertex data: position (float3), normal (float3), UV (float2), color (RGBA)
    - Index data: uint16 triangle indices
    - Embedded DXT textures (DXT1/DXT3/DXT5)
    - Placement transform (rotation matrix + translation)
[Submodel references (doors, elevators, etc.)]
```

**Known magic headers:**
| Magic | Description |
|-------|-------------|
| `f_sa` | Field/San d'Oria zone geometry |
| `f_el` | Field/Elvaan area geometry |
| `f_al` | Field/Al Zahbi area geometry |
| `syst` | System resources |
| `menu` | Menu/UI resources |
| `r_2s` | Resource 2-sided model |
| `4hm_` | Character model (Hume Male?) |
| `4gl_` | Character model (Galka?) |
| `lobb` | Lobby/title screen |
| `fen_` | Fence/boundary data |
| `brm_` | Unknown resource type |

### XiMesh Format (Pre-processed Collision)

The LSB server uses `.ximesh` files (zlib-compressed binary) for navmesh/collision. Format:

```
After decompression:
  [XimeshHeader]           20 bytes
    uint16 gridWidth
    uint16 gridHeight
    uint32 blockSectionOffset
    uint32 placementSectionOffset
    uint16 blockCount
    uint16 placementCount
    uint32 wideSearch

  [uint32 x cellCount]     Cell offset table

Cell (at offset):
  [XimeshCellHeader]       6 bytes (reserved u32 + entryCount u16)
  [XimeshCellEntry x N]    8 bytes each (blockOffset + placementOffset)

Block (at blockOffset):
  uint16 vertexCount
  uint16 triangleCount
  uint16 barrierFlag
  uint16 pad
  float[vertexCount * 3]   Local-space XYZ vertices
  uint16[triCount * 3]     Index buffer (4-byte aligned)
  uint8[triCount]          Triangle metadata (4-bit material, 1-bit barrier)

Placement (at placementOffset):
  uint32 flags             (roofed bit, mapId bits)
  float[9]                 3x3 rotation matrix (column-major)
  float[3]                 Translation vector
```

**Grid**: 4.0 world units (yalms) per cell, centered at world origin.

### String/Dialog DATs

Custom text encoding with control codes. Multiple types:
- Zone dialog tables (NPC text, system messages)
- Entity name lists
- Item descriptions
- d_msg (general game messages)
- XISTRING format

**Encoding**: Not standard Shift-JIS or UTF-8. POLUtils and xi-tinkerer have conversion tables.

### Event DATs (Bytecode)

One per zone. Contains compiled bytecode for the event VM.

**Structure**:
```
[Event offset table]     Array of uint32 offsets to each event's bytecode
[Event ID table]         Array of event IDs
[Reference/Immediate data table]  Static parameters
[Bytecode data]          The actual VM instructions
```

**VM Architecture** (from atom0s/XiEvents):
- 16 ReqStack entries with priority-based execution
- Stack-based jump/return system
- Opcodes control: entity movement, camera, dialog, animation, fading, waiting
- Each entity has its own `xievent_t` state block when in an event

### Entity Model DATs

Character/NPC/mob 3D models with skeletal animation data.

**Types by Look size:**
- `MODEL_STANDARD` (0) - Single mesh ID
- `MODEL_EQUIPPED` (1) - 9-slot equipment composition (face, head, body, hands, legs, feet, main, sub, ranged)
- `MODEL_DOOR` (3) - Door with DoorId
- `MODEL_SHIP` (4) - Ship/transport
- `MODEL_ELEVATOR` (5) - Elevator
- `MODEL_CHOCOBO` (6) - Mount

### Texture Format

Embedded within model/zone DATs as DDS-compatible data:
- DXT1 (4:1 compression, 1-bit alpha)
- DXT3 (4:1 compression, 4-bit explicit alpha)
- DXT5 (4:1 compression, interpolated alpha)

Can be extracted with standard DDS decoders.

### Audio Formats

**Music** (`sound/win/music/data/music###.bgw`):
- BGMStream format
- Header: `BGMStream\0` (10 bytes)
- ADPCM-encoded audio data
- Multiple channels/layers

**Sound Effects** (`sound/win/se/se###/`):
- Custom format, per-zone sound effect packs

---

## Zone-to-FileID Mapping

The client has internal tables mapping zone IDs to their required FileIDs. For each zone, multiple DATs are loaded:

1. **Zone geometry/visual model** (the large "field" DAT)
2. **Collision mesh** (separate from visual in some cases)
3. **Entity model list** (available NPCs/mobs for this zone)
4. **Dialog/string table** (zone-specific NPC text)
5. **Event bytecode** (cutscene scripts for this zone)
6. **Zone map texture** (the minimap image)

The NavMesh Builder project has a `ZoneList.dat` parser that maps zone names/IDs to their DAT locations. The galkareeve MapViewer also hardcodes these mappings.

---

## Coordinate System

- **FFXI**: Y-axis is altitude (negative-Y = up), X/Z are horizontal
- **Grid cell size**: 4.0 yalms (world units)
- **1 yalm**: Approximately 1 meter

**Conversion to UE5 (Z-up):**
```
UE5.X =  FFXI.X
UE5.Y =  FFXI.Z  
UE5.Z = -FFXI.Y
Scale: 1 yalm = 100 UE5 units (1 meter at default scale)
```

---

## Patching System

`patch.cfg` in the FFXI root tracks which DATs have been updated:
```
file ROM/175/52.DAT {
  30210706_0 76048 -139777 -116664851 30210706_0/Direct/ROM/175/52.DAT.slc 20862
}
```

Format: `patch_version size checksum crc32 patch_url compressed_size`
- `.slc` = direct replacement patch
- `.olc` = delta/indirect patch

`file.txt` contains a manifest: `hash:size:path` for every DAT file.
