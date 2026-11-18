import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_media.dart';

/// Per-service, per-user local wallpaper, outside the Android backup directory.
class PersonalWallpaper extends ChangeNotifier {
  PersonalWallpaper.forAccount({
    required String endpoint,
    required String userId,
  }) : scope = jsonEncode([
         endpoint.trim().replaceFirst(RegExp(r'/+$'), ''),
         userId,
       ]);
  static const channel = MethodChannel('couple/personal_wallpaper');
  final String scope;
  Uint8List? photo;
  bool _disposed = false;
  int _revision = 0;

  Future<void> load() async {
    final rev = ++_revision;
    try {
      final value = await channel.invokeMethod<Uint8List>('read', {
        'scope': scope,
      });
      if (!_disposed && rev == _revision) {
        photo = value;
        notifyListeners();
      }
    } on PlatformException {
      // The rest of the app remains usable when a device file cannot be read.
    } on MissingPluginException {
      // Desktop and widget previews do not have an Android wallpaper directory.
    }
  }

  Future<void> apply(Uint8List? value) async {
    final rev = ++_revision;
    await channel.invokeMethod<void>(value == null ? 'clear' : 'write', {
      'scope': scope,
      'data': ?value,
    });
    if (!_disposed && rev == _revision) {
      photo = value;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Resize on decode, remove EXIF and retain the photo's own colours.
  static Future<Uint8List?> choose() async {
    final file = await DeviceMedia.pick(imageOnly: true, wallpaper: true);
    if (file == null) return null;
    final buffer = await ui.ImmutableBuffer.fromUint8List(file.data);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width * descriptor.height > 100000000) {
          throw const FormatException('图片尺寸过大');
        }
        final scale = math.min(
          1.0,
          1440 / math.max(descriptor.width, descriptor.height),
        );
        final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()),
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            final data = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (data == null) throw const FormatException('无法读取这张图片');
            return data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }
}
