# FFXI UE5.8.1 Replacement Client - Architecture Design

## Project Overview

A replacement game client for Final Fantasy XI built in Unreal Engine 5.8.1 that connects to the LandSandBoat (LSB) private server. The client reads existing FFXI DAT files for game assets and implements the FFXI network protocol to communicate with the server.

## Goals

1. **Render FFXI zones** using original DAT file geometry and textures
2. **Communicate with LSB server** using the existing FFXI network protocol (no server modifications needed)
3. **Display entities** (players, NPCs, mobs) with animations from DAT files
4. **Handle game events/cutscenes** via the bytecode VM or a simplified interpreter
5. **Play audio** from BGMStream (.bgw) and SE formats
6. **Provide modern rendering** via UE5's Nanite, Lumen, and other features

---

## High-Level Architecture

```
+------------------------------------------------------------------+
|                     UE5 FFXI Client                               |
|                                                                   |
|  +------------------+  +------------------+  +-----------------+  |
|  | DAT Import Layer |  | Network Layer    |  | Game State      |  |
|  |                  |  |                  |  |                 |  |
|  | - VTABLE/FTABLE  |  | - UDP Socket     |  | - Entity Mgr   |  |
|  | - Zone Geometry  |  | - Blowfish Enc   |  | - Inventory     |  |
|  | - Models/Skel    |  | - zlib Compress  |  | - Party/LS      |  |
|  | - Textures(DXT)  |  | - Packet Parse   |  | - Status FX     |  |
|  | - Strings/Dialog |  | - Sequencing     |  | - Combat        |  |
|  | - Event Bytecode |  | - Key Rotation   |  | - Crafting      |  |
|  | - Audio (BGW/SE) |  |                  |  |                 |  |
|  +--------+---------+  +--------+---------+  +--------+--------+  |
|           |                      |                     |          |
|  +--------v----------------------v---------------------v--------+ |
|  |                    Core Game Loop                             | |
|  |                                                              | |
|  |  - Zone Management (load/unload/transition)                  | |
|  |  - Entity Spawning & Update Tick                             | |
|  |  - Event VM Execution                                        | |
|  |  - Player Input -> C2S Packets                               | |
|  |  - S2C Packets -> Game State Updates                         | |
|  +--------------------------------------------------------------+ |
|                                                                   |
|  +--------------------------------------------------------------+ |
|  |                    UE5 Rendering Layer                        | |
|  |                                                              | |
|  |  - Zone Mesh Actors (Procedural Mesh / Static Mesh)          | |
|  |  - Character Actors (Skeletal Mesh + Anim Blueprints)        | |
|  |  - UI (UMG Widgets for chat, menus, inventory)               | |
|  |  - Weather/Lighting (dynamic day/night, weather FX)          | |
|  |  - Audio (MetaSound for BGM/SE)                              | |
|  +--------------------------------------------------------------+ |
+------------------------------------------------------------------+
                              |
                              | UDP (Blowfish + zlib)
                              v
                   +---------------------+
                   |   LSB Server        |
                   | (unmodified)        |
                   +---------------------+
```

---

## Module Breakdown

### Module 1: DAT Import Layer (`Source/FFXIData/`)

Responsible for reading the FFXI installation's DAT files and converting them into UE5-usable assets at runtime or via an Editor plugin.

#### 1.1 File Resolution (`FFXIFileResolver`)
```cpp
// Resolves FileID -> physical path using VTABLE/FTABLE
class UFFXIFileResolver : public UObject
{
    // Reads VTABLE.DAT (1 byte per FileID -> volume/ROM number, 0=unused)
    // Reads FTABLE.DAT (2 bytes per FileID -> file number within ROM subfolder)
    // Supports ROM1-ROM9 with their own VTABLEn/FTABLEn
    
    FString ResolvePath(int32 FileID) const;
    TArray<uint8> ReadFileByID(int32 FileID) const;
    
    FString FFXIInstallPath; // "C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI\"
};
```

