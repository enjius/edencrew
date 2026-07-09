import 'package:flutter/material.dart';

import '../domain/watchlist_store.dart';
import 'format.dart';

class SummaryBar extends StatelessWidget {
  const SummaryBar({super.key, required this.store});

  final WatchlistStore store;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ValueListenableBuilder<List<String>>(
            valueListenable: store.visibleCodes,
            builder: (context, codes, _) => _Metric(
              label: '표시 종목',
              value: '${formatInt(codes.length)}개',
            ),
          ),
          ListenableBuilder(
            listenable: store.summary,
            builder: (context, _) => _Metric(
              label: '시가총액 합계',
              value: formatMarketCap(store.summary.totalMarketCap),
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
