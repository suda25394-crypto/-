import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The folded ginkgo and gallery arch from white-purple-review's canvas artwork.
class GinkgoArt extends CustomPainter {
  const GinkgoArt();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawColor(Colors.white, BlendMode.srcOver);
    final scale = math.max(size.width / 760, size.height / 444);
    canvas.translate(
      (size.width - 760 * scale) / 2,
      (size.height - 444 * scale) * .43,
    );
    canvas.scale(scale);
    const pale = Color(0xfff1e7f6), middle = Color(0xffd9bbdf);
    const violet = Color(0xff8038a0),
        fold = Color(0xffad83b9),
        ink = Color(0xff51465d);
    void stroke(Path path, Color color, double weight) => canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = weight,
    );
    final arch = Path()
      ..moveTo(420, 337)
      ..lineTo(420, 148)
      ..arcToPoint(const Offset(644, 148), radius: const Radius.circular(112))
      ..lineTo(644, 337)
      ..lineTo(620, 337)
      ..lineTo(620, 148)
      ..arcToPoint(
        const Offset(444, 148),
        radius: const Radius.circular(88),
        clockwise: false,
      )
      ..lineTo(444, 337)
      ..close();
    canvas.drawPath(arch, Paint()..color = pale);
    stroke(
      Path()
        ..moveTo(0, 328)
        ..lineTo(173, 328)
        ..moveTo(316, 328)
        ..lineTo(718, 328),
      middle,
      1.3,
    );
    stroke(
      Path()
        ..moveTo(80, 384)
        ..quadraticBezierTo(146, 258, 301, 121)
        ..moveTo(154, 261)
        ..quadraticBezierTo(146, 210, 139, 176),
      ink,
      2.5,
    );
    void leaf(double x, double y, double scale, double angle, Color color) {
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      canvas.scale(scale);
      final outline = Path()
        ..moveTo(0, 0)
        ..cubicTo(-20, -20, -45, -22, -62, -52)
        ..quadraticBezierTo(-63, -59, -54, -57)
        ..quadraticBezierTo(-48, -69, -39, -63)
        ..quadraticBezierTo(-33, -75, -24, -67)
        ..quadraticBezierTo(-18, -78, -11, -70)
        ..lineTo(-2, -57)
        ..lineTo(2, -72)
        ..quadraticBezierTo(9, -81, 17, -73)
        ..quadraticBezierTo(26, -77, 32, -68)
        ..quadraticBezierTo(41, -73, 47, -61)
        ..quadraticBezierTo(55, -65, 59, -54)
        ..cubicTo(52, -28, 20, -19, 0, 0)
        ..close();
      canvas.drawPath(outline, Paint()..color = color);
      stroke(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(-1, -24, -15, -49)
          ..moveTo(0, 0)
          ..quadraticBezierTo(-15, -26, -40, -45)
          ..moveTo(0, 0)
          ..quadraticBezierTo(12, -28, 34, -49),
        Colors.white,
        1.2,
      );
      canvas.restore();
    }

    leaf(145, 207, .89, -.69, middle);
    leaf(230, 167, 1.33, .16, violet);
    leaf(300, 123, .73, .75, fold);
    canvas.restore();
  }

  @override
  bool shouldRepaint(GinkgoArt oldDelegate) => false;
}
