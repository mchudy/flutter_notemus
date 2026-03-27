// lib/src/rendering/renderers/chord_renderer.dart
// VERSÃO REFATORADA: Usa StaffPositionCalculator e BaseGlyphRenderer
//
// MELHORIAS IMPLEMENTADAS (Fase 2):
// ✅ Usa StaffPositionCalculator unificado (elimina 42 linhas duplicadas)
// ✅ Herda de BaseGlyphRenderer para renderização consistente
// ✅ Usa drawGlyphWithBBox para 100% conformidade SMuFL
// ✅ Cache automático de TextPainters para melhor performance

import 'package:flutter/material.dart';

import '../../../core/core.dart'; // 🆕 Tipos do core
import '../../smufl/smufl_metadata_loader.dart';
import '../../theme/music_score_theme.dart';
import '../staff_coordinate_system.dart';
import '../staff_position_calculator.dart';
import 'base_glyph_renderer.dart';
import 'note_renderer.dart';

class ChordRenderer extends BaseGlyphRenderer {
  final MusicScoreTheme theme;
  final double staffLineThickness;
  final double stemThickness;
  final NoteRenderer noteRenderer;

  // ignore: use_super_parameters
  ChordRenderer({
    required StaffCoordinateSystem coordinates,
    required SmuflMetadata metadata,
    required this.theme,
    required double glyphSize,
    required this.staffLineThickness,
    required this.stemThickness,
    required this.noteRenderer,
  }) : super(
         coordinates: coordinates,
         metadata: metadata,
         glyphSize: glyphSize,
       );

  void render(
    Canvas canvas,
    Chord chord,
    Offset basePosition,
    Clef currentClef, {
    int? voiceNumber,
  }) {
    final sortedNotes = [...chord.notes]
      ..sort(
        (a, b) => StaffPositionCalculator.calculate(
          b.pitch,
          currentClef,
        ).compareTo(StaffPositionCalculator.calculate(a.pitch, currentClef)),
      );

    final positions = sortedNotes
        .map((n) => StaffPositionCalculator.calculate(n.pitch, currentClef))
        .toList();

    // Determine stem direction
    final stemUp = _getStemDirection(chord, positions, voiceNumber);

    // ── Notehead offsets for adjacent seconds ──
    final Map<int, double> xOffsets = {};
    final actualGlyph = chord.duration.type.glyphName;
    final noteheadInfo = metadata.getGlyphInfo(actualGlyph) ??
        metadata.getGlyphInfo('noteheadBlack');
    final noteWidth = noteheadInfo?.boundingBox?.width ?? 1.18;

    final isWhole = chord.duration.type == DurationType.whole;
    final offsetRight = isWhole || stemUp;

    for (int i = 0; i < sortedNotes.length; i++) {
      xOffsets[i] = 0.0;
      if (i > 0 && (positions[i - 1] - positions[i]).abs() <= 1) {
        if (xOffsets[i - 1] == 0.0) {
          // Use ~80% of notehead width so adjacent notes touch/overlap
          // slightly, matching standard engraving practice.
          final offset = noteWidth * 0.8 * coordinates.staffSpace;
          xOffsets[i] = offsetRight ? offset : -offset;
        }
      }
    }

    // ── Compute accidental columns BEFORE drawing anything ──
    // All accidentals are placed to the LEFT of the leftmost notehead.
    // Each accidental gets a column (0 = closest to notes, higher = further left).
    // Two accidentals collide vertically if within 6 staff positions.
    final accidentalColumns = <int, int>{};
    const collisionDistance = 6;

    for (int i = 0; i < sortedNotes.length; i++) {
      if (sortedNotes[i].pitch.accidentalGlyph == null) {
        continue;
      }

      int column = 0;
      for (int c = 0; c < sortedNotes.length; c++) {
        bool collision = false;
        for (final entry in accidentalColumns.entries) {
          if (entry.value == c &&
              (positions[i] - positions[entry.key]).abs() <= collisionDistance) {
            collision = true;
            break;
          }
        }
        if (!collision) {
          column = c;
          break;
        }
        column = c + 1;
      }
      accidentalColumns[i] = column;
    }

    // ── Draw accidentals ──
    // All accidentals are positioned relative to basePosition.dx (the chord's
    // x position), NOT relative to individual note offsets. This ensures all
    // accidentals are to the LEFT of ALL noteheads.
    for (final entry in accidentalColumns.entries) {
      final i = entry.key;
      final column = entry.value;
      final note = sortedNotes[i];
      final accidentalGlyph = note.pitch.accidentalGlyph!;
      final accidentalWidth = metadata.getGlyphWidth(accidentalGlyph);

      const clearance = 0.25; // clearance between accidental and noteheads
      final baseOffset = (accidentalWidth + clearance) * coordinates.staffSpace;
      final columnSpacing =
          (accidentalWidth + clearance) * coordinates.staffSpace;

      final noteY = StaffPositionCalculator.toPixelY(
        positions[i],
        coordinates.staffSpace,
        coordinates.staffBaseline.dy,
      );

      // Position relative to the chord's base x, not the note's offset x.
      final accidentalX = basePosition.dx - baseOffset - (column * columnSpacing);

      drawGlyphWithBBox(
        canvas,
        glyphName: accidentalGlyph,
        position: Offset(accidentalX, noteY),
        color: theme.accidentalColor ?? theme.noteheadColor,
        options: const GlyphDrawOptions(trackBounds: true),
      );
    }

    // ── Draw noteheads and ledger lines ──
    for (int i = 0; i < sortedNotes.length; i++) {
      final note = sortedNotes[i];
      final staffPos = positions[i];
      final noteY = StaffPositionCalculator.toPixelY(
        staffPos,
        coordinates.staffSpace,
        coordinates.staffBaseline.dy,
      );
      final xOffset = xOffsets[i]!;

      _drawLedgerLines(canvas, basePosition.dx + xOffset, staffPos);

      // Shift noteheads up slightly to center them on staff lines.
      // The Bravura font's reported metrics cause drawGlyphWithBBox to
      // place noteheads ~0.15 staff spaces too low.
      final correctedNoteY = noteY - coordinates.staffSpace * 0.15;
      drawGlyphWithBBox(
        canvas,
        glyphName: note.duration.type.glyphName,
        position: Offset(basePosition.dx + xOffset, correctedNoteY),
        color: theme.noteheadColor,
        options: GlyphDrawOptions.noteheadDefault,
      );
    }

    // ── Draw stem ──
    if (chord.duration.type != DurationType.whole) {
      final extremeNote = stemUp ? sortedNotes.last : sortedNotes.first;
      final extremePos = StaffPositionCalculator.calculate(
        extremeNote.pitch,
        currentClef,
      );
      final extremeY = StaffPositionCalculator.toPixelY(
        extremePos,
        coordinates.staffSpace,
        coordinates.staffBaseline.dy,
      );
      final extremeNoteIndex = sortedNotes.indexOf(extremeNote);
      final stemXOffset = xOffsets[extremeNoteIndex]!;
      final noteheadGlyph = chord.duration.type.glyphName;
      final beamCount = _getBeamCount(chord.duration.type);
      final sortedPositions = positions;
      final customStemLength = noteRenderer.positioningEngine.calculateChordStemLength(
        noteStaffPositions: sortedPositions,
        stemUp: stemUp,
        beamCount: beamCount,
      );
      final stemEnd = _renderChordStem(
        canvas,
        Offset(basePosition.dx + stemXOffset, extremeY),
        noteheadGlyph,
        stemUp,
        customStemLength,
      );
      if (chord.duration.type.value < 0.25) {
        noteRenderer.flagRenderer.render(
          canvas,
          stemEnd,
          chord.duration.type,
          stemUp,
        );
      }
    }
  }

