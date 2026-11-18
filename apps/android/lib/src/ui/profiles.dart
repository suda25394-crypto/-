import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import 'theme.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    final profile = demoProfiles[selected];
    final reduced = MediaQuery.disableAnimationsOf(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
      children: [
        const Text(
          '我们的档案',
          style: TextStyle(
            color: ink,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.3,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 17),
        Row(
          children: [
            for (var i = 0; i < demoProfiles.length; i++)
              Expanded(
                child: Semantics(
                  selected: selected == i,
                  button: true,
                  child: Material(
                    color: selected == i ? pine : Colors.transparent,
                    child: InkWell(
                      key: Key('profile-$i'),
                      onTap: () => setState(() => selected = i),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: selected == i ? pine : edge,
                          ),
                        ),
                        child: Text(
                          demoProfiles[i].name,
                          style: TextStyle(
                            color: selected == i ? warmSurface : ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 220),
          child: DecoratedBox(
            key: ValueKey(selected),
            decoration: BoxDecoration(color: selected == 0 ? mist : amberWash),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: CustomPaint(painter: _Bookplate(selected)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 16, 13),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '合成档案',
                          style: TextStyle(
                            color: ink,
                            fontSize: 13,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 15),
                        ExcludeSemantics(
                          child: Text(
                            selected == 0 ? 'A' : 'B',
                            style: const TextStyle(
                              fontFamily: 'serif',
                              color: pine,
                              fontSize: 72,
                              height: 1.05,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        for (final (label, value) in [
          ('生活偏好', profile.favorite),
          ('习惯', profile.habit),
          ('相处偏好', profile.preference),
        ])
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: edge)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: quiet,
                      fontSize: 13,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 18,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// Two botanical ex libris marks for the synthetic profiles.
class _Bookplate extends CustomPainter {
  const _Bookplate(this.person);
  final int person;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final scale = size.height / 150;
    canvas.translate(size.width - 135 * scale, size.height);
    canvas.scale(scale, scale);
    final color = person == 0 ? pine : amber;
    final mark = Paint()..color = color;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;

    if (person == 0) {
      final stem = Path()
        ..moveTo(8, 9)
        ..cubicTo(20, -42, 69, -77, 83, -149);
      canvas.drawPath(stem, line);
      for (final (point, angle, length) in [
        (const Offset(16, -16), -.88, 48.0),
        (const Offset(29, -42), .97, 48.0),
        (const Offset(42, -62), -.65, 46.0),
        (const Offset(55, -80), .96, 48.0),
        (const Offset(67, -103), -.51, 42.0),
        (const Offset(76, -123), .85, 32.0),
      ]) {
        canvas.save();
        canvas.translate(point.dx, point.dy);
        canvas.rotate(angle);
        final leaf = Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(-13, -length * .60, 0, -length)
          ..quadraticBezierTo(14, -length * .46, 0, 0)
          ..close();
        canvas.drawPath(leaf, mark);
        canvas.drawLine(
          const Offset(0, -3),
          Offset(-.7, -length * .82),
          Paint()
            ..color = mist
            ..strokeWidth = 1,
        );
        canvas.restore();
      }
    } else {
      final stalks = Path()
        ..moveTo(39, 7)
        ..quadraticBezierTo(71, -42, 71, -92)
        ..moveTo(47, -7)
        ..quadraticBezierTo(17, -26, 14, -57)
        ..moveTo(53, -28)
        ..quadraticBezierTo(97, -39, 108, -63);
      canvas.drawPath(stalks, line);
      for (final (p, radius) in [
        (const Offset(71, -97), 27.0),
        (const Offset(14, -64), 17.0),
        (const Offset(108, -70), 18.0),
      ]) {
        canvas.save();
        canvas.translate(p.dx, p.dy);
        for (var petal = 0; petal < 12; petal++) {
          canvas.rotate(math.pi / 6);
          canvas.drawOval(
            Rect.fromLTWH(-radius * .13, -radius, radius * .26, radius * .75),
            mark,
          );
        }
        canvas.drawCircle(Offset.zero, radius * .16, mark);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Bookplate oldDelegate) => oldDelegate.person != person;
}
