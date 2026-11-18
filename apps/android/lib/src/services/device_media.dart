import 'package:flutter/services.dart';

class PickedMedia {
  const PickedMedia(this.name, this.mime, this.data);
  final String name, mime;
  final Uint8List data;
}

class DeviceMedia {
  static const _channel = MethodChannel('couple/device_media');
  static void onPlaybackFailure(void Function(String)? listener) {
    _channel.setMethodCallHandler(
      listener == null
          ? null
          : (call) async {
              if (call.method == 'playbackFailed') {
                listener(call.arguments as String);
              }
            },
    );
  }

  static Future<PickedMedia?> pick({bool imageOnly = false}) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pick', {
      'imageOnly': imageOnly,
    });
    return result == null
        ? null
        : PickedMedia(
            result['name'] as String,
            result['mime'] as String,
            result['data'] as Uint8List,
          );
  }

  static Future<void> record() => _channel.invokeMethod('record');
  static Future<PickedMedia> finish() async => PickedMedia(
    'voice.wav',
    'audio/wav',
    (await _channel.invokeMethod<Uint8List>('finish'))!,
  );
  static Future<void> cancel() => _channel.invokeMethod('cancel');
  static Future<void> play(Uint8List data) =>
      _channel.invokeMethod('play', data);
  static Future<void> stop() => _channel.invokeMethod('stop');
}
