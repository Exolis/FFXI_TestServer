# FFXI Network Protocol Reference (for LSB Server)

## Transport Layer

- **Protocol**: UDP
- **Default Port**: 54230 (map server, configurable via `network.MAP_PORT`)
- **Packet Model**: Each UDP datagram = one "big packet" containing compressed/encrypted bundle of "small packets"
- **Reliability**: Simple lock-step acknowledgment (not TCP-style windowing)

---

## Wire Format

### Outbound (Client → Server)

```
[28-byte FFXI Header]
[zlib-compressed payload of concatenated small packets]
[4-byte compressed size]
[16-byte MD5 hash]
```

Then the entire payload after byte 28 is **Blowfish-encrypted** (64-bit blocks).

Exception: The initial 0x00A login packet is sent **unencrypted** (validated by its own checksum).

### Inbound (Server → Client)

Same format. Client must:
1. Verify the 28-byte header sequence numbers
2. Blowfish-decrypt payload (everything after byte 28)
3. Verify MD5 hash
4. zlib-decompress payload
5. Parse concatenated small packets from decompressed data

---

## FFXI Header (28 bytes / 0x1C)

```
Offset  Size   Field
0x00    uint16 client_packet_id (client's sequence number / server's ACK of last received)
0x02    uint16 server_packet_id (server's sequence number / client's ACK)
0x04    uint32 unknown/flags
0x08    uint32 timestamp (earth_time)
0x0C-1B        (additional framing data)
```

---

## Small Packet Format

Each "small packet" within the decompressed payload:

```
Offset  Size   Field
0x00    uint16 Bits 0-8: Packet Type ID (9 bits, & 0x1FF)
               Bit 9-15 of byte 1: Size in 2-byte units ((byte1 & 0xFE) * 2 = actual bytes)
0x02    uint16 Sequence number
0x04+          Packet-specific data
```

**Max small packet size**: 511 bytes (0x1FF)

---

## Encryption: Blowfish

- **Key source**: `accounts_sessions.session_key` in database (20 bytes / 5 uint32)
- **Block size**: 64-bit (two 32-bit words per cipher operation)
- **Cipher scope**: Everything after the 28-byte header
- **Key rotation**: On zone transition, after server sends 0x00B, both sides increment the key
- **Fallback**: If decryption fails during zone transition, server tries the previous key

### States
```
BLOWFISH_WAITING      → Initial connection, waiting for 0x00A
BLOWFISH_SENT         → Key set up, awaiting confirmation
BLOWFISH_ACCEPTED     → Normal encrypted communication
BLOWFISH_PENDING_ZONE → Zone transition in progress, key about to change
```

---

## Connection Flow

### Login Sequence
```
1. Client obtains session_key from login server (separate process)
2. Client sends UNENCRYPTED 0x00A to map server
   - Contains: CharID, Name, Account, Ticket, Look, Version, Language
   - Has own checksum byte for validation
3. Server loads session_key from DB, initializes Blowfish
4. Server sends ENCRYPTED 0x00A response
   - Contains: Position, ZoneID, Weather, Music, Stats, Time, Config
5. Client sends 0x00C (Game OK - confirms zone loaded)
6. Client sends 0x011 (Zone transition complete)
7. Normal gameplay begins (encrypted bidirectional)
```

### Zone Transition
```
1. Server sends 0x00B with target zone IP:Port and LogoutState=ZONECHANGE
2. Server increments Blowfish key, saves previous
3. Client reconnects to new zone server
4. Client sends fresh UNENCRYPTED 0x00A
5. Repeat from step 3 of login sequence
```

---

## Critical S2C Packets (Server → Client)

### 0x00A - Login Response
```cpp
struct {
    GP_SERV_POS_HEAD PosHead;   // Entity ID, position, rotation, speed, HP%, animation
    uint32 ZoneNo;              // Zone ID
    uint32 ntTimeSec;           // Earth timestamp
    uint32 GameTime;            // Vanadiel timestamp
    uint16 GrapIDTbl[9];        // Equipment appearance (face|race, head, body, hands, legs, feet, main, sub, ranged)
    uint16 MusicNum[5];         // Day music, Night music, Solo battle, Party battle, Mount
    uint16 MapNumber;           // Map/boundary
    uint16 WeatherNumber;       // Current weather
    uint32 WeatherTime;         // Weather change timestamp
    SAVE_LOGIN_STATE LoginState; // MYROOM or GAME
    char name[16];              // Character name
    uint32 PlayTime;            // Total play time in seconds
    GP_MYROOM_DANCER_PKT Dancer; // Jobs, levels, stats
    SAVE_CONF_PKT ConfData;     // Player config
};
```

