import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final _program = DynamicLibrary.executable();
final _open = _program.lookupFunction<Int32 Function(Int32, Int32),
    int Function(int, int)>('realface_open_ai_output');
final _submit = _program.lookupFunction<
    Int32 Function(Int32, Int32, Pointer<Uint8>),
    int Function(int, int, Pointer<Uint8>)>('realface_submit_ai_frame');
final _close = _program.lookupFunction<Void Function(), void Function()>(
    'realface_close_ai_output');

class WindowsAiOutput {
  Pointer<Uint8> _pixels = nullptr;
  int _capacity = 0;
  bool _opened = false;

  bool present(Uint8List packet) {
    if (packet.length < 8) return false;
    final header = ByteData.sublistView(packet, 0, 8);
    final width = header.getUint32(0, Endian.little);
    final height = header.getUint32(4, Endian.little);
    final bytes = width * height * 4;
    if (width < 1 ||
        width > 960 ||
        height < 1 ||
        height > 540 ||
        packet.length != bytes + 8) {
      return false;
    }

    if (!_opened) {
      _opened = _open(width, height) != 0;
      if (!_opened) return false;
    }
    if (bytes > _capacity) {
      if (_pixels != nullptr) calloc.free(_pixels);
      _pixels = calloc<Uint8>(bytes);
      _capacity = bytes;
    }
    _pixels.asTypedList(bytes).setRange(0, bytes, packet, 8);
    return _submit(width, height, _pixels) != 0;
  }

  void close() {
    if (_opened) _close();
    _opened = false;
    if (_pixels != nullptr) calloc.free(_pixels);
    _pixels = nullptr;
    _capacity = 0;
  }
}
