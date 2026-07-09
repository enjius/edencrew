import 'package:flutter/foundation.dart';

import '../seed/market_models.dart';

class QuoteState {
  QuoteState({
    required this.code,
    required this.name,
    required this.market,
    required this.listedShares,
    required this.previousClose,
    required this.price,
    required this.dayVolume,
    required this.lastTimestampMs,
    this.status = QuoteStatus.active,
    double? dayHigh,
    double? dayLow,
  })  : dayHigh = dayHigh ?? price,
        dayLow = dayLow ?? price;

  factory QuoteState.fromSnapshot(QuoteSnapshotEntry e) {
    return QuoteState(
      code: e.info.code,
      name: e.info.name,
      market: e.info.market,
      listedShares: e.info.listedShares,
      previousClose: e.previousClose,
      price: e.price,
      dayVolume: e.dayVolume,
      lastTimestampMs: -1,
    );
  }

  final String code;
  final String name;
  final MarketType market;
  final int listedShares;
  final double previousClose;

  double price;
  int dayVolume;
  int lastTimestampMs;
  QuoteStatus status;

  double dayHigh;
  double dayLow;

  double get changeAmount => price - previousClose;

  double get changePercent =>
      previousClose == 0 ? 0 : (price - previousClose) / previousClose * 100;

  double get marketCap => price * listedShares;

  bool get isHalted => status == QuoteStatus.halted;
}

class QuoteCell extends ChangeNotifier {
  QuoteCell(this.state);

  final QuoteState state;

  bool applyTick(QuoteTick tick) {
    final s = state;
    if (tick.timestampMs < s.lastTimestampMs) {
      return false;
    }

    final priceChanged = tick.price != s.price;
    final volumeChanged = tick.dayVolume != s.dayVolume;
    final statusChanged = tick.status != s.status;

    s.lastTimestampMs = tick.timestampMs;
    s.price = tick.price;
    s.dayVolume = tick.dayVolume;
    s.status = tick.status;
    if (tick.price > s.dayHigh) s.dayHigh = tick.price;
    if (tick.price < s.dayLow) s.dayLow = tick.price;

    final changed = priceChanged || volumeChanged || statusChanged;
    if (changed) notifyListeners();
    return changed;
  }
}
