# 7z-HBD Minimal Container Specification (v5)

## 1. Overview
This document specifies a strict, minimal subset of the 7z binary container format tailored to map 7-bit ASCII filenames to binary data blobs using a restricted set of codecs (`Copy`, `Deflate`, `LZMA2`). 

Appended directly after the compliant 7z container is a custom `HBD` (Hunspell Binary Dictionary) block. This structure enables memory-to-memory, buffer-to-buffer decompression of distinct subblocks without allocating external memory for sliding window dictionaries, while ensuring full compatibility with standard 7-Zip decoder tools.

---

## 2. Global File Layout
A complete 7z-HBD file consists of three contiguous segments:
1. **7z Signature Header**: Standard 32-byte preamble.
2. **7z Data Stream Segment**: Raw payloads of all non-empty files, concatenated sequentially.
3. **7z Metadata Header**: Minimal directory and stream metadata, including standard CRC32s, to satisfy 7-Zip parsers.
4. **HBD Appended Block**: Custom metadata mapping both Deflate and LZMA2 subblocks, bounded by a trailing CRC32.

```text
+-------------------------+
| 7z Signature Header     | (32 bytes)
+-------------------------+
| Data Stream 1 Payload   |
| Data Stream 2 Payload   |
| ...                     |
+-------------------------+
| 7z Metadata Header      | (Variable length)
+-------------------------+
| HBD Appended Block      | (Variable length, starts exactly at EOF of 7z)
+-------------------------+
```

---

## 3. Data Payloads & Memory-to-Memory Constraints

Files are stored as continuous streams in the **7z Data Stream Segment**. To satisfy the strict memory-to-memory buffer requirements without independent sliding window allocations, encoders MUST obey the following constraints:

### 3.1 Codecs Supported
Only three codecs are permitted:
*   **Copy** (ID: `0x00`) - Raw uncompressed bytes.
*   **Deflate** (ID: `0x040108`)
*   **LZMA2** (ID: `0x21`)

### 3.2 File Size Constraints & Empty Files
To support empty files with minimal added complexity, all archive mapping MUST be strictly ordered:
*   All $N$ **non-empty files** ($\ge 1$ byte) MUST be grouped together first.
*   All $E$ **empty files** ($0$ bytes) MUST be grouped together at the end of the file list.
*   The maximum uncompressed file size for any individual file is bounded to 2,097,152 bytes (2MB).

This eliminates interleaved stream/folder mapping logic. Empty files do not have any payload in the Data Stream Segment.

### 3.3 Deflate Subblock Encoding
Deflate streams MUST be divided into independent subblocks. 
*   Subblocks MUST be terminated with a **`Z_FULL_FLUSH`** operation. Unlike `Z_SYNC_FLUSH`, a full flush explicitly clears the sliding window dictionary state while aligning outputs to byte boundaries.
*   Because the dictionary is reset between these boundaries, any standard DEFLATE decoder can decode each compressed subblock completely independently from memory buffer to memory buffer, without referencing a prior sliding window.
*   Concatenating these subblocks natively produces a valid continuous DEFLATE stream for standard 7-Zip extractors.

### 3.4 LZMA2 Subblock Encoding
To decompress LZMA2 buffer-to-buffer without allocating a separate sliding window, the maximum decompressed block size is strictly bounded to 2MB, and **the LZMA2 dictionary size is strictly hardcoded to 2MB**. 
*   The standard LZMA2 property byte for 2MB is $p = 18$ (`0x12`). Encoders MUST hardcode `0x12` in the metadata for all LZMA2 streams.
*   LZMA2 streams MAY be divided into independent subblocks. 
*   An LZMA2 subblock is a sequence of LZMA2 chunks sharing the same dictionary. 
*   To ensure independent memory-to-memory decompression, the first chunk of each subblock MUST dictate a dictionary reset so it does not depend on the dictionary state of the preceding subblock.

---

## 4. HBD Appended Block Specification

