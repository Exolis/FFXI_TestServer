# Measures unique MMB geometry vs the flattened/baked total, to quantify what an
# asset+instance pipeline would save over merging everything into one mesh.

param(
    [string]$DatPath = "C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI\ROM\1\31.DAT"
)

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;

public class MMBInfo
{
    public string ImgID;
    public int ModelCount;
    public int VertexTotal;
    public int IndexTotal;
}

public static class FFXIDedupe
{
    static readonly byte[] KeyTable = new byte[256] {
        0xE2,0xE5,0x06,0xA9,0xED,0x26,0xF4,0x42,0x15,0xF4,0x81,0x7F,0xDE,0x9A,0xDE,0xD0,
        0x1A,0x98,0x20,0x91,0x39,0x49,0x48,0xA4,0x0A,0x9F,0x40,0x69,0xEC,0xBD,0x81,0x81,
        0x8D,0xAD,0x10,0xB8,0xC1,0x88,0x15,0x05,0x11,0xB1,0xAA,0xF0,0x0F,0x1E,0x34,0xE6,
        0x81,0xAA,0xCD,0xAC,0x02,0x84,0x33,0x0A,0x19,0x38,0x9E,0xE6,0x73,0x4A,0x11,0x5D,
        0xBF,0x85,0x77,0x08,0xCD,0xD9,0x96,0x0D,0x79,0x78,0xCC,0x35,0x06,0x8E,0xF9,0xFE,
        0x66,0xB9,0x21,0x03,0x20,0x29,0x1E,0x27,0xCA,0x86,0x82,0xE6,0x45,0x07,0xDD,0xA9,
        0xB6,0xD5,0xA2,0x03,0xEC,0xAD,0x62,0x45,0x2D,0xCE,0x79,0xBD,0x8F,0x2D,0x10,0x18,
        0xE6,0x0A,0x6F,0xAA,0x6F,0x46,0x84,0x32,0x9F,0x29,0x2C,0xC2,0xF0,0xEB,0x18,0x6F,
        0xF2,0x3A,0xDC,0xEA,0x7B,0x0C,0x81,0x2D,0xCC,0xEB,0xA1,0x51,0x77,0x2C,0xFB,0x49,
        0xE8,0x90,0xF7,0x90,0xCE,0x5C,0x01,0xF3,0x5C,0xF4,0x41,0xAB,0x04,0xE7,0x16,0xCC,
        0x3A,0x05,0x54,0x55,0xDC,0xED,0xA4,0xD6,0xBF,0x3F,0x9E,0x08,0x93,0xB5,0x63,0x38,
        0x90,0xF7,0x5A,0xF0,0xA2,0x5F,0x56,0xC8,0x08,0x70,0xCB,0x24,0x16,0xDD,0xD2,0x74,
        0x95,0x3A,0x1A,0x2A,0x74,0xC4,0x9D,0xEB,0xAF,0x69,0xAA,0x51,0x39,0x65,0x94,0xA2,
        0x4B,0x1F,0x1A,0x60,0x52,0x39,0xE8,0x23,0xEE,0x58,0x39,0x06,0x3D,0x22,0x6A,0x2D,
        0xD2,0x91,0x25,0xA5,0x2E,0x71,0x62,0xA5,0x0B,0xC1,0xE5,0x6E,0x43,0x49,0x7C,0x58,
        0x46,0x19,0x9F,0x45,0x49,0xC6,0x40,0x09,0xA2,0x99,0x5B,0x7B,0x98,0x7F,0xA0,0xD0
    };
    static readonly byte[] KeyTable2 = new byte[256] {
        0xB8,0xC5,0xF7,0x84,0xE4,0x5A,0x23,0x7B,0xC8,0x90,0x1D,0xF6,0x5D,0x09,0x51,0xC1,
        0x07,0x24,0xEF,0x5B,0x1D,0x73,0x90,0x08,0xA5,0x70,0x1C,0x22,0x5F,0x6B,0xEB,0xB0,
        0x06,0xC7,0x2A,0x3A,0xD2,0x66,0x81,0xDB,0x41,0x62,0xF2,0x97,0x17,0xFE,0x05,0xEF,
        0xA3,0xDC,0x22,0xB3,0x45,0x70,0x3E,0x18,0x2D,0xB4,0xBA,0x0A,0x65,0x1D,0x87,0xC3,
        0x12,0xCE,0x8F,0x9D,0xF7,0x0D,0x50,0x24,0x3A,0xF3,0xCA,0x70,0x6B,0x67,0x9C,0xB2,
        0xC2,0x4D,0x6A,0x0C,0xA8,0xFA,0x81,0xA6,0x79,0xEB,0xBE,0xFE,0x89,0xB7,0xAC,0x7F,
        0x65,0x43,0xEC,0x56,0x5B,0x35,0xDA,0x81,0x3C,0xAB,0x6D,0x28,0x60,0x2C,0x5F,0x31,
        0xEB,0xDF,0x8E,0x0F,0x4F,0xFA,0xA3,0xDA,0x12,0x7E,0xF1,0xA5,0xD2,0x22,0xA0,0x0C,
        0x86,0x8C,0x0A,0x0C,0x06,0xC7,0x65,0x18,0xCE,0xF2,0xA3,0x68,0xFE,0x35,0x96,0x95,
        0xA6,0xFA,0x58,0x63,0x41,0x59,0xEA,0xDD,0x7F,0xD3,0x1B,0xA8,0x48,0x44,0xAB,0x91,
        0xFD,0x13,0xB1,0x68,0x01,0xAC,0x3A,0x11,0x78,0x30,0x33,0xD8,0x4E,0x6A,0x89,0x05,
        0x7B,0x06,0x8E,0xB0,0x86,0xFD,0x9F,0xD7,0x48,0x54,0x04,0xAE,0xF3,0x06,0x17,0x36,
        0x53,0x3F,0xA8,0x11,0x53,0xCA,0xA1,0x95,0xC2,0xCD,0xE6,0x1F,0x57,0xB4,0x7F,0xAA,
        0xF3,0x6B,0xF9,0xA0,0x27,0xD0,0x09,0xEF,0xF6,0x68,0x73,0x60,0xDC,0x50,0x2A,0x25,
        0x0F,0x77,0xB9,0xB0,0x04,0x0B,0xE1,0xCC,0x35,0x31,0x84,0xE6,0x22,0xF9,0xC2,0xAB,
        0x95,0x91,0x61,0xD9,0x2B,0xB9,0x72,0x4E,0x10,0x76,0x31,0x66,0x0A,0x0B,0x2E,0x83
    };