#### 1.2 Zone Geometry Parser (`FFXIZoneParser`)
```cpp
// Reads zone DAT files and extracts visual mesh data
// DAT format: 4-byte magic header, then MMB (Model Mesh Block) structures
// Each MMB contains: vertices (pos, normal, UV, color), indices, DXT textures
//
// Reference implementations:
//   - galkareeve/ffxi (C++/OpenGL MapViewer)
//   - FFXI NavMesh Builder (collision extraction to .OBJ)
//   - xi-visualizer (collision to .ximesh)
//
// For collision only: can also read pre-built .ximesh files from server's ximeshes/ folder

struct FFFXIVertex
{
    FVector Position;
    FVector Normal;
    FVector2D UV;
    FColor Color;
};

struct FFFXIMeshBlock
{
    TArray<FFFXIVertex> Vertices;
    TArray<uint16> Indices;
    UTexture2D* Texture; // Decoded from embedded DXT data
    FTransform Placement; // 3x3 rotation + translation from DAT
};

class UFFXIZoneParser : public UObject
{
    // Parse a zone DAT into mesh blocks ready for UE5 ProceduralMesh or StaticMesh
    TArray<FFFXIMeshBlock> ParseZone(int32 ZoneID);
    
    // Parse collision mesh from .ximesh file (simpler, well-documented format)
    TArray<FFFXIMeshBlock> ParseXiMesh(const FString& FilePath);
};
```

#### 1.3 Entity/Character Model Parser (`FFXIModelParser`)
```cpp
// Reads character/NPC/mob model DATs
// Format: Skeletal mesh with bone hierarchy, weighted vertices, animation data
// Noesis has a working FFXI plugin we can reference for format details

class UFFXIModelParser : public UObject
{
    USkeletalMesh* ParseCharacterModel(int32 FileID);
    UAnimSequence* ParseAnimation(int32 FileID, USkeleton* Skeleton);
};
```

#### 1.4 Texture Decoder (`FFXITextureDecoder`)
```cpp
// FFXI textures use DXT1/DXT3/DXT5 compression embedded in DAT files
// UE5 natively supports DXT/BC formats, so we create UTexture2D directly

class UFFXITextureDecoder : public UObject
{
    UTexture2D* DecodeTexture(const TArray<uint8>& RawData, int32 Offset);
};
```

#### 1.5 String/Dialog Parser (`FFXIStringParser`)
```cpp
// FFXI uses a custom text encoding (not standard Shift-JIS or UTF-8)
// Reference: xi-tinkerer, POLUtils encoding tables

class UFFXIStringParser : public UObject
{
    FString DecodeDialog(const TArray<uint8>& RawData);
    TArray<FString> ParseDialogTable(int32 FileID);
    TArray<FString> ParseEntityNames(int32 FileID);
};
```

#### 1.6 Audio Decoder (`FFXIAudioDecoder`)
```cpp
// BGMStream (.bgw): ADPCM-encoded music
// SE: Sound effects in custom format within sound/win/se/ folders

class UFFXIAudioDecoder : public UObject
{
    USoundWave* DecodeBGW(const FString& FilePath);
    USoundWave* DecodeSE(const FString& FilePath);
};
```

---

### Module 2: Network Layer (`Source/FFXINet/`)

Implements the FFXI network protocol to communicate with an unmodified LSB server.

#### 2.1 Transport (`FFXISocket`)
```cpp
// Raw UDP socket with the FFXI framing protocol
// - 28-byte FFXI header (sequence numbers, timestamp)
// - zlib-compressed payload
// - Blowfish encryption
// - MD5 verification
// - Lock-step acknowledgment

class UFFXISocket : public UObject
{
    // Connection lifecycle
    void Connect(const FString& Host, uint16 Port);
    void Disconnect();
    
    // Send unencrypted 0x00A login
    void SendLogin(uint32 CharID, const FString& Name, const TArray<uint8>& SessionKey);
    
    // Send encrypted packet
    void SendPacket(const FFFXIPacket& Packet);
    
    // Receive and decrypt
    TArray<FFFXIPacket> ReceivePackets();
    
    // Key management
    void InitBlowfish(const TArray<uint8>& SessionKey);
    void IncrementBlowfish(); // Called on zone transition (0x00B received)
    
private:
    FSocket* UDPSocket;
    FBlowfishContext CurrentKey;
    FBlowfishContext PreviousKey;
    uint16 ServerPacketID;  // Our sequence number
    uint16 ClientPacketID;  // Last ACK'd from server
};
```