The `HBD` block is appended precisely at the byte immediately following the end of the standard 7z container. Fixed-width multi-byte integers are **Little-Endian**. The subblock maps utilize standard 7z **VarInts** (defined in Section 5.1).

| Offset | Size | Description |
| :--- | :--- | :--- |
| `0x00` | 3 bytes | **Signature**: ASCII `"HBD"` (`0x48, 0x42, 0x44`) |
| `0x03` | 1 byte | **SemVer Length** ($L$): Unsigned 8-bit int. The length of the SemVer string. |
| `0x04` | $L$ bytes | **SemVer String**: True Semantic Version string in ASCII (e.g., `"1.0.0"`). No null terminator. |
| `0x04 + L` | 4 bytes | **Max Decompressed Block Size**: Unsigned 32-bit int (Little-Endian). Must be $\le 2,097,152$ (2MB). |
| `0x08 + L` | 4 bytes | **Max Compressed Block Size**: Unsigned 32-bit int (Little-Endian). Must be $\le 2,097,152$ (2MB). |
| `0x0C + L` | VarInt | **Deflate Stream Count** ($K_D$): Number of Deflate streams detailed in the map. |
| Var | Var | **Deflate Subblock Map**: Array of $K_D$ variable-length entries. |
| Var | VarInt | **LZMA2 Stream Count** ($K_L$): Number of LZMA2 streams detailed in the map. |
| Var | Var | **LZMA2 Subblock Map**: Array of $K_L$ variable-length entries. |
| End | 4 bytes | **HBD CRC32**: CRC32 of the entire HBD block, from offset `0x00` up to (but not including) these last 4 bytes. |

### 4.1 Deflate Subblock Map Entry Structure
For each of the $K_D$ Deflate streams, the following block occurs, strictly utilizing 7z **VarInts**:

1.  **Stream Index** (`VarInt`): The 0-based index of the file as it appears sequentially in the archive (from `0` to $N-1$). **This index MUST refer strictly to a stream encoded with the Deflate codec.** It is strictly invalid for this index to point to a Copy payload, an LZMA2 payload, or an empty file.
2.  **Subblock Count ($M$)** (`VarInt`): Number of independent reset blocks within this stream.
3.  **Subblock Sizes** (Array of $M$ `VarInt`s): Exact compressed byte sizes of each subblock in sequential order. 

### 4.2 LZMA2 Subblock Map Entry Structure
For each of the $K_L$ LZMA2 streams, the following block occurs, strictly utilizing 7z **VarInts**:

1.  **Stream Index** (`VarInt`): The 0-based index of the file in the archive (from `0` to $N-1$). **This index MUST refer strictly to a stream encoded with the LZMA2 codec.**
2.  **Subblock Count ($J$)** (`VarInt`): Number of independent subblocks (dictionary resets) within this stream.
3.  **Subblock Sizes** (Array of $J$ `VarInt`s): Exact compressed byte sizes of each subblock sequence in sequential order. 

---

## 5. Minimal 7z Subset Structure

To keep the implementation minimal but fully compliant with 7-Zip, the 7z metadata avoids nested archives and header compression. The 7z metadata header is constructed as an uncompressed, linear tree of bytes.

### 5.1 Variable-Length Integers (VarInt)
Both standard 7z structures and the custom HBD map use the 7z specific Variable-Length Integer format. The first byte encodes both the total byte length of the integer and its most significant bits. The following bytes hold the lower bits in little-endian order.

**Decoding Algorithm:**
1.  Read the first byte `b0`. Let `mask = 0x80` and `value = 0`.
2.  Iterate `i` from `0` to `8`:
    *   If `(b0 & mask) == 0`:
        *   `value |= ((uint64_t)(b0 & (mask - 1)) << (8 * i))`
        *   Return `value`.
    *   Else:
        *   Read the next byte into `next_byte`.
        *   `value |= ((uint64_t)next_byte << (8 * i))`
        *   `mask >>= 1`

### 5.2 7z Signature Header (Absolute File Offset `0x00`)

