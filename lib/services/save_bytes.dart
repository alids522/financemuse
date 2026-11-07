import 'dart:typed_data';

import 'save_bytes_stub.dart'
    if (dart.library.io) 'save_bytes_io.dart'
    if (dart.library.html) 'save_bytes_web.dart';

/// Save bytes as a downloadable file on the current platform.
/// Web: browser download. Mobile/desktop: writes to the app documents dir.
Future<String> saveBytes(Uint8List bytes, String filename) =>
    saveBytesImpl(bytes, filename);
