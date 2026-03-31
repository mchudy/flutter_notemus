import 'package:flutter/painting.dart';

import '../../../core/core.dart';
import '../../smufl/smufl_metadata_loader.dart';
import '../../theme/music_score_theme.dart';
import '../staff_coordinate_system.dart';
import 'glyph_renderer.dart';

/// Renders barlines by drawing directly on the canvas.
///
/// Uses canvas draw operations instead of font glyphs to ensure barlines
/// align pixel-perfectly with staff lines at all staff space sizes.
class BarlineRenderer {
  // Keep legacy constants for API compatibility.
  static const double barlineHeightMultiplier = 4.0;
  static const double barlineYOffset = -2.0;
  static const double barlineXOffset = 0.0;

  final StaffCoordinateSystem coordinates;
  final SmuflMetadata metadata;
  final MusicScoreTheme theme;
  final GlyphRenderer glyphRenderer;
  final double glyphSize;

  BarlineRenderer({
    required this.coordinates,
    required this.metadata,
    required this.theme,
    required this.glyphRenderer,
    required this.glyphSize,
  });

  void render(Canvas canvas, Barline barline, Offset position) {
    if (barline.type == BarlineType.none) return;

    // Extend by half a staff line thickness so the barline rect fully covers
    // the outermost staff lines (which are drawn with strokeWidth centered on
    // their Y coordinate).
    final staffLineThickness =
        metadata.getEngravingDefault('staffLineThickness') *
        coordinates.staffSpace;
    final topY = coordinates.getStaffLineY(5) - staffLineThickness / 2;
    final bottomY = coordinates.getStaffLineY(1) + staffLineThickness / 2;
    final x = position.dx;

    final thin =
        metadata.getEngravingDefault('thinBarlineThickness') *
        coordinates.staffSpace;
    final thick =
        metadata.getEngravingDefault('thickBarlineThickness') *
        coordinates.staffSpace;
    final separation = coordinates.staffSpace * 0.4;

    switch (barline.type) {
      case BarlineType.single:
        _drawLine(canvas, x, topY, bottomY, thin);
      case BarlineType.double:
      case BarlineType.lightLight:
        _drawLine(canvas, x, topY, bottomY, thin);
        _drawLine(canvas, x + thin + separation, topY, bottomY, thin);
      case BarlineType.final_:
      case BarlineType.lightHeavy:
        _drawLine(canvas, x, topY, bottomY, thin);
        _drawLine(canvas, x + thin + separation, topY, bottomY, thick);
      case BarlineType.heavyLight:
        _drawLine(canvas, x, topY, bottomY, thick);
        _drawLine(canvas, x + thick + separation, topY, bottomY, thin);
      case BarlineType.heavyHeavy:
        _drawLine(canvas, x, topY, bottomY, thick);
        _drawLine(canvas, x + thick + separation, topY, bottomY, thick);
      case BarlineType.heavy:
        _drawLine(canvas, x, topY, bottomY, thick);
      case BarlineType.dashed:
        _drawDashedLine(canvas, x, topY, bottomY, thin);
      case BarlineType.repeatForward:
        _drawLine(canvas, x, topY, bottomY, thick);
        _drawLine(canvas, x + thick + separation, topY, bottomY, thin);
        _drawRepeatDots(
          canvas,
          x + thick + separation + thin + separation,
        );
      case BarlineType.repeatBackward:
        final dotsWidth = coordinates.staffSpace * 0.6;
        _drawRepeatDots(canvas, x);
        _drawLine(canvas, x + dotsWidth + separation, topY, bottomY, thin);
        _drawLine(
          canvas,
          x + dotsWidth + separation + thin + separation,
          topY,
          bottomY,
          thick,
        );
      case BarlineType.repeatBoth:
        final dotsWidth = coordinates.staffSpace * 0.6;
        _drawRepeatDots(canvas, x);
        _drawLine(canvas, x + dotsWidth + separation, topY, bottomY, thin);
        _drawLine(
          canvas,
          x + dotsWidth + separation + thin + separation,
          topY,
          bottomY,
          thick,
        );
        final afterThick =
            x + dotsWidth + separation + thin + separation + thick;
        _drawLine(canvas, afterThick + separation, topY, bottomY, thin);
        _drawRepeatDots(canvas, afterThick + separation + thin + separation);
      case BarlineType.tick:
        final tickBottom = topY + coordinates.staffSpace;
        _drawLine(canvas, x, topY, tickBottom, thin);
      case BarlineType.short_:
        final shortTop = coordinates.getStaffLineY(4);
        final shortBottom = coordinates.getStaffLineY(2);
        _drawLine(canvas, x, shortTop, shortBottom, thin);
      case BarlineType.none:
        break;
    }
  }

  void _drawLine(
    Canvas canvas,
    double x,
    double topY,
    double bottomY,
    double width,
  ) {
    final paint = Paint()
      ..color = theme.barlineColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(x - width / 2, topY, width, bottomY - topY),
      paint,
    );
  }

  void _drawDashedLine(
    Canvas canvas,
    double x,
    double topY,
    double bottomY,
    double width,
  ) {
    final paint = Paint()
      ..color = theme.barlineColor
      ..style = PaintingStyle.fill;
    final dashHeight = coordinates.staffSpace * 0.5;
    final gapHeight = coordinates.staffSpace * 0.5;
    var y = topY;
    while (y < bottomY) {
      final dashEnd = (y + dashHeight).clamp(y, bottomY);
      canvas.drawRect(
        Rect.fromLTWH(x - width / 2, y, width, dashEnd - y),
        paint,
      );
      y += dashHeight + gapHeight;
    }
  }

  void _drawRepeatDots(Canvas canvas, double x) {
    final dotRadius = coordinates.staffSpace * 0.2;
    final paint = Paint()
      ..color = theme.barlineColor
      ..style = PaintingStyle.fill;
    // Dots in spaces 2 and 3 (between lines 2-3 and 3-4).
    final space2Y =
        (coordinates.getStaffLineY(2) + coordinates.getStaffLineY(3)) / 2;
    final space3Y =
        (coordinates.getStaffLineY(3) + coordinates.getStaffLineY(4)) / 2;
    canvas.drawCircle(Offset(x + dotRadius, space2Y), dotRadius, paint);
    canvas.drawCircle(Offset(x + dotRadius, space3Y), dotRadius, paint);
  }
}
