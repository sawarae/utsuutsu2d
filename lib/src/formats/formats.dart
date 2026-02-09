/// Formats module for utsutsu2d
library;

export 'bc7_decoder.dart';
export 'binary_reader.dart';
export 'inp_parser.dart';
export 'inx_parser.dart';
export 'inx_exporter.dart';

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/model.dart';
import 'inp_parser.dart';

// Conditionally export file loading (not available on web)
export 'model_loader_io.dart' if (dart.library.html) 'model_loader_stub.dart';

/// Top-level function for compute() - parses model bytes
Model _parseModelBytes(_ParseModelArgs args) {
  return ModelLoader.loadFromBytes(args.bytes, args.filename);
}

/// Arguments for _parseModelBytes (must be serializable for isolate)
class _ParseModelArgs {
  final Uint8List bytes;
  final String? filename;
  _ParseModelArgs(this.bytes, this.filename);
}

/// Unified model loader
class ModelLoader {
  /// Load model from bytes asynchronously using compute() for better performance
  static Future<Model> loadFromBytesAsync(Uint8List bytes, [String? filename]) {
    return compute(_parseModelBytes, _ParseModelArgs(bytes, filename));
  }

  /// Load model from bytes (works on all platforms including web)
  static Model loadFromBytes(Uint8List bytes, [String? filename]) {
    // Check for TRNSRTS binary format (INP/INX)
    if (_isTrnsrtsFormat(bytes)) {
      return InpParser.parse(bytes);
    }

    // Check for ZIP archive (older INP format)
    if (_isZipArchive(bytes)) {
      return InpParser.parse(bytes);
    }

    // Try to detect by filename
    if (filename != null) {
      final ext = filename.toLowerCase();
      if (ext.endsWith('.inp') || ext.endsWith('.inx')) {
        // Both INP and INX use InpParser for TRNSRTS format
        return InpParser.parse(bytes);
      }
    }

    throw FormatException('Unknown file format: does not match TRNSRTS or ZIP signatures');
  }

  static bool _isTrnsrtsFormat(Uint8List bytes) {
    if (bytes.length < 8) return false;
    return bytes[0] == 0x54 && // T
        bytes[1] == 0x52 && // R
        bytes[2] == 0x4E && // N
        bytes[3] == 0x53 && // S
        bytes[4] == 0x52 && // R
        bytes[5] == 0x54 && // T
        bytes[6] == 0x53 && // S
        bytes[7] == 0x00; // \0
  }

  static bool _isZipArchive(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }
}