    static void DecodeMMB(byte[] d, int off, int limit)
    {
        int declaredLen = d[off] | (d[off+1] << 8) | (d[off+2] << 16);
        int effLen = Math.Min(declaredLen, limit);
        if (d[off+3] >= 5) {
            uint key = KeyTable[d[off+5] ^ 0xF0];
            int kc = 0;
            for (int pos = 8; pos < effLen; pos++) {
                uint x = ((key & 0xFF) << 8) | (key & 0xFF);
                key += (uint)(++kc);
                d[off+pos] ^= (byte)(x >> (int)(key & 7));
                key += (uint)(++kc);
            }
        }
        if (d[off+6] == 0xFF && d[off+7] == 0xFF) {
            uint key1 = (uint)(d[off+5] ^ 0xF0);
            uint key2 = KeyTable2[key1];
            int dc = ((effLen - 8) & ~0xf) / 2;
            for (int pos = 0; pos + 8 <= dc; pos += 8) {
                int a = off + 8 + pos, b = off + 8 + dc + pos;
                if (b + 8 > off + limit) break;
                if ((key2 & 1) != 0)
                    for (int k = 0; k < 8; k++) { byte t = d[a+k]; d[a+k] = d[b+k]; d[b+k] = t; }
                key1 += 9; key2 += key1;
            }
        }
    }

    static string Str16(byte[] d, int off)
    {
        var sb = new System.Text.StringBuilder();
        for (int i = 0; i < 16; i++) {
            byte b = d[off+i];
            if (b == 0) break;
            sb.Append((b >= 0x20 && b < 0x7F) ? (char)b : '?');
        }
        return sb.ToString().TrimEnd();
    }

    static int RoundUp4(int v) { return (v + 3) & ~3; }

    // Walks a decoded MMB and tallies its model/vertex/index counts.
    public static MMBInfo WalkMMB(byte[] d, int chunkStart, int chunkSize)
    {
        int off = chunkStart + 16;
        int len = chunkSize - 16;
        DecodeMMB(d, off, len);

        var info = new MMBInfo();
        int d3 = d[off + 4];
        int vertStride = (d3 == 2) ? 48 : 36;

        int hdr = off + 16;
        info.ImgID = Str16(d, hdr);
        int pieces = BitConverter.ToInt32(d, hdr + 16);
        uint offBH = BitConverter.ToUInt32(d, hdr + 44);

        if (pieces <= 0 || pieces > 64) return info;

        int cursor = (offBH != 0) ? (int)offBH : 64;

        for (int p = 0; p < pieces; p++)
        {
            if (cursor + 32 > len) break;
            int numModel = BitConverter.ToInt32(d, off + cursor);
            cursor += 32;
            if (numModel < 0 || numModel > 50) break;

            for (int m = 0; m < numModel; m++)
            {
                if (cursor + 20 > len) break;
                int vertexSize = BitConverter.ToUInt16(d, off + cursor + 16);
                cursor += 20;

                int vBytes = vertexSize * vertStride;
                if (cursor + vBytes > len) break;
                cursor += vBytes;

                if (cursor + 4 > len) break;
                int numIndices = (int)(BitConverter.ToUInt32(d, off + cursor) & 0xFFFF);
                cursor += 4;

                int iBytes = numIndices * 2;
                if (cursor + iBytes > len) break;
                cursor += iBytes;
                if (numIndices % 2 > 0) cursor += 2;

                info.ModelCount++;
                info.VertexTotal += vertexSize;
                info.IndexTotal += numIndices;
            }
        }
        return info;
    }

