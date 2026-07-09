import 'package:flutter/material.dart';

import '../domain/aggregates.dart';
import '../domain/watchlist_store.dart';
import 'detail_page.dart';
import 'format.dart';

class TopMoversSection extends StatefulWidget {
  const TopMoversSection({super.key, required this.store});

  final WatchlistStore store;

  @override
  State<TopMoversSection> createState() => _TopMoversSectionState();
}

class _TopMoversSectionState extends State<TopMoversSection> {
  static const int _collapsedCount = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store.summary,
      builder: (context, _) {
        final movers = widget.store.summary.topMovers;
        final visible = _expanded
            ? movers.length
            : (movers.length < _collapsedCount ? movers.length : _collapsedCount);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                '🔥 실시간 급상승 TOP 20',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            for (var i = 0; i < visible; i++)
              _MoverRow(
                rank: i + 1,
                mover: movers[i],
                onTap: () => _openDetail(context, movers[i]),
              ),
            if (movers.length > _collapsedCount)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? '접기 ▲' : '더보기 ▼'),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openDetail(BuildContext context, TopMover mover) {
    final cell = widget.store.cellFor(mover.code);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailPage(cell: cell)),
    );
  }
}

class _MoverRow extends StatelessWidget {
  const _MoverRow({required this.rank, required this.mover, this.onTap});

  final int rank;
  final TopMover mover;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = changeColor(mover.changePercent);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: rank <= 3 ? const Color(0xFFD32F2F) : const Color(0xFFBDBDBD),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mover.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              formatInt(mover.price),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: Text(
                formatPercent(mover.changePercent),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
