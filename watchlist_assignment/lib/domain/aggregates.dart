import 'quote_state.dart';

class TopMover {
  const TopMover({
    required this.code,
    required this.name,
    required this.price,
    required this.changePercent,
  });

  final String code;
  final String name;
  final double price;
  final double changePercent;
}

class Aggregates {
  double _totalMarketCap = 0;

  double get totalMarketCap => _totalMarketCap;

  void seed(Iterable<QuoteState> states) {
    var sum = 0.0;
    for (final s in states) {
      sum += s.marketCap;
    }
    _totalMarketCap = sum;
  }

  void onPriceChanged(double oldPrice, double newPrice, int shares) {
    _totalMarketCap += (newPrice - oldPrice) * shares;
  }

  void recomputeTotal(Iterable<QuoteState> states) => seed(states);

  List<TopMover> computeTopMovers(List<QuoteState> all, {int k = 20}) {
    final top = <QuoteState>[];
    for (final s in all) {
      if (top.length < k) {
        _insert(top, s);
      } else if (_higher(s, top[top.length - 1])) {
        top.removeLast();
        _insert(top, s);
      }
    }
    return [
      for (final s in top)
        TopMover(
          code: s.code,
          name: s.name,
          price: s.price,
          changePercent: s.changePercent,
        ),
    ];
  }

  void _insert(List<QuoteState> top, QuoteState s) {
    var i = top.length;
    while (i > 0 && _higher(s, top[i - 1])) {
      i--;
    }
    top.insert(i, s);
  }

  bool _higher(QuoteState a, QuoteState b) {
    final ca = a.changePercent;
    final cb = b.changePercent;
    if (ca != cb) return ca > cb;
    return a.code.compareTo(b.code) < 0;
  }
}
