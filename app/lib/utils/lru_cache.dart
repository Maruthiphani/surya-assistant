/// Tiny LRU cache with optional per-entry TTL (CLAUDE.md §9 caching).
///
/// Insertion order of a LinkedHashMap gives us LRU: on access we re-insert to
/// move the key to the most-recent end; on overflow we drop the oldest (first).
class LruCache<K, V> {
  LruCache({this.maxSize = 50, this.ttl});

  final int maxSize;
  final Duration? ttl;
  final _map = <K, _Entry<V>>{};

  V? get(K key) {
    final e = _map.remove(key);
    if (e == null) return null;
    if (ttl != null && DateTime.now().difference(e.at) > ttl!) return null;
    _map[key] = e; // mark most-recently-used
    return e.value;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = _Entry(value, DateTime.now());
    if (_map.length > maxSize) {
      _map.remove(_map.keys.first); // evict oldest
    }
  }

  int get length => _map.length;
  void clear() => _map.clear();
}

class _Entry<V> {
  _Entry(this.value, this.at);
  final V value;
  final DateTime at;
}
