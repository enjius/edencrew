import 'dart:async';

import 'package:flutter/material.dart';

import '../seed/market_feed.dart';
import '../seed/market_models.dart';
import '../ui/format.dart';

class _Holder {
  _Holder({
    required this.name,
    required this.code,
    required this.listedShares,
    required this.previousClose,
    required this.price,
    required this.dayVolume,
  });

  final String name;
  final String code;
  final int listedShares;
  final double previousClose;
  double price;
  int dayVolume;
  QuoteStatus status = QuoteStatus.active;

  double get changePercent =>
      previousClose == 0 ? 0 : (price - previousClose) / previousClose * 100;
  double get marketCap => price * listedShares;
}

class NaiveWatchlistPage extends StatefulWidget {
  const NaiveWatchlistPage({super.key, required this.feed, this.autoStart = true});

  final MarketFeed feed;
  final bool autoStart;

  @override
  State<NaiveWatchlistPage> createState() => _NaiveWatchlistPageState();
}

class _NaiveWatchlistPageState extends State<NaiveWatchlistPage> {
  final Map<String, _Holder> _data = {};
  final List<String> _codes = [];
  StreamSubscription<List<QuoteTick>>? _sub;

  @override
  void initState() {
    super.initState();
    for (final e in widget.feed.initialSnapshot()) {
      _data[e.info.code] = _Holder(
        name: e.info.name,
        code: e.info.code,
        listedShares: e.info.listedShares,
        previousClose: e.previousClose,
        price: e.price,
        dayVolume: e.dayVolume,
      );
      _codes.add(e.info.code);
    }
    _sub = widget.feed.ticks.listen(_onBatch, onError: (_) {});
    if (widget.autoStart) widget.feed.start();
  }

  void _onBatch(List<QuoteTick> batch) {
    for (final t in batch) {
      final h = _data[t.code];
      if (h == null) continue;
      h.price = t.price;
      h.dayVolume = t.dayVolume;
      h.status = t.status;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var totalCap = 0.0;
    for (final code in _codes) {
      totalCap += _data[code]!.marketCap;
    }

    final sorted = _codes.map((c) => _data[c]!).toList()
      ..sort((a, b) => b.changePercent.compareTo(a.changePercent));
    final top20 = sorted.take(20).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('관심종목 (baseline)')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '표시 ${formatInt(_codes.length)}개    시총 ${formatMarketCap(totalCap)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final h in top20)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: Text(
                        '${h.name} ${formatPercent(h.changePercent)}',
                        style: TextStyle(color: changeColor(h.changePercent)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemExtent: 96,
              itemCount: _codes.length,
              itemBuilder: (context, i) {
                final h = _data[_codes[i]]!;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(h.name,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            Text(h.code,
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF9E9E9E))),
                          ],
                        ),
                      ),
                      Text(formatInt(h.dayVolume),
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF9E9E9E))),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 96,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(formatInt(h.price),
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            Text(formatPercent(h.changePercent),
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: changeColor(h.changePercent))),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