#### 2.2 Packet Definitions (`FFXIPackets`)
```cpp
// Each packet type maps to a struct
// S2C (Server-to-Client): ~130 types that we must handle
// C2S (Client-to-Server): ~120 types that we send

// Base packet: 4 bytes header (9-bit type, 7-bit size in 2-byte units, 16-bit sequence)
struct FFFXIPacket
{
    uint16 Type;     // 9-bit packet ID
    uint16 Size;     // Actual byte size
    uint16 Sequence;
    TArray<uint8> Data;
};

// Critical S2C packets to implement first:
// 0x00A - Login response (zone, position, weather, music, stats)
// 0x00B - Zone/Logout (target zone IP:port, triggers key rotation)
// 0x00D - PC entity update (players)
// 0x00E - NPC/Mob entity update (position, model, flags, HP%)
// 0x028 - Battle action (damage, healing, abilities)
// 0x029 - Battle message
// 0x032 - Event start (cutscene trigger)
// 0x034 - Event numeric params
// 0x01F - Item list
// 0x050 - Equipment list
// 0x05E - Conquest data
// 0x05F - Music change
// 0x057 - Weather change
// 0x061 - Character status (buffs, HP/MP/TP)
// 0x067/068 - Entity update (extended)

// Critical C2S packets:
// 0x00A - Login request
// 0x00C - Game OK (zone loaded confirmation)
// 0x011 - Zone transition confirmation
// 0x015 - Position update (sent every ~1s)
// 0x01A - Action request (attack, magic, ability, item use)
// 0x05B - Event end (with result)
// 0x0B5 - Chat message
```

#### 2.3 Packet Handler Registry (`FFXIPacketHandler`)
```cpp
// Dispatches received S2C packets to appropriate game systems

class UFFXIPacketHandler : public UObject
{
    // Register handlers per packet type
    void RegisterHandler(uint16 PacketType, TFunction<void(const FFFXIPacket&)> Handler);
    
    // Process received packets
    void ProcessPackets(const TArray<FFFXIPacket>& Packets);
};
```

---

### Module 3: Game State (`Source/FFXIGame/`)

Manages all game state that the server communicates.

#### 3.1 Entity Manager (`FFXIEntityManager`)
```cpp
// Tracks all entities in the current zone (players, NPCs, mobs, pets, trusts)
// Entity updates come via 0x00D (PC) and 0x00E (NPC/Mob) packets

struct FFFXIEntity
{
    uint32 ServerID;      // Global unique ID
    uint16 TargetIndex;   // Local zone index (0-2303)
    FVector Position;
    float Rotation;
    uint16 ModelID;
    uint16 Look[9];       // Equipment appearance slots
    FString Name;
    uint8 HPPercent;
    uint8 Animation;
    uint8 Speed;
    // ... flags, status, etc.
};

class UFFXIEntityManager : public UObject
{
    void SpawnEntity(const FFFXIEntity& Data);
    void UpdateEntity(uint16 TargetIndex, const FFFXIPacket& UpdatePacket);
    void DespawnEntity(uint16 TargetIndex);
    
    FFFXIEntity* GetEntity(uint16 TargetIndex);
    FFFXIEntity* GetPlayerEntity(); // TargetIndex from 0x00A login
    
    TMap<uint16, FFFXIEntity> Entities;
};
```

#### 3.2 Zone Manager (`FFXIZoneManager`)
```cpp
// Handles zone loading, transitions, and zone-specific state

class UFFXIZoneManager : public UObject
{
    void LoadZone(uint16 ZoneID);
    void UnloadCurrentZone();
    void BeginZoneTransition(uint16 TargetZoneID, const FString& ServerIP, uint16 ServerPort);
    
    uint16 CurrentZoneID;
    FString CurrentZoneName;
    // Weather, music, time-of-day state
};
```

#### 3.3 Event System (`FFXIEventSystem`)
```cpp
// Option A: Implement FFXI bytecode VM interpreter (complex but faithful)
// Option B: Server-driven approach where we handle event packets generically
//
// For MVP: Option B - handle 0x032/0x033/0x034 packets as instructions to show
// dialog, move camera, play animations, etc. Send back 0x05B/0x05C with results.
//
// Long term: Option A - full VM interpreter using atom0s/XiEvents documentation

class UFFXIEventSystem : public UObject
{
    void StartEvent(uint16 EventID, uint32 EntityID, const TArray<uint32>& Params);
    void HandleEventUpdate(uint16 EventID, uint32 Result);
    void EndEvent(uint16 EventID, uint32 Result);
    
    // Dialog display
    void ShowDialog(const FString& Text, const TArray<FString>& Options);
    
    bool bInEvent;
    uint16 CurrentEventID;
};
```

---

### Module 4: UE5 Rendering (`Source/FFXIRenderer/`)

