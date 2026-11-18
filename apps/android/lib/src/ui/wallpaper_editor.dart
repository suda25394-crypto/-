import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:material_ui/material_ui.dart';

import '../services/personal_wallpaper.dart';

Future<void> openWallpaperEditor(
  BuildContext context,
  PersonalWallpaper controller,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(builder: (_) => WallpaperEditor(controller: controller)),
);

class WallpaperEditor extends StatefulWidget {
  const WallpaperEditor({
    super.key,
    required this.controller,
    this.pick = PersonalWallpaper.choose,
  });
  final PersonalWallpaper controller;
  final Future<Uint8List?> Function() pick;
  @override
  State<WallpaperEditor> createState() => _WallpaperEditorState();
}

class _WallpaperEditorState extends State<WallpaperEditor> {
  Uint8List? _candidate;
  bool _changed = false;
  bool _busy = false;
  String? _error;
  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await widget.pick();
      if (mounted && picked != null) {
        setState(() {
          _candidate = picked;
          _changed = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is PlatformException
              ? e.message ?? '无法打开图片，请重新选择。'
              : '这张图片无法打开，请选择另一张。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.apply(_candidate);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '背景保存失败，可以重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('换背景')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final photo = _changed ? _candidate : widget.controller.photo;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('背景预览', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Align(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 245),
                  child: AspectRatio(
                    aspectRatio: 0.85,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xffe5d2eb)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (photo != null)
                              Image.memory(
                                photo,
                                fit: BoxFit.cover,
                                key: const Key('background-preview'),
                              ),
                            Positioned(
                              left: 12,
                              right: 12,
                              top: 12,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Chip(
                                  label: const Text('我们仨'),
                                  backgroundColor: Colors.white,
                                  side: BorderSide.none,
                                ),
                              ),
                            ),
                            const Positioned(
                              left: 12,
                              right: 12,
                              bottom: 12,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Chip(
                                  label: Text('聊天气泡预览'),
                                  backgroundColor: Color(0xfff1e7f6),
                                  side: BorderSide.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '只保存在这台设备的当前账号，伴侣和 DP 看不到。',
                textAlign: TextAlign.center,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('从相册选择'),
              ),
              if (photo != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _candidate = null;
                          _changed = true;
                        }),
                  child: const Text('恢复默认背景'),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy || !_changed ? null : _apply,
                child: const Text('应用背景'),
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