    public static int[] ReadMZBIds(byte[] d, int chunkStart, int chunkSize, out string[] ids)
    {
        int off = chunkStart + 16;
        int len = chunkSize - 16;

        if (d[off+3] >= 0x1B) {
            int declared = d[off] | (d[off+1] << 8) | (d[off+2] << 16);
            if (declared <= len) {
                uint key = KeyTable[d[off+7] ^ 0xFF];
                int kc = 0;
                for (int pos = 8; pos < declared; ) {
                    int xorLen = (int)(((key >> 4) & 7) + 16);
                    if ((key & 1) != 0 && pos + xorLen < declared)
                        for (int i = 0; i < xorLen; i++) d[off+pos+i] ^= 0xFF;
                    key += (uint)(++kc);
                    pos += xorLen;
                }
                int nc = d[off+4] | (d[off+5] << 8) | (d[off+6] << 16);
                for (int i = 0; i < nc; i++) {
                    int nb = off + 32 + i * 100;
                    if (nb + 16 > off + len) break;
                    for (int j = 0; j < 16; j++) d[nb+j] ^= 0x55;
                }
            }
        }

        int total = (int)(BitConverter.ToUInt32(d, off + 4) & 0xFFFFFF);
        int endR100 = (int)BitConverter.ToUInt32(d, off + 20);
        int entrySize = total > 0 ? (endR100 - 32) / total : 0;

        var list = new List<string>();
        for (int i = 0; i < total; i++) {
            int nb = off + 32 + i * entrySize;
            if (nb + 16 > off + len) break;
            list.Add(Str16(d, nb));
        }
        ids = list.ToArray();
        return new int[] { total, entrySize };
    }
}
'@ -ErrorAction Stop

$data = [System.IO.File]::ReadAllBytes($DatPath)

$offset = 0
$mmbChunks = @(); $mzbChunks = @()
while ($offset + 16 -lt $data.Length) {
    $info = [BitConverter]::ToUInt32($data, $offset + 4)
    $type = $info -band 0x7F
    $size = ($info -shr 3) -band 0x7FFFF0
    if ($size -eq 0 -or $offset + $size -gt $data.Length) { break }
    if ($type -eq 0x2E) { $mmbChunks += ,@($offset, $size) }
    if ($type -eq 0x1C) { $mzbChunks += ,@($offset, $size) }
    $offset += $size
}

# Tally unique geometry per MMB
$byName = @{}
$uniqModels = 0; $uniqVerts = 0; $uniqIdx = 0
foreach ($c in $mmbChunks) {
    $i = [FFXIDedupe]::WalkMMB($data, $c[0], $c[1])
    $byName[$i.ImgID] = $i
    $uniqModels += $i.ModelCount
    $uniqVerts  += $i.VertexTotal
    $uniqIdx    += $i.IndexTotal
}

# Tally what flattening costs (each placement re-bakes its MMB's geometry)
$ids = $null
$meta = [FFXIDedupe]::ReadMZBIds($data, $mzbChunks[0][0], $mzbChunks[0][1], [ref]$ids)
$placements = $meta[0]

$bakedModels = 0; $bakedVerts = 0; $bakedIdx = 0
$instanceCount = @{}
foreach ($id in $ids) {
    if ($byName.ContainsKey($id)) {
        $i = $byName[$id]
        $bakedModels += $i.ModelCount
        $bakedVerts  += $i.VertexTotal
        $bakedIdx    += $i.IndexTotal
        if (-not $instanceCount.ContainsKey($id)) { $instanceCount[$id] = 0 }
        $instanceCount[$id]++
    }
}

Write-Output "=============================================================="
Write-Output " UNIQUE GEOMETRY (what an asset library would hold)"
Write-Output "=============================================================="
Write-Output ("  MMB blocks (assets) : {0}" -f $mmbChunks.Count)
Write-Output ("  mesh sections       : {0}" -f $uniqModels)
Write-Output ("  vertices            : {0:N0}" -f $uniqVerts)
Write-Output ("  indices             : {0:N0}" -f $uniqIdx)
Write-Output ""
Write-Output "=============================================================="
Write-Output " FLATTENED / BAKED (what we currently build)"
Write-Output "=============================================================="
Write-Output ("  placements          : {0}" -f $placements)
Write-Output ("  mesh sections       : {0}" -f $bakedModels)
Write-Output ("  vertices            : {0:N0}" -f $bakedVerts)
Write-Output ("  indices             : {0:N0}" -f $bakedIdx)
Write-Output ""
if ($uniqVerts -gt 0) {
    Write-Output ("  duplication factor  : {0:N2}x vertices, {1:N2}x sections" -f ($bakedVerts / $uniqVerts), ($bakedModels / [math]::Max($uniqModels,1)))
}
Write-Output ""
Write-Output "=== Most-reused meshes (best instancing candidates) ==="
$instanceCount.GetEnumerator() | Sort-Object -Property @{Expression={$_.Value}; Descending=$true} | Select-Object -First 20 | ForEach-Object {
    $v = if ($byName.ContainsKey($_.Key)) { $byName[$_.Key].VertexTotal } else { 0 }
    Write-Output ("  {0,-20} x{1,-5} ({2} verts each)" -f $_.Key, $_.Value, $v)
}
