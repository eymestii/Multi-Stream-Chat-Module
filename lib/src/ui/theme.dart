import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../generated/streamchat.pbgrpc.dart' as pb;

/// Base gris pizarra neutra: los únicos colores fuertes son los de cada
/// plataforma y los nombres de los usuarios.
abstract final class Palette {
  static const base = Color(0xFF1E2129);
  static const surface = Color(0xFF262A34);
  static const raised = Color(0xFF323744);
  static const hover = Color(0xFF2A2E39);
  static const line = Color(0xFF353A47);
  static const text = Color(0xFFE9E7E2);
  static const muted = Color(0xFF8C91A0);
  static const ok = Color(0xFF6FCF97);
  static const warn = Color(0xFFE5A54B);
  static const twitch = Color(0xFF9146FF);
  static const kick = Color(0xFF53FC18);
}

Color platformColor(pb.Platform p) {
  if (p == pb.Platform.PLATFORM_TWITCH) return Palette.twitch;
  if (p == pb.Platform.PLATFORM_KICK) return Palette.kick;
  return Palette.muted;
}

String platformName(pb.Platform p) {
  if (p == pb.Platform.PLATFORM_TWITCH) return 'Twitch';
  if (p == pb.Platform.PLATFORM_KICK) return 'Kick';
  return 'Desconocida';
}

/// Muchos usuarios eligen colores oscuros que no se leen sobre fondo oscuro:
/// se aclaran conservando el tono.
Color readableNameColor(Color? c, String seed) {
  final color = c ??
      HSLColor.fromAHSL(1, (seed.hashCode % 360).abs().toDouble(), 0.55, 0.65)
          .toColor();
  final hsl = HSLColor.fromColor(color);
  return hsl.lightness < 0.55 ? hsl.withLightness(0.64).toColor() : color;
}

String formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Palette.base,
    colorScheme: const ColorScheme.dark(
      surface: Palette.surface,
      onSurface: Palette.text,
      primary: Palette.text,
      onPrimary: Palette.base,
      secondary: Palette.muted,
      outline: Palette.line,
    ),
    textTheme: GoogleFonts.ibmPlexSansTextTheme(base.textTheme)
        .apply(bodyColor: Palette.text, displayColor: Palette.text),
    dividerColor: Palette.line,
    tooltipTheme:
        const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
  );
}
