import 'dart:typed_data';

/// Decodes BC7 (BPTC) compressed texture data to RGBA8888 pixels.
///
/// BC7 is a block compression format defined by the DirectX 11 specification.
/// Each 4x4 pixel block is encoded as 128 bits (16 bytes) using one of 8 modes
/// (0-7), each with different endpoint/index/partition configurations.
///
/// Reference: https://learn.microsoft.com/en-us/windows/win32/direct3d11/bc7-format
///
/// [data] is the raw BC7 block data.
/// [width] and [height] are the texture dimensions in pixels.
/// Returns [Uint8List] of RGBA pixel data (width * height * 4 bytes).
///
/// Throws [ArgumentError] if [width] or [height] is not positive.
/// Throws [FormatException] if [data] is too small for the given dimensions.
Uint8List decodeBc7(Uint8List data, int width, int height) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('Width and height must be positive: $width x $height');
  }

  final blocksX = (width + 3) ~/ 4;
  final blocksY = (height + 3) ~/ 4;
  final requiredBytes = blocksX * blocksY * 16;

  if (data.length < requiredBytes) {
    throw FormatException(
      'BC7 data too small: need $requiredBytes bytes for '
      '${width}x$height (${blocksX}x$blocksY blocks), got ${data.length}',
    );
  }

  final output = Uint8List(width * height * 4);

  for (int by = 0; by < blocksY; by++) {
    for (int bx = 0; bx < blocksX; bx++) {
      final blockOffset = (by * blocksX + bx) * 16;
      final block = Uint8List.sublistView(data, blockOffset, blockOffset + 16);
      final pixels = _decodeBlock(block);

      // Write decoded 4x4 pixels to the output image.
      for (int py = 0; py < 4; py++) {
        final destY = by * 4 + py;
        if (destY >= height) break;
        for (int px = 0; px < 4; px++) {
          final destX = bx * 4 + px;
          if (destX >= width) continue;
          final srcIdx = (py * 4 + px) * 4;
          final dstIdx = (destY * width + destX) * 4;
          output[dstIdx] = pixels[srcIdx];
          output[dstIdx + 1] = pixels[srcIdx + 1];
          output[dstIdx + 2] = pixels[srcIdx + 2];
          output[dstIdx + 3] = pixels[srcIdx + 3];
        }
      }
    }
  }

  return output;
}

/// Detects the BC7 mode from a 16-byte block.
///
/// The mode is determined by the position of the first set bit (LSB first).
/// Mode 0: bit 0 set, Mode 1: bit 1 set, ..., Mode 7: bit 7 set.
/// Returns -1 if no mode bit is set (invalid block).
int detectBc7Mode(Uint8List block) {
  if (block.isEmpty) return -1;
  final firstByte = block[0];
  if (firstByte == 0) return -1;

  for (int i = 0; i < 8; i++) {
    if ((firstByte & (1 << i)) != 0) return i;
  }
  return -1; // unreachable
}

// --------------------------------------------------------------------------
// BC7 mode configurations
// --------------------------------------------------------------------------

/// Configuration data for each BC7 mode.
class _Bc7ModeInfo {
  final int mode;
  final int numSubsets;
  final int partitionBits;
  final int rotationBits;
  final int indexSelectionBits;
  final int colorBits;
  final int alphaBits;
  final int pBitType; // 0=none, 1=shared, 2=unique
  final int indexBits;
  final int secondaryIndexBits;

  const _Bc7ModeInfo({
    required this.mode,
    required this.numSubsets,
    required this.partitionBits,
    required this.rotationBits,
    required this.indexSelectionBits,
    required this.colorBits,
    required this.alphaBits,
    required this.pBitType,
    required this.indexBits,
    required this.secondaryIndexBits,
  });
}

