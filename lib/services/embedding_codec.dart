import 'dart:convert';
import 'dart:typed_data';

/// Provides high-performance encoding and decoding for vector embeddings.
class EmbeddingCodec {
  /// Encodes a List of doubles to a Base64 string.
  ///
  /// This approach is significantly faster than standard `jsonEncode()`
  /// and uses less storage space, making it ideal for storing high-dimensional
  /// vectors in SQLite.
  static String encode(List<double> embedding) {
    return base64Encode(Float64List.fromList(embedding).buffer.asUint8List());
  }

  /// Decodes a Base64 string back to a List of doubles.
  static List<double> decode(String encodedString) {
    // If it's a JSON array format (legacy support), use jsonDecode.
    if (encodedString.startsWith('[')) {
      return (jsonDecode(encodedString) as List).cast<double>();
    }

    // Decode from base64 float64list
    return Float64List.view(base64Decode(encodedString).buffer).toList();
  }
}
