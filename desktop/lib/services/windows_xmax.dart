import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final _bridge = DynamicLibrary.open('realface_xmax.dll');

final _start = _bridge.lookupFunction<
    Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>,
        Pointer<Utf8>, Pointer<Utf8>, Int32),
    Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>,
        Pointer<Utf8>, Pointer<Utf8>, int)>('realface_xmax_start');

final _obsFrame = _bridge.lookupFunction<
    Pointer<Uint8> Function(Pointer<Void>, Pointer<Int32>),
    Pointer<Uint8> Function(
        Pointer<Void>, Pointer<Int32>)>('realface_xmax_obs_frame');

final _poll = _bridge.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('realface_xmax_poll');

final _texture = _bridge.lookupFunction<Int64 Function(Pointer<Void>, Int32),
    int Function(Pointer<Void>, int)>('realface_xmax_texture');

final _stop = _bridge.lookupFunction<Void Function(Pointer<Void>),
    void Function(Pointer<Void>)>('realface_xmax_stop');

final _cameras = _bridge.lookupFunction<Int32 Function(Pointer<Uint8>, Int32),
    int Function(Pointer<Uint8>, int)>('realface_xmax_cameras');

Future<Map<String, String>> listWindowsXmaxCameras() => Isolate.run(
      () => using((arena) {
        const capacity = 65536;
        final buffer = arena<Uint8>(capacity);
        final length = _cameras(buffer, capacity);
        if (length < 0) throw StateError('Could not list Windows cameras.');
        if (length == 0) return <String, String>{};
        final fields = utf8.decode(buffer.asTypedList(length)).split('\u0000');
        return {
          for (var index = 0; index + 1 < fields.length - 1; index += 2)
            fields[index]: fields[index + 1],
        };
      }),
    );

Future<int> startWindowsXmax(
  String token,
  String prompt,
  String reference,
  String camera,
) =>
    Isolate.run(() => using((arena) {
          final error = arena<Uint8>(1024).cast<Utf8>();
          final session = _start(
            token.toNativeUtf8(allocator: arena),
            prompt.toNativeUtf8(allocator: arena),
            reference.toNativeUtf8(allocator: arena),
            camera.toNativeUtf8(allocator: arena),
            error,
            1024,
          );
          if (session == nullptr) throw StateError(error.toDartString());
          return session.address;
        }));

(int, int) windowsXmaxTextures(int address) {
  final session = Pointer<Void>.fromAddress(address);
  return (_texture(session, 0), _texture(session, 1));
}

int pollWindowsXmax(int address) {
  final updated = _poll(Pointer<Void>.fromAddress(address));
  if (updated == -2) {
    throw StateError(
        'Could not start AI generation. Check your connection and try again.');
  }
  if (updated < 0) throw StateError('Could not read native video.');
  return updated;
}

Future<Uint8List?> readWindowsObsFrame(int address) =>
    Isolate.run(() => using((arena) {
          final length = arena<Int32>();
          final bytes = _obsFrame(Pointer<Void>.fromAddress(address), length);
          if (length.value < 0) throw StateError('Could not encode OBS video.');
          return bytes == nullptr
              ? null
              : Uint8List.fromList(bytes.asTypedList(length.value));
        }));

Future<void> stopWindowsXmax(int address) =>
    Isolate.run(() => _stop(Pointer<Void>.fromAddress(address)));
