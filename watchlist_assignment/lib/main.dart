import 'package:flutter/material.dart';

import 'data/market_repository.dart';
import 'domain/watchlist_store.dart';
import 'ui/watchlist_page.dart';

void main() {
  runApp(const WatchlistApp());
}

class WatchlistApp extends StatefulWidget {
  const WatchlistApp({super.key});

  @override
  State<WatchlistApp> createState() => _WatchlistAppState();
}

class _WatchlistAppState extends State<WatchlistApp> {
  late final WatchlistStore _store;

  @override
  void initState() {
    super.initState();
    _store = WatchlistStore(MarketRepository())
      ..init()
      ..start();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '관심종목',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: WatchlistPage(store: _store),
    );
  }
}