### 0x00E - NPC/Mob Entity Update
```cpp
struct {
    uint32 UniqueNo;         // Global entity ID
    uint16 ActIndex;         // Target index (0-2303)
    sendflags_t SendFlg;     // Which fields are populated (Position, ClaimStatus, General, Name, Model, Despawn)
    uint8 dir;               // Rotation (0-255 = 0-360 degrees)
    float x, z, y;           // Position (z = altitude in FFXI)
    flags0_t Flags0;         // MovTime, RunMode, GroundFlag, KingFlag, FaceTarget
    uint8 Speed, SpeedBase;
    uint8 Hpp;               // HP percentage
    uint8 server_status;     // Animation state
    flags1_t Flags1;         // MonsterFlag, HideFlag, SleepFlag, LfgFlag, Gender, etc.
    flags2_t Flags2;         // RGB color, PvP, Shadow, Charm, Named flags
    flags3_t Flags3;         // Trust, Pet, Ballista, MonStat flags
    uint32 BtTargetID;       // Battle target
    uint16 SubKind:3;        // Model type (determines Data[] interpretation)
    uint16 Status:13;
    uint8 Data[18];          // Model data (varies by SubKind)
};
```

### 0x028 - Battle Action
Contains damage numbers, ability effects, healing, etc. Variable-length with multiple targets.

### 0x032 - Event Start
Triggers a cutscene/NPC interaction. Client should display dialog, move camera, etc.

### 0x05F - Music Change
```cpp
struct {
    uint16 MusicType;  // 0=day, 1=night, 2=solo battle, 3=party battle
    uint16 MusicID;    // BGM track number
};
```

### 0x057 - Weather Change
```cpp
struct {
    uint16 WeatherID;  // Weather type enum
    uint32 ChangeTime; // Vanadiel timestamp of change
};
```

---

## Critical C2S Packets (Client → Server)

### 0x00A - Login Request (UNENCRYPTED)
```cpp
struct GP_CLI_LOGIN {
    uint16 id;          // 0x00A
    uint16 size;
    uint32 UniqueNo;    // Char ID
    char sName[16];     // Character name
    char sAccunt[16];   // Account name
    uint32 Ticket;      // Session ticket
    uint16 GrapIDTbl[9]; // Appearance
    uint8 uCliLang;     // Language (0=JP, 1=EN, 2=EU)
    // ... platform info, version
    uint8 LoginPacketCheck; // Checksum of packet body
};
```

### 0x015 - Position Update
```cpp
struct {
    float x, z, y;       // Current position
    uint8 dir;           // Rotation
    uint16 TargetIndex;  // Current target
    uint32 timestamp;    // Client timestamp
    // Movement flags
};
```
Sent approximately every 1 second during movement, or on significant state change.

### 0x01A - Action Request
```cpp
struct {
    uint16 TargetIndex;  // Target entity
    uint16 ActionCategory; // Attack, Magic, Ability, Item, etc.
    uint16 ActionID;     // Spell ID, ability ID, item ID, etc.
};
```

### 0x05B - Event End
```cpp
struct {
    uint32 EndPara;      // Result/selection value
    uint16 EventPara;    // Event ID
    uint16 Mode;         // End or UpdatePending
};
```

### 0x0B5 - Chat Message
```cpp
struct {
    uint8 ChatType;      // Say, Shout, Tell, Party, Linkshell, etc.
    char Message[];      // Variable-length message text
};
```

---

## Sequencing and Reliability

- **Lock-step**: Server only sends next packet bundle after client ACKs previous
- **ACK mechanism**: Each header carries the last-received sequence number from the other side
- **Retransmission**: If server sees client hasn't ACK'd, it resends the previous bundle
- **Max payload**: ~1300 - 28 (header) - 16 (MD5) = ~1256 bytes per UDP datagram before compression
- **Sequence increment**: `server_packet_id` increments by 1 per bundle sent

---

## Vanadiel Time

- 1 Vanadiel day = 57.6 real-world minutes (25x speed)
- 1 Vanadiel hour = 2.4 real-world minutes
- Base epoch: The server sends `GameTime` as a 32-bit Vanadiel timestamp in 0x00A
- Client calculates current Vanadiel time from this + elapsed real time * 25

---

## Entity Update Masks

Used in 0x00D/0x00E `SendFlg`:
```
Bit 0: Position (pos, rotation, movement)
Bit 1: ClaimStatus (who has claim, enmity info)
Bit 2: General (HP%, animation, speed, target, flags)
Bit 3: Name (entity name string)
Bit 4: Model (appearance/equipment data)
Bit 5: Despawn (entity leaving zone)
Bit 6: Name2 (extended name info)
```

Combined masks:
- `UPDATE_POS = 0x01`
- `UPDATE_STATUS = 0x04`
- `UPDATE_HP = 0x04`
- `UPDATE_NAME = 0x08`
- `UPDATE_LOOK = 0x10`
- `UPDATE_ALL_MOB = 0x1F`
- `UPDATE_COMBAT = 0x06` (ClaimStatus + General)
