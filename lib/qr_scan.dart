/// Reading QR codes, from the camera or from an image (a screenshot, a photo someone sent).
///
/// The desktop reads only images, because a laptop's camera faces its user. A phone's faces the
/// code, so scanning is what "Scan QR" means here; an image is kept for the link that arrived as
/// a screenshot. Either way the text goes into the Link tab like a paste, so there is no second
/// import path to keep honest.
///
/// Decoding is `zxing2`, a pure-Dart port of ZXing (pinned exactly), rather than ML Kit, which is
/// proprietary and cannot be built from source for F-Droid. Frames and images are decoded off the
/// UI thread, and nothing is kept or sent anywhere.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zxing2/qrcode.dart';

import 'tones.dart';

/// Greyscale pixels, one byte each, packed row after row: the camera's Y plane already is this.
class _Luma extends LuminanceSource {
  _Luma(this.data, int width, int height) : super(width, height);
  final Int8List data;

  @override
  Int8List getRow(int y, Int8List? row) {
    final out = row != null && row.length >= width ? row : Int8List(width);
    out.setRange(0, width, data, y * width);
    return out;
  }

  @override
  Int8List getMatrix() => data;
}

/// One frame or image: luminance, size, and whether to try hard (an image is read once, so it
/// can afford it; a camera frame is followed by another in a moment).
typedef _Job = ({Int8List luma, int width, int height, bool hard});

/// Both ways round, because a code screenshotted from a dark-mode app is often light-on-dark.
String? _decode(_Job job) {
  final hints = DecodeHints();
  if (job.hard) hints.put(DecodeHintType.tryHarder);
  final source = _Luma(job.luma, job.width, job.height);
  for (final s in [source, source.invert()]) {
    try {
      return QRCodeReader()
          .decode(BinaryBitmap(HybridBinarizer(s)), hints: hints)
          .text;
    } on ReaderException {
      continue;
    }
  }
  return null;
}

/// Reads a QR code out of greyscale pixels, one byte each, row after row; null when none.
String? decodeQrLuma(Int8List luma, int width, int height) =>
    _decode((luma: luma, width: width, height: height, hard: true));

/// Reads a QR code out of an encoded image, or null when there is none. A large photo is scaled
/// down first: a code needs a few pixels per module, not a 48-megapixel sensor's worth.
Future<String?> readQrImage(Uint8List encoded) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  const longest = 1600;
  final wide = descriptor.width >= descriptor.height;
  final shrink = (wide ? descriptor.width : descriptor.height) > longest;
  final codec = await descriptor.instantiateCodec(
    targetWidth: shrink && wide ? longest : null,
    targetHeight: shrink && !wide ? longest : null,
  );
  final image = (await codec.getNextFrame()).image;
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final (w, h) = (image.width, image.height);
  image.dispose();
  return compute(_decode, (
    luma: _lumaFromRgba(rgba.buffer.asUint8List(), w * h, 4, 0),
    width: w,
    height: h,
    hard: true,
  ));
}

/// Luminance from 4-byte pixels; [red] is the red channel's offset (RGBA 0, BGRA 2).
Int8List _lumaFromRgba(Uint8List px, int count, int stride, int red) {
  final luma = Int8List(count);
  final blue = 2 - red;
  for (var i = 0, o = 0; i < count; i++, o += stride) {
    luma[i] = (px[o + red] * 77 + px[o + 1] * 150 + px[o + blue] * 29) >> 8;
  }
  return luma;
}

/// The live camera, reading every frame it can until one holds a code, then reporting it once.
class QrCameraView extends StatefulWidget {
  const QrCameraView({super.key, required this.onFound});
  final ValueChanged<String> onFound;

  @override
  State<QrCameraView> createState() => _QrCameraViewState();
}

class _QrCameraViewState extends State<QrCameraView>
    with WidgetsBindingObserver {
  CameraController? camera;
  String? problem;
  bool busy = false, found = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    camera?.dispose();
    super.dispose();
  }

  /// The camera is released while the app is in the background, as Android expects, and taken
  /// again on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final c = camera;
      camera = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && camera == null && !found) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return _fail('This phone has no camera to scan with.');
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final c = CameraController(
        back,
        // Medium is plenty for a code held up to the lens, and keeps each frame quick to read.
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        camera = c;
        problem = null;
      });
      await c.startImageStream(_frame);
    } on CameraException catch (e) {
      _fail(switch (e.code) {
        'CameraAccessDenied' ||
        'CameraAccessDeniedWithoutPrompt' ||
        'CameraAccessRestricted' => 'Camera access is off. Allow it in Settings, or choose an image instead.',
        _ => "The camera didn't start: ${e.description ?? e.code}",
      });
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => problem = message);
  }

  /// Frames arrive faster than they can be read; one is read at a time and the rest dropped.
  Future<void> _frame(CameraImage frame) async {
    if (busy || found) return;
    busy = true;
    try {
      final text = await compute(_decode, _jobFor(frame));
      if (text != null && !found && mounted) {
        found = true;
        await camera?.stopImageStream();
        widget.onFound(text);
      }
    } finally {
      busy = false;
    }
  }

  _Job _jobFor(CameraImage f) {
    final (w, h) = (f.width, f.height);
    final plane = f.planes.first;
    if (f.format.group == ImageFormatGroup.bgra8888) {
      return (
        luma: _lumaFromRgba(
          _packed(plane.bytes, w * 4, h, plane.bytesPerRow),
          w * h,
          4,
          2,
        ),
        width: w,
        height: h,
        hard: false,
      );
    }
    // YUV: the first plane is the luminance, rows padded to bytesPerRow.
    final y = _packed(plane.bytes, w, h, plane.bytesPerRow);
    return (
      luma: Int8List.view(y.buffer, y.offsetInBytes, w * h),
      width: w,
      height: h,
      hard: false,
    );
  }

  /// Rows of [rowBytes] each, without the padding a stride may add.
  Uint8List _packed(Uint8List bytes, int rowBytes, int rows, int stride) {
    if (stride == rowBytes) {
      return Uint8List.sublistView(bytes, 0, rowBytes * rows);
    }
    final out = Uint8List(rowBytes * rows);
    for (var r = 0; r < rows; r++) {
      out.setRange(r * rowBytes, (r + 1) * rowBytes, bytes, r * stride);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = camera;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: Colors.black,
        height: 260,
        width: double.infinity,
        child: problem != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    problem!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              )
            : c == null || !c.value.isInitialized
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  // The preview fills the box and its overflow is cropped, as a camera app's does.
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: c.value.previewSize!.height,
                      height: c.value.previewSize!.width,
                      child: CameraPreview(c),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Text(
                      found ? 'Read' : 'Point at a QR code',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: found ? green : Colors.white,
                        fontWeight: FontWeight.w700,
                        shadows: const [Shadow(blurRadius: 6)],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