const _modeInfos = [
  // Mode 0: 3 subsets, 4-bit partition, 4-bit color, no alpha, unique p-bits, 3-bit index
  _Bc7ModeInfo(mode: 0, numSubsets: 3, partitionBits: 4, rotationBits: 0, indexSelectionBits: 0, colorBits: 4, alphaBits: 0, pBitType: 2, indexBits: 3, secondaryIndexBits: 0),
  // Mode 1: 2 subsets, 6-bit partition, 6-bit color, no alpha, shared p-bits, 3-bit index
  _Bc7ModeInfo(mode: 1, numSubsets: 2, partitionBits: 6, rotationBits: 0, indexSelectionBits: 0, colorBits: 6, alphaBits: 0, pBitType: 1, indexBits: 3, secondaryIndexBits: 0),
  // Mode 2: 3 subsets, 6-bit partition, 5-bit color, no alpha, no p-bits, 2-bit index
  _Bc7ModeInfo(mode: 2, numSubsets: 3, partitionBits: 6, rotationBits: 0, indexSelectionBits: 0, colorBits: 5, alphaBits: 0, pBitType: 0, indexBits: 2, secondaryIndexBits: 0),
  // Mode 3: 2 subsets, 6-bit partition, 7-bit color, no alpha, unique p-bits, 2-bit index
  _Bc7ModeInfo(mode: 3, numSubsets: 2, partitionBits: 6, rotationBits: 0, indexSelectionBits: 0, colorBits: 7, alphaBits: 0, pBitType: 2, indexBits: 2, secondaryIndexBits: 0),
  // Mode 4: 1 subset, 0-bit partition, 2-bit rotation, 1-bit index selection, 5-bit color, 6-bit alpha, no p-bits, 2-bit primary index, 3-bit secondary index
  _Bc7ModeInfo(mode: 4, numSubsets: 1, partitionBits: 0, rotationBits: 2, indexSelectionBits: 1, colorBits: 5, alphaBits: 6, pBitType: 0, indexBits: 2, secondaryIndexBits: 3),
  // Mode 5: 1 subset, 0-bit partition, 2-bit rotation, 0-bit index selection, 7-bit color, 8-bit alpha, no p-bits, 2-bit primary index, 2-bit secondary index
  _Bc7ModeInfo(mode: 5, numSubsets: 1, partitionBits: 0, rotationBits: 2, indexSelectionBits: 0, colorBits: 7, alphaBits: 8, pBitType: 0, indexBits: 2, secondaryIndexBits: 2),
  // Mode 6: 1 subset, 0-bit partition, 0-bit rotation, 0-bit index selection, 7-bit color, 7-bit alpha, unique p-bits, 4-bit index
  _Bc7ModeInfo(mode: 6, numSubsets: 1, partitionBits: 0, rotationBits: 0, indexSelectionBits: 0, colorBits: 7, alphaBits: 7, pBitType: 2, indexBits: 4, secondaryIndexBits: 0),
  // Mode 7: 2 subsets, 6-bit partition, 5-bit color, 5-bit alpha, unique p-bits, 2-bit index
  _Bc7ModeInfo(mode: 7, numSubsets: 2, partitionBits: 6, rotationBits: 0, indexSelectionBits: 0, colorBits: 5, alphaBits: 5, pBitType: 2, indexBits: 2, secondaryIndexBits: 0),
];

// --------------------------------------------------------------------------
// Partition tables (BC7 spec Sections 2.3.1 and 2.3.2)
// --------------------------------------------------------------------------