#### 4.1 Zone Actor (`AFFXIZoneActor`)
```cpp
// Spawned when a zone loads. Creates mesh components from parsed DAT data.
// Option A: UProceduralMeshComponent (runtime generation, flexible)
// Option B: Convert DATs to UStaticMesh at editor time (better performance)
//
// Recommended: Hybrid - Editor tool pre-converts DATs to .uasset StaticMeshes,
// but runtime fallback via ProceduralMesh for dynamic content.

UCLASS()
class AFFXIZoneActor : public AActor
{
    GENERATED_BODY()
    
    void LoadFromDAT(uint16 ZoneID);
    void LoadFromXiMesh(const FString& XiMeshPath); // Collision only
    
    UPROPERTY()
    TArray<UStaticMeshComponent*> MeshComponents;
};
```

#### 4.2 Entity Actor (`AFFXIEntityActor`)
```cpp
// Visual representation of an in-game entity

UCLASS()
class AFFXIEntityActor : public ACharacter
{
    GENERATED_BODY()
    
    void UpdateFromServerData(const FFFXIEntity& Data);
    void PlayAnimation(uint8 AnimationID);
    void SetEquipmentLook(const uint16 Look[9]);
    
    UPROPERTY()
    USkeletalMeshComponent* ModelMesh;
};
```

#### 4.3 Weather & Lighting (`AFFXIWeatherController`)
```cpp
// Vanadiel time: 25x real time (1 Vanadiel day = ~57.6 real minutes)
// Weather affects lighting, particle effects, gameplay

UCLASS()
class AFFXIWeatherController : public AActor
{
    void SetWeather(uint16 WeatherID);
    void SetVanadielTime(uint32 GameTime);
    void UpdateDayNightCycle(float DeltaTime);
};
```

---

## Implementation Phases

### Phase 1: Foundation (Weeks 1-4)
- [ ] Set up UE5.8.1 C++ project structure
- [ ] Implement `FFXIFileResolver` (VTABLE/FTABLE reading)
- [ ] Implement basic `FFXISocket` (UDP, Blowfish, zlib)
- [ ] Send 0x00A login, receive 0x00A response
- [ ] Parse zone ID and position from login response
- [ ] Display "connected" state in a basic UMG widget

### Phase 2: Zone Rendering (Weeks 5-8)
- [ ] Port zone collision mesh parser from NavMesh Builder / xi-visualizer
- [ ] Render .ximesh collision geometry as ProceduralMesh (wireframe initially)
- [ ] Implement full zone DAT visual mesh parser (MMB format)
- [ ] Decode DXT textures and apply to mesh
- [ ] Basic camera controller (FFXI-style 3rd person)
- [ ] Load zone on login, apply player position

### Phase 3: Entity System (Weeks 9-12)
- [ ] Parse 0x00D/0x00E packets for entity spawn/update/despawn
- [ ] Spawn placeholder actors at entity positions
- [ ] Implement entity movement interpolation
- [ ] Parse character model DATs (basic mesh, no animation yet)
- [ ] Equipment appearance (Look[] array -> model composition)

### Phase 4: Gameplay Core (Weeks 13-20)
- [ ] Position update sending (C2S 0x015)
- [ ] Chat system (send 0x0B5, receive 0x017)
- [ ] Target system and action commands (0x01A)
- [ ] Basic event handling (0x032 -> dialog display -> 0x05B)
- [ ] Inventory display (0x01F packets)
- [ ] Status effects and HP/MP/TP display

### Phase 5: Polish (Weeks 21+)
- [ ] Skeletal animation for characters/NPCs
- [ ] Audio (BGMStream music, sound effects)
- [ ] Weather and day/night cycle
- [ ] Full UI (menus, map, equipment, etc.)
- [ ] Event VM interpreter for cutscenes
- [ ] Particle effects (spells, abilities)

---

## Key Design Decisions

### 1. DAT Reading Strategy
**Decision**: Read DATs at runtime with an Editor-time pre-import option.
**Rationale**: Keeps the project simple to distribute (just point at FFXI install), but allows offline pre-processing for performance. Users need a valid FFXI installation.

### 2. Coordinate System
**Decision**: Transform FFXI coordinates to UE5 at the import boundary.
- FFXI uses negative-Y-up, UE5 uses Z-up
- FFXI grid cell = 4.0 yalms, 1 yalm ~ 1 meter in UE5
- Transform: `UE5.X = FFXI.X`, `UE5.Y = FFXI.Z`, `UE5.Z = -FFXI.Y`

