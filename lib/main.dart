import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:gal/gal.dart';

void main() => runApp(const SquraApp());

class SquraApp extends StatelessWidget {
  const SquraApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Squra',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  XFile? _picked;
  final _picker = ImagePicker();

  // 畫布狀態
  Color _bg = Colors.white;
  double _borderRatio = 0.08; // 0 ~ 0.3
  double _zoom = 1.0;         // 1.0 = 不裁切；>1 開始裁切
  Offset _pan = Offset.zero;  // 拖曳位移（以邏輯像素）
  int _exportSide = 2048;     // 1080 / 2048 / 4096

  // 匯出用
  final GlobalKey _repaintKey = GlobalKey();
  double _stageSize = 0; // 預覽方塊的邏輯邊長（LayoutBuilder 取得）

  Future<void> _pickFromGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (x == null) return;
    setState(() {
      _picked = x;
      _zoom = 1.0;
      _pan = Offset.zero;
    });
  }

  Future<void> _pickFromCamera() async {
    final camGranted = await Permission.camera.request();
    if (!camGranted.isGranted) {
      _toast('Camera permission denied');
      return;
    }
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 100);
    if (x == null) return;
    setState(() {
      _picked = x;
      _zoom = 1.0;
      _pan = Offset.zero;
    });
  }

  Future<void> _save() async {
    if (_picked == null || _stageSize <= 0) return;

    // Android 13+ 會需要照片權限；舊版需要 storage
    var st = await Permission.photos.request();
    if (!st.isGranted) {
      st = await Permission.storage.request();
    }
    if (!st.isGranted) {
      _toast('Need Photos permission');
      return;
    }

    // 將 RepaintBoundary（你看到的預覽）以指定輸出邊長轉為 PNG
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final pixelRatio = _exportSide / _stageSize; // 讓輸出為精準像素邊長
      final ui.Image img = await boundary.toImage(pixelRatio: pixelRatio.clamp(1.0, 8.0));
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      await Gal.putImageBytes(pngBytes);
      _toast('Saved to Photos');
    } catch (e) {
      _toast('Save failed: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _pickColor() async {
    Color tmp = _bg;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Background color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: tmp,
            onColorChanged: (c) => tmp = c,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _bg = tmp), child: const Text('OK')),
        ],
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _picked != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Squra'),
        actions: [
          PopupMenuButton<int>(
            initialValue: _exportSide,
            onSelected: (v) => setState(() => _exportSide = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 1080, child: Text('Export 1080')),
              PopupMenuItem(value: 2048, child: Text('Export 2048')),
              PopupMenuItem(value: 4096, child: Text('Export 4096')),
            ],
          ),
          IconButton(onPressed: _pickColor, icon: const Icon(Icons.color_lens)),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 預覽區：正方形畫布（你看到的就是輸出結果）
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, c) {
                  final side = c.biggest.shortestSide.clamp(200.0, 800.0);
                  if (_stageSize != side) {
                    // 記住預覽方塊邊長（邏輯尺寸）；供存檔時計算像素倍率
                    _stageSize = side;
                  }
                  return SizedBox(
                    width: side,
                    height: side,
                    child: RepaintBoundary(
                      key: _repaintKey,
                      child: Container(
                        color: _bg, // 外框顏色
                        child: hasImage
                            ? _Stage(
                          file: File(_picked!.path),
                          zoom: _zoom,
                          pan: _pan,
                          borderRatio: _borderRatio,
                          onPanUpdate: (d) => setState(() => _pan += d),
                        )
                            : const _Hint(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // 控制列
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _pickFromGallery,
                        icon: const Icon(Icons.photo),
                        label: const Text('Pick'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _pickFromCamera,
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Camera'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: hasImage ? _save : null,
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                      ),
                    ],
                  ),
                  if (hasImage) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Border'),
                        Expanded(
                          child: Slider(
                            value: _borderRatio,
                            min: 0.0,
                            max: 0.3,
                            onChanged: (v) => setState(() => _borderRatio = v),
                          ),
                        ),
                        Text('${(_borderRatio * 100).round()}%'),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('Zoom'),
                        Expanded(
                          child: Slider(
                            value: _zoom,
                            min: 1.0,
                            max: 3.0,
                            onChanged: (v) => setState(() => _zoom = v),
                          ),
                        ),
                        Text('${_zoom.toStringAsFixed(2)}x'),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _zoom = 1.0;
                            _pan = Offset.zero;
                          }),
                          icon: const Icon(Icons.center_focus_strong),
                          label: const Text('Reset'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 預覽舞台：正方形畫布內，先留出邊框，再放可縮放/拖曳的圖片
class _Stage extends StatelessWidget {
  final File file;
  final double zoom;          // 1.0 = contain，不裁切
  final Offset pan;           // 拖曳位移
  final double borderRatio;   // 畫布邊長的比例（0~0.3）
  final ValueChanged<Offset> onPanUpdate;

  const _Stage({
    required this.file,
    required this.zoom,
    required this.pan,
    required this.borderRatio,
    required this.onPanUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final side = c.maxWidth;
        final inner = (1 - 2 * borderRatio).clamp(0.0, 1.0) * side; // 內容區邊長
        return Center(
          child: Container(
            width: inner,
            height: inner,
            color: Colors.transparent,
            child: GestureDetector(
              onPanUpdate: (d) => onPanUpdate(d.delta),
              child: ClipRect(
                child: Transform.translate(
                  offset: pan,
                  child: Transform.scale(
                    scale: zoom,
                    child: Image.file(
                      file,
                      fit: BoxFit.contain, // 以 contain 塞進內容區
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Tap "Pick" to choose a photo',
          style: TextStyle(color: Colors.grey, fontSize: 16)),
    );
  }
}
