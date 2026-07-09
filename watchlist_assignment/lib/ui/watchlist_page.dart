import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/watchlist_store.dart';
import 'detail_page.dart';
import 'quote_row.dart';
import 'summary_bar.dart';
import 'top_movers_section.dart';

class WatchlistPage extends StatefulWidget {
  const WatchlistPage({super.key, required this.store});

  final WatchlistStore store;

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      widget.store.search(value);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final totalCount = store.allStates.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('관심종목'),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: '종목명·초성·코드 검색 (예: ㄱㅇ, 전자, 000590)',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          _ErrorBanner(store: store),
          SummaryBar(store: store),
          const Divider(height: 1),
          Expanded(
            child: ValueListenableBuilder<List<String>>(
              valueListenable: store.visibleCodes,
              builder: (context, codes, _) {
                final searching = codes.length != totalCount;
                return CustomScrollView(
                  slivers: [
                    if (!searching)
                      SliverToBoxAdapter(child: TopMoversSection(store: store)),
                    SliverToBoxAdapter(
                      child: _SectionHeader(
                        searching
                            ? '검색 결과 ${codes.length}종목'
                            : '전체 관심종목',
                      ),
                    ),
                    if (codes.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('검색 결과가 없습니다.')),
                        ),
                      )
                    else
                      SliverFixedExtentList(
                        itemExtent: 60,
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final cell = store.cellFor(codes[i]);
                            return QuoteRow(
                              cell: cell,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DetailPage(cell: cell),
                                ),
                              ),
                            );
                          },
                          childCount: codes.length,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF757575),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.store});

  final WatchlistStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store.summary,
      builder: (context, _) {
        if (!store.summary.hasFeedError) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: const Color(0xFFFFF3E0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFE65100)),
              SizedBox(width: 6),
              Text(
                '일시적 피드 오류 — 자동 복구 중',
                style: TextStyle(fontSize: 12, color: Color(0xFFE65100)),
              ),
            ],
          ),
        );
      },
    );
  }
}