  int _getBeamCount(DurationType duration) {
    return switch (duration) {
      DurationType.eighth => 1,
      DurationType.sixteenth => 2,
      DurationType.thirtySecond => 3,
      DurationType.sixtyFourth => 4,
      _ => 0,
    };
  }

  void _drawLedgerLines(Canvas canvas, double x, int staffPosition) {
    if (!theme.showLedgerLines) return;

    final ledgerPositions = StaffPositionCalculator.getLedgerLinePositions(staffPosition);

    if (ledgerPositions.isEmpty) return;

    final paint = Paint()
      ..color = theme.staffLineColor
      ..strokeWidth = staffLineThickness;

    // Ledger lines must extend beyond the notehead on both sides.
    // Whole notes are ~1.7 staffSpaces wide, so half-width needs to be
    // at least 1.0 to be visible beyond the notehead edges.
    final halfWidth = coordinates.staffSpace * 1.1;

    for (final linePos in ledgerPositions) {
      final y = StaffPositionCalculator.toPixelY(
        linePos,
        coordinates.staffSpace,
        coordinates.staffBaseline.dy,
      );
      canvas.drawLine(
        Offset(x - halfWidth, y),
        Offset(x + halfWidth, y),
        paint,
      );
    }
  }

  Offset _renderChordStem(
    Canvas canvas,
    Offset notePosition,
    String noteheadGlyph,
    bool stemUp,
    double customStemLength,
  ) {
    final stemColor = theme.stemColor ?? theme.noteheadColor;

    final anchors = metadata.getGlyphAnchors(noteheadGlyph);

    double stemX;
    if (stemUp) {
      final anchor = anchors?.getAnchor('stemUpSE');
      if (anchor != null) {
        stemX = notePosition.dx + (anchor.dx * coordinates.staffSpace);
      } else {
        final noteheadWidth = metadata.getGlyphWidthInPixels(
          noteheadGlyph,
          coordinates.staffSpace,
        );
        stemX = notePosition.dx + noteheadWidth;
      }
    } else {
      final anchor = anchors?.getAnchor('stemDownNW');
      if (anchor != null) {
        stemX = notePosition.dx + (anchor.dx * coordinates.staffSpace);
      } else {
        stemX = notePosition.dx;
      }
    }

    final stemDirection = stemUp ? -1.0 : 1.0;
    final stemLength = customStemLength * coordinates.staffSpace;
    final stemEnd = Offset(stemX, notePosition.dy + stemDirection * stemLength);

    canvas.drawLine(
      Offset(stemX, notePosition.dy),
      stemEnd,
      Paint()
        ..color = stemColor
        ..strokeWidth = stemThickness,
    );

    return stemEnd;
  }

  bool _getStemDirection(Chord chord, List<int> positions, int? voiceNumber) {
    if (voiceNumber != null) {
      return voiceNumber.isOdd;
    }

    if (chord.voice != null) {
      return chord.voice!.isOdd;
    }

    final mostExtremePos = positions.reduce(
      (a, b) => a.abs() > b.abs() ? a : b,
    );
    return mostExtremePos > 0;
  }
}
