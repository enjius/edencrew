import 'package:flutter/material.dart';

String formatInt(num value) {
  final rounded = value.round();
  final negative = rounded < 0;
  final digits = rounded.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return negative ? '-$buf' : buf.toString();
}

String formatMarketCap(double value) {
  final trillions = value / 1e12;
  return '${formatInt(trillions.round())}조';
}

String formatPercent(double pct) {
  final sign = pct > 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(2)}%';
}

Color changeColor(double pct) {
  if (pct > 0) return const Color(0xFFD32F2F);
  if (pct < 0) return const Color(0xFF1565C0);
  return const Color(0xFF757575);
}