| Offset | Bytes | Description |
| :--- | :--- | :--- |
| `0x00` | `37 7A BC AF 27 1C` | 7z Magic Signature |
| `0x06` | `00 04` | Version (0.4) |
| `0x08` | 4 bytes | CRC32 of the following 20 bytes. |
| `0x0C` | 8 bytes (UInt64) | **NextHeaderOffset**: Offset to the 7z Metadata Header relative to the end of this 32-byte header (absolute offset `0x20 + NextHeaderOffset`). This equals the total size of the Data Stream Segment. |
| `0x14` | 8 bytes (UInt64) | **NextHeaderSize**: Size of the 7z Metadata Header. |
| `0x1C` | 4 bytes | **NextHeaderCRC**: CRC32 of the uncompressed 7z Metadata Header. |

### 5.3 7z Metadata Header Assembly

#### A. MainStreamsInfo Sequence (Non-Empty Files Only)
Let $N$ be the number of non-empty files.
```text
0x01                          // ID: Header
  0x04                        // ID: MainStreamsInfo
    0x06                      // ID: PackInfo
      0x00                    // PackPos (VarInt: 0)
      0x01                    // NumPackStreams
      [VarInt: N]             // Value: Number of NON-EMPTY files
      0x09                    // ID: Size
      [Array of N VarInts]    // Compressed sizes of each non-empty file stream
      0x00                    // End of PackInfo
    0x07                      // ID: UnpackInfo
      0x0B                    // ID: Folder
      [VarInt: N]             // NumFolders (1 folder per non-empty file)
      0x00                    // External = 0
      [N instances of Folder Codec Setup, see below]
      0x0C                    // ID: CodersUnpackSize
      [Array of N VarInts]    // Decompressed sizes of each non-empty file stream
      0x00                    // End of UnpackInfo
    0x08                      // ID: SubStreamsInfo
      0x0A                    // ID: Digest
      0x01                    // AllAreDefined = 1
      [Array of N CRC32s]     // 4 bytes each, Little-Endian, for decompressed files
      0x00                    // End of SubStreamsInfo
    0x00                      // End of MainStreamsInfo
```

**Folder Codec Setup Instances**:
For each of the $N$ non-empty files, append an opaque byte sequence depending on the codec:
*   **Copy**: `0x01 0x01 0x00`
*   **Deflate**: `0x01 0x03 0x04 0x01 0x08`
*   **LZMA2**: `0x01 0x21 0x01 0x12`

#### B. FilesInfo Sequence (File Names & Empty Files)
Immediately following the `End of MainStreamsInfo` (`0x00`), append the FilesInfo block. Let $N$ be the number of non-empty files and $E$ be the number of empty files grouped at the end.

> **Bit Array Encoding Note:** 7z stores bit arrays tightly packed into bytes. Bit 0 (the first item) corresponds to the most significant bit (`0x80`) of the first byte, Bit 1 is `0x40`, and so on. Padding bits in the last byte are set to `0`. 

```text
  0x05                        // ID: FilesInfo
    [VarInt: N + E]           // Value: Total number of files
    
    // --- INJECT THE FOLLOWING ONLY IF E > 0 ---
    0x0E                      // ID: EmptyStream
    [VarInt: ceil((N+E)/8)]   // Size of the bit array in bytes
    [Bit Array]               // (N+E) bits. First N bits are 0, last E bits are 1.
                              
    0x0F                      // ID: EmptyFile
    [VarInt: ceil(E/8)]       // Size of the bit array in bytes
    [Bit Array]               // E bits. All bits must be 1.
    // ------------------------------------------

    0x11                      // ID: Name
      [VarInt: NameDataSize]  // Size of the names block in bytes
      0x00                    // External = 0
      [Names Data Block]      // Sequence of N+E null-terminated UTF-16LE strings. 
                              // Terminate each name with `0x00 0x00`.
    0x00                      // End of FilesInfo
  0x00                        // End of Header
```