/// 2-subset partition table (64 entries, 16 texels each).
/// Each value 0-1 indicates which subset that texel belongs to.
const _partitionTable2 = [
  [0,0,1,1,0,0,1,1,0,0,1,1,0,0,1,1],
  [0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1],
  [0,1,1,1,0,1,1,1,0,1,1,1,0,1,1,1],
  [0,0,0,1,0,0,1,1,0,0,1,1,0,1,1,1],
  [0,0,0,0,0,0,0,1,0,0,0,1,0,0,1,1],
  [0,0,1,1,0,1,1,1,0,1,1,1,1,1,1,1],
  [0,0,0,1,0,0,1,1,0,1,1,1,1,1,1,1],
  [0,0,0,0,0,0,0,1,0,0,1,1,0,1,1,1],
  [0,0,0,0,0,0,0,0,0,0,0,1,0,0,1,1],
  [0,0,1,1,0,1,1,1,1,1,1,1,1,1,1,1],
  [0,0,0,0,0,0,0,1,0,1,1,1,1,1,1,1],
  [0,0,0,0,0,0,0,0,0,0,0,1,0,1,1,1],
  [0,0,0,1,0,1,1,1,1,1,1,1,1,1,1,1],
  [0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1],
  [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1],
  [0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1],
  [0,0,0,0,1,0,0,0,1,1,1,0,1,1,1,1],
  [0,1,1,1,0,0,0,1,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,1,0,0,0,1,1,1,0],
  [0,1,1,1,0,0,1,1,0,0,0,1,0,0,0,0],
  [0,0,1,1,0,0,0,1,0,0,0,0,0,0,0,0],
  [0,0,0,0,1,0,0,0,1,1,0,0,1,1,1,0],
  [0,0,0,0,0,0,0,0,1,0,0,0,1,1,0,0],
  [0,1,1,1,0,0,1,1,0,0,1,1,0,0,0,1],
  [0,0,1,1,0,0,0,1,0,0,0,1,0,0,0,0],
  [0,0,0,0,1,0,0,0,1,0,0,0,1,1,0,0],
  [0,1,1,0,0,1,1,0,0,1,1,0,0,1,1,0],
  [0,0,1,1,0,1,1,0,0,1,1,0,1,1,0,0],
  [0,0,0,1,0,1,1,1,1,1,1,0,1,0,0,0],
  [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
  [0,1,1,1,0,0,0,1,1,0,0,0,1,1,1,0],
  [0,0,1,1,1,0,0,1,1,0,0,1,1,1,0,0],
  [0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,1],
  [0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1],
  [0,1,0,1,1,0,1,0,0,1,0,1,1,0,1,0],
  [0,0,1,1,0,0,1,1,1,1,0,0,1,1,0,0],
  [0,0,1,1,1,1,0,0,0,0,1,1,1,1,0,0],
  [0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0],
  [0,1,1,0,1,0,0,1,0,1,1,0,1,0,0,1],
  [0,1,0,1,1,0,1,0,1,0,1,0,0,1,0,1],
  [0,1,1,1,0,0,1,1,1,1,0,0,1,1,1,0],
  [0,0,0,1,0,0,1,1,1,1,0,0,1,0,0,0],
  [0,0,1,1,0,0,1,0,0,1,0,0,1,1,0,0],
  [0,0,1,1,1,0,1,1,1,1,0,1,1,1,0,0],
  [0,1,1,0,1,0,0,1,1,0,0,1,0,1,1,0],
  [0,0,1,1,1,1,0,0,1,1,0,0,0,0,1,1],
  [0,1,1,0,0,1,1,0,1,0,0,1,1,0,0,1],
  [0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0],
  [0,1,0,0,1,1,1,0,0,1,0,0,0,0,0,0],
  [0,0,1,0,0,1,1,1,0,0,1,0,0,0,0,0],
  [0,0,0,0,0,0,1,0,0,1,1,1,0,0,1,0],
  [0,0,0,0,0,1,0,0,1,1,1,0,0,1,0,0],
  [0,1,1,0,1,1,0,0,1,0,0,1,0,0,1,1],
  [0,0,1,1,0,1,1,0,1,1,0,0,1,0,0,1],
  [0,1,1,0,0,0,1,1,1,0,0,1,1,1,0,0],
  [0,0,1,1,1,0,0,1,1,1,0,0,0,1,1,0],
  [0,1,1,0,1,1,0,0,1,1,0,0,1,0,0,1],
  [0,1,1,0,0,0,1,1,0,0,1,1,1,0,0,1],
  [0,1,1,1,1,1,1,0,1,0,0,0,0,0,0,1],
  [0,0,0,1,1,0,0,0,1,1,1,0,0,1,1,1],
  [0,0,0,0,1,1,1,1,0,0,1,1,0,0,1,1],
  [0,0,1,1,0,0,1,1,1,1,1,1,0,0,0,0],
  [0,0,1,0,0,0,1,0,1,1,1,0,1,1,1,0],
  [0,1,0,0,0,1,0,0,0,1,1,1,0,1,1,1],
];

/// 3-subset partition table (64 entries, 16 texels each).
/// Each value 0-2 indicates which subset.
const _partitionTable3 = [
  [0,0,1,1,0,0,1,1,0,2,2,1,2,2,2,2],
  [0,0,0,1,0,0,1,1,2,2,1,1,2,2,2,1],
  [0,0,0,0,2,0,0,1,2,2,1,1,2,2,1,1],
  [0,2,2,2,0,0,2,2,0,0,1,1,0,1,1,1],
  [0,0,0,0,0,0,0,0,1,1,2,2,1,1,2,2],
  [0,0,1,1,0,0,1,1,0,0,2,2,0,0,2,2],
  [0,0,2,2,0,0,2,2,1,1,1,1,1,1,1,1],
  [0,0,1,1,0,0,1,1,2,2,1,1,2,2,1,1],
  [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2],
  [0,0,0,0,1,1,1,1,1,1,1,1,2,2,2,2],
  [0,0,0,0,1,1,1,1,2,2,2,2,2,2,2,2],
  [0,0,1,2,0,0,1,2,0,0,1,2,0,0,1,2],
  [0,1,1,2,0,1,1,2,0,1,1,2,0,1,1,2],
  [0,1,2,2,0,1,2,2,0,1,2,2,0,1,2,2],
  [0,0,1,1,0,1,1,2,1,1,2,2,1,2,2,2],
  [0,0,1,1,2,0,0,1,2,2,0,0,2,2,2,0],
  [0,0,0,1,0,0,1,1,0,1,1,2,1,1,2,2],
  [0,1,1,1,0,0,1,1,2,0,0,1,2,2,0,0],
  [0,0,0,0,1,1,2,2,1,1,2,2,1,1,2,2],
  [0,0,2,2,0,0,2,2,0,0,2,2,1,1,1,1],
  [0,1,1,1,0,1,1,1,0,2,2,2,0,2,2,2],
  [0,0,0,1,0,0,0,1,2,2,2,1,2,2,2,1],
  [0,0,0,0,0,0,1,1,0,1,2,2,0,1,2,2],
  [0,0,0,0,1,1,0,0,2,2,1,0,2,2,1,0],
  [0,1,2,2,0,1,2,2,0,0,1,1,0,0,0,0],
  [0,0,1,2,0,0,1,2,1,1,2,2,2,2,2,2],
  [0,1,1,0,1,2,2,1,1,2,2,1,0,1,1,0],
  [0,0,0,0,0,1,1,0,1,2,2,1,1,2,2,1],
  [0,0,2,2,1,1,0,2,1,1,0,2,0,0,2,2],
  [0,1,1,0,0,1,1,0,2,0,0,2,2,2,2,2],
  [0,0,1,1,0,1,2,2,0,1,2,2,0,0,1,1],
  [0,0,0,0,2,0,0,0,2,2,1,1,2,2,2,1],
  [0,0,0,0,0,0,0,2,1,1,2,2,1,2,2,2],
  [0,2,2,2,0,0,2,2,0,0,1,2,0,0,1,1],
  [0,0,1,1,0,0,1,2,0,0,2,2,0,2,2,2],
  [0,1,2,0,0,1,2,0,0,1,2,0,0,1,2,0],
  [0,0,0,0,1,1,1,1,2,2,2,2,0,0,0,0],
  [0,1,2,0,1,2,0,1,2,0,1,2,0,1,2,0],
  [0,1,2,0,2,0,1,2,1,2,0,1,0,1,2,0],
  [0,0,1,1,2,2,0,0,1,1,2,2,0,0,1,1],
  [0,0,1,1,1,1,2,2,2,2,0,0,0,0,1,1],
  [0,1,0,1,0,1,0,1,2,2,2,2,2,2,2,2],
  [0,0,0,0,0,0,0,0,2,1,2,1,2,1,2,1],
  [0,0,2,2,1,1,2,2,0,0,2,2,1,1,2,2],
  [0,0,2,2,0,0,1,1,0,0,2,2,0,0,1,1],
  [0,2,2,0,1,2,2,1,0,2,2,0,1,2,2,1],
  [0,1,0,1,2,2,2,2,2,2,2,2,0,1,0,1],
  [0,0,0,0,2,1,2,1,2,1,2,1,2,1,2,1],
  [0,1,0,1,0,1,0,1,0,1,0,1,2,2,2,2],
  [0,2,2,2,0,1,1,1,0,2,2,2,0,1,1,1],
  [0,0,0,2,1,1,1,2,0,0,0,2,1,1,1,2],
  [0,0,0,0,2,1,1,2,2,1,1,2,2,1,1,2],
  [0,2,2,2,0,1,1,1,0,1,1,1,0,2,2,2],
  [0,0,0,2,1,1,1,2,1,1,1,2,0,0,0,2],
  [0,1,1,0,0,1,1,0,0,1,1,0,2,2,2,2],
  [0,0,0,0,0,0,0,0,2,1,1,2,2,1,1,2],
  [0,1,1,0,0,1,1,0,2,2,2,2,2,2,2,2],
  [0,0,2,2,0,0,1,1,0,0,1,1,0,0,2,2],
  [0,0,2,2,1,1,2,2,1,1,2,2,0,0,2,2],
  [0,0,0,0,0,0,0,0,0,0,0,0,2,1,1,2],
  [0,0,0,2,0,0,0,1,0,0,0,2,0,0,0,1],
  [0,2,2,2,1,2,2,2,0,2,2,2,1,2,2,2],
  [0,1,0,1,2,2,2,2,2,2,2,2,2,2,2,2],
  [0,1,1,1,2,0,1,1,2,2,0,1,2,2,2,0],
];

/// Anchor index for second subset in 2-subset partitions.
/// The anchor index is the texel in each subset whose index has one fewer bit.
const _anchorIndex2 = [
  15, 15, 15, 15, 15, 15, 15, 15,
  15, 15, 15, 15, 15, 15, 15, 15,
  15,  2,  8,  2,  2,  8,  8, 15,
   2,  8,  2,  2,  8,  8,  2,  2,
  15, 15,  6,  8,  2,  8, 15, 15,
   2,  8,  2,  2,  2, 15, 15,  6,
   6,  2,  6,  8, 15, 15,  2,  2,
  15, 15, 15, 15, 15,  2,  2, 15,
];

/// Anchor indices for second subset in 3-subset partitions.
const _anchorIndex3a = [
   3,  3, 15, 15,  8,  3, 15, 15,
   8,  8,  6,  6,  6,  5,  3,  3,
   3,  3,  8, 15,  3,  3,  6, 10,
   5,  8,  8,  6,  8,  5, 15, 15,
   8, 15,  3,  5,  6, 10,  8, 15,
  15,  3, 15,  5, 15, 15, 15, 15,
   3, 15,  5,  5,  5,  8,  5, 10,
   5, 10,  8, 13, 15, 12,  3,  3,
];

/// Anchor indices for third subset in 3-subset partitions.
const _anchorIndex3b = [
  15,  8,  8,  3, 15, 15,  3,  8,
  15, 15, 15, 15, 15, 15, 15,  8,
  15,  8, 15,  3, 15,  8, 15,  8,
   3, 15,  6, 10, 15, 15, 10,  8,
  15,  3, 15, 10, 10,  8,  9, 10,
   6, 15,  8, 15,  3,  6,  6,  8,
  15,  3, 15, 15, 15, 15, 15, 15,
  15, 15, 15, 15,  3, 15, 15,  8,
];

// --------------------------------------------------------------------------
// Bit reader for 128-bit blocks
// --------------------------------------------------------------------------

class _BitReader {
  final Uint8List _data;
  int position;

  _BitReader(this._data) : position = 0;

  /// Read [count] bits (up to 32) from the block, LSB first.
  int readBits(int count) {
    if (count == 0) return 0;
    int result = 0;
    for (int i = 0; i < count; i++) {
      final byteIdx = position >> 3;
      final bitIdx = position & 7;
      if (byteIdx < _data.length) {
        result |= ((_data[byteIdx] >> bitIdx) & 1) << i;
      }
      position++;
    }
    return result;
  }
}

// --------------------------------------------------------------------------
// Block decoding
// --------------------------------------------------------------------------

/// Decode a single 16-byte BC7 block into 16 RGBA pixels (64 bytes).
Uint8List _decodeBlock(Uint8List block) {
  final mode = detectBc7Mode(block);

  if (mode < 0 || mode > 7) {
    // Invalid block: output magenta debug pixels.
    return _magentaBlock();
  }

  final info = _modeInfos[mode];
  final reader = _BitReader(block);

  // Skip mode bits (mode + 1 bits: the mode number of 0 bits followed by a 1 bit).
  reader.position = mode + 1;

  // Read partition index.
  final partition = reader.readBits(info.partitionBits);

  // Read rotation bits (modes 4, 5).
  final rotation = reader.readBits(info.rotationBits);

  // Read index selection bit (mode 4 only).
  final indexSelection = reader.readBits(info.indexSelectionBits);

  // Read endpoints.
  final numEndpoints = info.numSubsets * 2;

  // Color endpoints: R, G, B for each endpoint.
  final endpointR = List<int>.filled(numEndpoints, 0);
  final endpointG = List<int>.filled(numEndpoints, 0);
  final endpointB = List<int>.filled(numEndpoints, 0);
  final endpointA = List<int>.filled(numEndpoints, 0);

  for (int i = 0; i < numEndpoints; i++) {
    endpointR[i] = reader.readBits(info.colorBits);
  }
  for (int i = 0; i < numEndpoints; i++) {
    endpointG[i] = reader.readBits(info.colorBits);
  }
  for (int i = 0; i < numEndpoints; i++) {
    endpointB[i] = reader.readBits(info.colorBits);
  }

  // Alpha endpoints (modes 4, 5, 6, 7).
  if (info.alphaBits > 0) {
    for (int i = 0; i < numEndpoints; i++) {
      endpointA[i] = reader.readBits(info.alphaBits);
    }
  }

  // Read P-bits (if any).
  final pBits = <int>[];
  if (info.pBitType == 1) {
    // Shared p-bits: one per subset.
    for (int i = 0; i < info.numSubsets; i++) {
      pBits.add(reader.readBits(1));
    }
  } else if (info.pBitType == 2) {
    // Unique p-bits: one per endpoint.
    for (int i = 0; i < numEndpoints; i++) {
      pBits.add(reader.readBits(1));
    }
  }

  // Unquantize endpoints.
  for (int i = 0; i < numEndpoints; i++) {
    int pBit;
    if (info.pBitType == 1) {
      pBit = pBits[i >> 1]; // Shared: same p-bit for both endpoints in a subset.
    } else if (info.pBitType == 2) {
      pBit = pBits[i];
    } else {
      pBit = -1; // No p-bit.
    }

    endpointR[i] = _unquantize(endpointR[i], info.colorBits, pBit);
    endpointG[i] = _unquantize(endpointG[i], info.colorBits, pBit);
    endpointB[i] = _unquantize(endpointB[i], info.colorBits, pBit);

    if (info.alphaBits > 0) {
      endpointA[i] = _unquantize(endpointA[i], info.alphaBits, pBit);
    } else {
      endpointA[i] = 255; // Opaque when no alpha channel.
    }
  }

  // Read primary color indices.
  final primaryIndices = List<int>.filled(16, 0);
  for (int i = 0; i < 16; i++) {
    final subset = _getSubset(info.numSubsets, partition, i);
    final isAnchor = _isAnchorIndex(i, subset, info.numSubsets, partition);
    final bits = isAnchor ? info.indexBits - 1 : info.indexBits;
    primaryIndices[i] = reader.readBits(bits);
  }

  // Read secondary indices (modes 4, 5).
  final secondaryIndices = List<int>.filled(16, 0);
  if (info.secondaryIndexBits > 0) {
    for (int i = 0; i < 16; i++) {
      // For secondary indices, texel 0 is always the anchor.
      final isAnchor = (i == 0);
      final bits = isAnchor ? info.secondaryIndexBits - 1 : info.secondaryIndexBits;
      secondaryIndices[i] = reader.readBits(bits);
    }
  }

  // Interpolate endpoints to get final pixel colors.
  final pixels = Uint8List(64);
  final primaryWeights = _getWeights(info.indexBits);
  final secondaryWeights = info.secondaryIndexBits > 0
      ? _getWeights(info.secondaryIndexBits)
      : primaryWeights;

  for (int i = 0; i < 16; i++) {
    final subset = _getSubset(info.numSubsets, partition, i);
    final e0 = subset * 2;
    final e1 = subset * 2 + 1;

    int r, g, b, a;

    if (info.secondaryIndexBits > 0) {
      // Modes 4 and 5: separate color and alpha indices.
      int colorIndex, alphaIndex;
      if (info.mode == 4 && indexSelection == 1) {
        // Index selection swaps which index is used for color vs alpha.
        colorIndex = secondaryIndices[i];
        alphaIndex = primaryIndices[i];
        r = _interpolate(endpointR[e0], endpointR[e1], secondaryWeights, colorIndex);
        g = _interpolate(endpointG[e0], endpointG[e1], secondaryWeights, colorIndex);
        b = _interpolate(endpointB[e0], endpointB[e1], secondaryWeights, colorIndex);
        a = _interpolate(endpointA[e0], endpointA[e1], primaryWeights, alphaIndex);
      } else {
        colorIndex = primaryIndices[i];
        alphaIndex = secondaryIndices[i];
        r = _interpolate(endpointR[e0], endpointR[e1], primaryWeights, colorIndex);
        g = _interpolate(endpointG[e0], endpointG[e1], primaryWeights, colorIndex);
        b = _interpolate(endpointB[e0], endpointB[e1], primaryWeights, colorIndex);
        a = _interpolate(endpointA[e0], endpointA[e1], secondaryWeights, alphaIndex);
      }
    } else {
      // Single index for all channels.
      final w = primaryWeights;
      final idx = primaryIndices[i];
      r = _interpolate(endpointR[e0], endpointR[e1], w, idx);
      g = _interpolate(endpointG[e0], endpointG[e1], w, idx);
      b = _interpolate(endpointB[e0], endpointB[e1], w, idx);
      a = _interpolate(endpointA[e0], endpointA[e1], w, idx);
    }

    // Apply rotation (modes 4, 5).
    if (rotation > 0) {
      switch (rotation) {
        case 1: // Swap A and R
          final tmp = a; a = r; r = tmp;
          break;
        case 2: // Swap A and G
          final tmp = a; a = g; g = tmp;
          break;
        case 3: // Swap A and B
          final tmp = a; a = b; b = tmp;
          break;
      }
    }

    pixels[i * 4] = r.clamp(0, 255);
    pixels[i * 4 + 1] = g.clamp(0, 255);
    pixels[i * 4 + 2] = b.clamp(0, 255);
    pixels[i * 4 + 3] = a.clamp(0, 255);
  }

  return pixels;
}

/// Returns magenta debug pixels for unsupported or invalid blocks.
Uint8List _magentaBlock() {
  final pixels = Uint8List(64);
  for (int i = 0; i < 16; i++) {
    pixels[i * 4] = 255;     // R
    pixels[i * 4 + 1] = 0;   // G
    pixels[i * 4 + 2] = 255; // B
    pixels[i * 4 + 3] = 255; // A
  }
  return pixels;
}

/// Get the subset index for a texel given the number of subsets and partition.
int _getSubset(int numSubsets, int partition, int texelIndex) {
  if (numSubsets == 1) return 0;
  if (numSubsets == 2) return _partitionTable2[partition][texelIndex];
  return _partitionTable3[partition][texelIndex];
}

/// Check if a texel index is an anchor for its subset.
bool _isAnchorIndex(int texelIndex, int subset, int numSubsets, int partition) {
  // Texel 0 is always anchor for subset 0.
  if (texelIndex == 0) return true;

  if (numSubsets == 2) {
    if (subset == 1) return texelIndex == _anchorIndex2[partition];
  } else if (numSubsets == 3) {
    if (subset == 1) return texelIndex == _anchorIndex3a[partition];
    if (subset == 2) return texelIndex == _anchorIndex3b[partition];
  }

  return false;
}

/// Unquantize an endpoint value from [bits] precision to 8 bits.
/// If [pBit] >= 0, it is appended as the LSB before expanding.
int _unquantize(int value, int bits, int pBit) {
  if (pBit >= 0) {
    // Append p-bit as LSB: value becomes (value << 1) | pBit in (bits+1) precision.
    value = (value << 1) | pBit;
    bits = bits + 1;
  }

  if (bits >= 8) return value;
  if (bits == 0) return 0;

  // Replicate high bits into low bits to expand to 8 bits.
  // e.g., for 5-bit value ABCDE -> ABCDEABC (8 bits).
  int result = value << (8 - bits);
  result |= value >> (2 * bits - 8);
  return result & 0xFF;
}

/// Get interpolation weights for a given number of index bits.
List<int> _getWeights(int indexBits) {
  switch (indexBits) {
    case 2:
      return const [0, 21, 43, 64];
    case 3:
      return const [0, 9, 18, 27, 37, 46, 55, 64];
    case 4:
      return const [0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64];
    default:
      return const [0, 64];
  }
}

/// Interpolate between two endpoint values using a weight table and index.
int _interpolate(int e0, int e1, List<int> weights, int index) {
  if (index >= weights.length) index = weights.length - 1;
  final w = weights[index];
  return ((64 - w) * e0 + w * e1 + 32) >> 6;
}
