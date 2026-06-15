import 'package:flutter/material.dart';
import 'package:ichibase/ichibase.dart';

import '../widgets/result_view.dart';
import '../widgets/section_card.dart';

/// MongoDB CRUD demo on an `orders` collection.
class MongoScreen extends StatefulWidget {
  const MongoScreen({super.key});

  @override
  State<MongoScreen> createState() => _MongoScreenState();
}

class _MongoScreenState extends State<MongoScreen> {
  static const _collection = 'orders';

  final _item = TextEditingController();
  final _total = TextEditingController();

  List<Map<String, dynamic>> _docs = [];
  IchibaseResponse<dynamic>? _result;
  bool _busy = false;

  MongoCollection get _orders =>
      Ichibase.instance.mongo.collection(_collection);

  @override
  void dispose() {
    _item.dispose();
    _total.dispose();
    super.dispose();
  }

  Future<void> _wrap(
    Future<IchibaseResponse<dynamic>> Function() action, {
    String? success,
    bool reloadAfter = true,
  }) async {
    setState(() => _busy = true);
    try {
      final res = await action();
      if (!mounted) return;
      setState(() => _result = res);
      if (!res.ok) {
        _snack('${res.error?.code}: ${res.error?.detail}', error: true);
      } else if (success != null) {
        _snack(success);
      }
      if (res.ok && reloadAfter) await _find(setResult: false);
    } catch (e) {
      if (mounted) _snack('Unexpected error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _find({bool setResult = true}) async {
    final res = await _orders.find(const {}, sort: {'_id': -1}, limit: 50);
    if (!mounted) return;
    setState(() {
      if (setResult) _result = res;
      _docs = _extractDocs(res.data);
    });
    if (!res.ok && setResult) {
      _snack('${res.error?.code}: ${res.error?.detail}', error: true);
    }
  }

  /// Mongo responses can be a bare List or `{documents: [...]}` / `{rows: ...}`.
  List<Map<String, dynamic>> _extractDocs(dynamic data) {
    List? list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      list = (data['documents'] ?? data['rows'] ?? data['data']) as List?;
    }
    return (list ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<void> _insert() async {
    final item = _item.text.trim();
    final total = num.tryParse(_total.text.trim());
    if (item.isEmpty || total == null) {
      _snack('Enter an item and a numeric total.', error: true);
      return;
    }
    await _wrap(
      () => _orders.insertOne({'item': item, 'total': total}),
      success: 'Inserted.',
    );
    if (mounted) {
      _item.clear();
      _total.clear();
    }
  }

  /// Update by `_id`. Mongo `_id` usually serializes as `{"\$oid": "..."}`; we
  /// echo back whatever the doc carried so the filter matches the same shape.
  Future<void> _bump(Map<String, dynamic> doc) async {
    final id = doc['_id'];
    if (id == null) {
      _snack('Document has no _id.', error: true);
      return;
    }
    await _wrap(
      () => _orders.updateOne(
        {'_id': id},
        {
          r'$inc': {'total': 1},
        },
      ),
      success: 'total += 1',
    );
  }

  Future<void> _delete(Map<String, dynamic> doc) async {
    final id = doc['_id'];
    if (id == null) {
      _snack('Document has no _id.', error: true);
      return;
    }
    await _wrap(
      () => _orders.deleteOne({'_id': id}),
      success: 'Deleted.',
    );
  }

  Future<void> _count() async {
    await _wrap(() => _orders.count(const {}), reloadAfter: false);
  }

  Future<void> _aggregate() async {
    // Total revenue grouped — a tiny but real pipeline.
    await _wrap(
      () => _orders.aggregate([
        {
          r'$group': {
            '_id': null,
            'revenue': {r'$sum': r'$total'},
            'orders': {r'$sum': 1},
          },
        },
      ]),
      reloadAfter: false,
    );
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MongoDB')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(
            title: 'Add an order',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _item,
                  decoration: const InputDecoration(
                    labelText: 'Item',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _total,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Total',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _insert,
                        icon: const Icon(Icons.add),
                        label: const Text('insertOne'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _find(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('find({})'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _count,
                        icon: const Icon(Icons.tag),
                        label: const Text('count'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _aggregate,
                        icon: const Icon(Icons.calculate_outlined),
                        label: const Text('aggregate'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'orders (${_docs.length})',
            child: _docs.isEmpty
                ? Text(
                    'No documents loaded. Tap "find({})" — a fresh free Mongo '
                    'project denies all access until you set a collection policy '
                    'in the dashboard.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Column(
                    children: [for (final d in _docs) _orderTile(d)],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Last response',
            child: ResultView(
              response: _result,
              placeholder: 'Run an operation to see the raw response.',
            ),
          ),
          const SizedBox(height: 12),
          const InfoCard(
            icon: Icons.policy_outlined,
            title: 'Collection policies (default-deny)',
            body:
                'Mongo access is gated by per-collection policies. A new free '
                'Mongo project denies reads and writes until you add a policy in '
                'the dashboard. Logged in, the policy sees the user; logged out, '
                'it sees the anon key.',
          ),
          const SizedBox(height: 12),
          const InfoCard(
            icon: Icons.data_object,
            title: 'Update operators & _id',
            body:
                'Updates use Mongo operators, e.g. updateOne(filter, '
                '{"\$set": {...}}) or {"\$inc": {...}}. The _id usually comes '
                'back as {"\$oid": "..."}; pass that exact value back as the '
                'filter to target the same document.',
          ),
        ],
      ),
    );
  }

  Widget _orderTile(Map<String, dynamic> doc) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text('${doc['item'] ?? '(no item)'}'),
      subtitle: Text(
        'total: ${doc['total']} · _id: ${_shortId(doc['_id'])}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'total += 1',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _busy ? null : () => _bump(doc),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : () => _delete(doc),
          ),
        ],
      ),
    );
  }

  static String _shortId(dynamic id) {
    final s = id is Map ? (id[r'$oid']?.toString() ?? id.toString()) : '$id';
    return s.length <= 8 ? s : '…${s.substring(s.length - 6)}';
  }
}
