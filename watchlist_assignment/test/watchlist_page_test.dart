import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchlist_assignment/data/market_repository.dart';
import 'package:watchlist_assignment/domain/watchlist_store.dart';
import 'package:watchlist_assignment/ui/watchlist_page.dart';

void main() {
  testWidgets('목록 화면이 조립되고 첫 종목이 렌더된다', (tester) async {

    final store = WatchlistStore(MarketRepository())..init();
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(home: WatchlistPage(store: store)));

    expect(find.text('가온전자'), findsWidgets);

    expect(find.text('2,000개'), findsOneWidget);
  });
}