### 3. Network Thread
**Decision**: Dedicated network thread separate from game thread.
**Rationale**: UDP receive/decrypt/decompress must not block rendering. Use UE5's `FRunnable` thread with a lock-free queue to pass parsed packets to the game thread.

### 4. Event System Approach
**Decision**: Start with server-packet-driven approach (no VM), add VM later.
**Rationale**: The original client VM executes bytecode that mostly controls camera, entity movement, and dialog display. For MVP, we can handle the server's event packets directly and show basic dialog/choices. Full cutscene fidelity requires the VM but isn't needed initially.

### 5. No Server Modifications
**Decision**: The UE5 client MUST work with unmodified LSB server.
**Rationale**: This is a client replacement, not a protocol change. The server doesn't need to know it's talking to UE5 instead of the original client.

---

## Dependencies and Tools

| Tool/Library | Purpose | Integration |
|---|---|---|
| UE5.8.1 | Game engine | Base platform |
| OpenSSL/LibreSSL | Blowfish encryption | Linked via UE5 module |
| zlib | Packet compression | Already in UE5 (FCompression) |
| MD5 | Packet verification | UE5's FMD5Hash |
| FFXI Installation | Game asset source | Read-only file path reference |

---

## File Structure (UE5 Project)

```
FFXIClient/
├── Source/
│   ├── FFXIData/          # DAT file parsing and asset loading
│   │   ├── FFXIFileResolver.h/cpp
│   │   ├── FFXIZoneParser.h/cpp
│   │   ├── FFXIModelParser.h/cpp
│   │   ├── FFXITextureDecoder.h/cpp
│   │   ├── FFXIStringParser.h/cpp
│   │   └── FFXIAudioDecoder.h/cpp
│   ├── FFXINet/           # Network protocol implementation
│   │   ├── FFXISocket.h/cpp
│   │   ├── FFXIBlowfish.h/cpp
│   │   ├── FFXIPacket.h/cpp
│   │   ├── FFXIPacketHandler.h/cpp
│   │   └── Packets/       # Per-packet-type structs
│   │       ├── S2C_Login.h
│   │       ├── S2C_EntityUpdate.h
│   │       ├── S2C_Event.h
│   │       ├── C2S_Login.h
│   │       ├── C2S_Position.h
│   │       └── ...
│   ├── FFXIGame/          # Game state management
│   │   ├── FFXIEntityManager.h/cpp
│   │   ├── FFXIZoneManager.h/cpp
│   │   ├── FFXIEventSystem.h/cpp
│   │   ├── FFXIInventory.h/cpp
│   │   ├── FFXIPlayerState.h/cpp
│   │   └── FFXIChatSystem.h/cpp
│   └── FFXIRenderer/      # UE5 visual representation
│       ├── FFXIZoneActor.h/cpp
│       ├── FFXIEntityActor.h/cpp
│       ├── FFXIWeatherController.h/cpp
│       ├── FFXIPlayerController.h/cpp
│       └── FFXIGameMode.h/cpp
├── Content/
│   ├── UI/                # UMG widget blueprints
│   ├── Materials/         # Base materials for DAT textures
│   └── Maps/              # Persistent level(s)
├── Config/
│   └── FFXIClient.ini     # FFXI install path, server IP, etc.
└── Plugins/
    └── FFXIEditor/        # Editor tools for DAT preview/import
```

---

## References

- [atom0s/XiPackets](https://github.com/atom0s/XiPackets) - Packet format documentation
- [atom0s/XiEvents](https://github.com/atom0s/XiEvents) - Event VM and bytecode documentation
- [InoUno/xi-tinkerer](https://github.com/InoUno/xi-tinkerer) - DAT file format parser (Rust)
- [InoUno/xi-visualizer](https://github.com/InoUno/xi-visualizer) - Zone mesh extraction (TypeScript)
- [LandSandBoat/FFXI-NavMesh-Builder](https://github.com/LandSandBoat/FFXI-NavMesh-Builder-) - Collision mesh to OBJ
- [galkareeve/ffxi](https://github.com/galkareeve/ffxi) - Zone DAT rendering (C++/OpenGL)
- [Windower/ResourceExtractor](https://github.com/Windower/ResourceExtractor) - Game resource extraction
- [Maphesdus/FFXI_MapViewer](https://github.com/Maphesdus/FFXI_MapViewer) - Updated MapViewer fork
- LSB Server Source (`src/map/packets/`) - Definitive packet structure reference
- LSB Server Source (`src/map/ximesh/`) - XiMesh binary format reference
