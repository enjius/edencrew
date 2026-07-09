import 'quote_state.dart';

class SearchIndex {
  SearchIndex._(this._entries);

  final List<_Entry> _entries;

  static const String _chosung = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
  static final Set<String> _chosungSet = _chosung.split('').toSet();

  factory SearchIndex.build(List<QuoteState> states) {
    final entries = <_Entry>[
      for (final s in states)
        _Entry(code: s.code, name: s.name, chosung: _extractChosung(s.name)),
    ];
    return SearchIndex._(entries);
  }

  static String _extractChosung(String name) {
    final buf = StringBuffer();
    for (final ch in name.split('')) {
      final code = ch.codeUnitAt(0);
      if (code >= 0xAC00 && code <= 0xD7A3) {
        buf.write(_chosung[(code - 0xAC00) ~/ 588]);
      } else {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  static bool _isChosung(String ch) => _chosungSet.contains(ch);

  List<String> match(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      return [for (final e in _entries) e.code];
    }
    return [
      for (final e in _entries)
        if (e.code.contains(q) || _nameMatches(e, q)) e.code,
    ];
  }

  bool _nameMatches(_Entry e, String q) {
    final name = e.name;
    final chosung = e.chosung;
    final qn = q.length;
    final nn = name.length;
    if (qn > nn) return false;

    for (var start = 0; start + qn <= nn; start++) {
      var ok = true;
      for (var k = 0; k < qn; k++) {
        final qc = q[k];
        if (_isChosung(qc)) {
          if (chosung[start + k] != qc) {
            ok = false;
            break;
          }
        } else if (name[start + k] != qc) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }
}

class _Entry {
  _Entry({required this.code, required this.name, required this.chosung});

  final String code;
  final String name;
  final String chosung;
}
