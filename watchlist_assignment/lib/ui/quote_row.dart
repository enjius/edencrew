import 'package:flutter/material.dart';

import '../domain/quote_state.dart';
import 'format.dart';

class QuoteRow extends StatelessWidget {
  const QuoteRow({super.key, required this.cell, this.onTap});

  final QuoteCell cell;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: cell,
        builder: (context, _) {
          final s = cell.state;
          final halted = s.isHalted;
          final color =
              halted ? const Color(0xFF9E9E9E) : changeColor(s.changePercent);

          return InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                s.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (halted) ...[
                              const SizedBox(width: 6),
                              const _HaltBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.code,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9E9E9E),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Text(
                    formatInt(s.dayVolume),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                  const SizedBox(width: 16),

                  SizedBox(
                    width: 96,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          formatInt(s.price),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: halted ? const Color(0xFF9E9E9E) : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatPercent(s.changePercent),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HaltBadge extends StatelessWidget {
  const _HaltBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFFBDBDBD)),
      ),
      child: const Text(
        '정지',
        style: TextStyle(fontSize: 10, color: Color(0xFF616161)),
      ),
    );
  }
}
