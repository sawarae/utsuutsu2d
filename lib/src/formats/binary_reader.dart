import 'dart:typed_data';
import 'dart:convert';

/// Binary data reader with endianness support
class BinaryReader {
  final ByteData _data;
  int _offset = 0;

  BinaryReader(Uint8List bytes) : _data = ByteData.sublistView(bytes);

  int get offset => _offset;
  int get remaining => _data.lengthInBytes - _offset;
  bool get hasMore => remaining > 0;

  void seek(int position) {
    if (position < 0 || position > _data.lengthInBytes) {
      throw RangeError('Seek position out of range');
    }
    _offset = position;
  }

  void skip(int bytes) {
    _offset += bytes;
  }

  Uint8List readBytes(int count) {
    final bytes = Uint8List.sublistView(_data, _offset, _offset + count);
    _offset += count;
    return bytes;
  }

  int readUint8() => _data.getUint8(_offset++);

  int readUint16BE() {
    final value = _data.getUint16(_offset, Endian.big);
    _offset += 2;
    return value;
  }

  int readUint32BE() {
    final value = _data.getUint32(_offset, Endian.big);
    _offset += 4;
    return value;
  }

  int readUint32LE() {
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  double readFloat32LE() {
    final value = _data.getFloat32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  double readFloat64LE() {
    final value = _data.getFloat64(_offset, Endian.little);
    _offset += 8;
    return value;
  }

  String readString(int length) {
    final bytes = readBytes(length);
    return utf8.decode(bytes, allowMalformed: true);
  }

  String readNullTerminatedString() {
    final bytes = <int>[];
    while (hasMore) {
      final byte = readUint8();
      if (byte == 0) break;
      bytes.add(byte);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
