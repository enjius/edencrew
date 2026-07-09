import 'dart:collection';

import 'package:flutter/material.dart';

import '../domain/quote_state.dart';
import 'format.dart';
import 'sparkline.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.cell});

  final QuoteCell cell;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  static const int _maxPoints = 120;
  final ListQueue<double> _history = ListQueue(_maxPoints);

  @override
  void initState() {
    super.initState();
    _history.add(widget.cell.state.price);
    widget.cell.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.cell.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    final price = widget.cell.state.price;
    if (_history.isNotEmpty && _history.last == price) return;
    if (_history.length >= _maxPoints) _history.removeFirst();
    _history.add(price);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.cell.state.name)),
      body: ListenableBuilder(
        listenable: widget.cell,
        builder: (context, _) {
          final s = widget.cell.state;
          final color = s.isHalted ? const Color(0xFF9E9E9E) : changeColor(s.changePercent);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Text(
                    s.name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Text(s.code, style: const TextStyle(color: Color(0xFF9E9E9E))),
                  if (s.isHalted) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEEEEE),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('거래정지', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Text(
                formatInt(s.price),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${s.changeAmount >= 0 ? '+' : ''}${formatInt(s.changeAmount)}  (${formatPercent(s.changePercent)})',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 120,
                child: Sparkline(values: _history.toList(growable: false), color: color),
              ),
              const SizedBox(height: 24),
              _StatRow(label: '고가', value: formatInt(s.dayHigh)),
              _StatRow(label: '저가', value: formatInt(s.dayLow)),
              _StatRow(label: '전일 종가', value: formatInt(s.previousClose)),
              _StatRow(label: '당일 거래량', value: formatInt(s.dayVolume)),
              _StatRow(label: '상장 주식 수', value: formatInt(s.listedShares)),
            ],
          );
        },
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF757575))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
