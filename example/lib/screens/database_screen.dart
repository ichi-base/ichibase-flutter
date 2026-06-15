import 'package:flutter/material.dart';
import 'package:ichibase/ichibase.dart';

import '../widgets/result_view.dart';
import '../widgets/section_card.dart';

/// Postgres CRUD demo on a `posts` table (id, title text, published bool).
class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  static const _table = 'posts';

  final _title = TextEditingController();
  final _rpcName = TextEditingController(text: 'your_function');

  List<Map<String, dynamic>> _rows = [];
  IchibaseResponse<dynamic>? _result;
  bool _busy = false;

  Ichibase get _ichi => Ichibase.instance;

  @override
  void dispose() {
    _title.dispose();
    _rpcName.dispose();
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
      if (res.ok && reloadAfter) await _load(setResult: false);
    } catch (e) {
      if (mounted) _snack('Unexpected error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load({bool setResult = true}) async {
    final res = await _ichi
        .from(_table)
        .select('*')
        .order('id', ascending: false)
        .limit(50);
    if (!mounted) return;
    setState(() {
      if (setResult) _result = res;
      if (res.ok && res.data is List) {
        _rows = (res.data as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
    });
    if (!res.ok && setResult) {
      _snack('${res.error?.code}: ${res.error?.detail}', error: true);
    }
  }

  Future<void> _add() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _snack('Enter a title first.', error: true);
      return;
    }
    await _wrap(
      () => _ichi.from(_table).insert({'title': title, 'published': false}),
      success: 'Inserted.',
    );
    if (mounted) _title.clear();
  }

  Future<void> _togglePublished(Map<String, dynamic> row) async {
    final id = row['id'];
    final next = !(row['published'] == true);
    await _wrap(
      () => _ichi
          .from(_table)
          .update({'published': next})
          .eq('id', id as Object),
      success: 'Updated.',
    );
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = row['id'];
    await _wrap(
      () => _ichi.from(_table).delete().eq('id', id as Object),
      success: 'Deleted.',
    );
  }

  Future<void> _rpc() async {
    final fn = _rpcName.text.trim();
    if (fn.isEmpty) return;
    await _wrap(
      () => _ichi.rpc(fn, args: const {'limit': 5}),
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
      appBar: AppBar(title: const Text('Database (Postgres)')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(
            title: 'Add a post',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _add(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _add,
                        icon: const Icon(Icons.add),
                        label: const Text('Insert'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _load(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Load'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'posts (${_rows.length})',
            child: _rows.isEmpty
                ? Text(
                    'No rows loaded. Tap "Load" — if you are logged out, RLS may '
                    'deny anon access until your table allows it.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Column(
                    children: [
                      for (final row in _rows) _postTile(row),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'RPC (Postgres function)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _rpcName,
                  decoration: const InputDecoration(
                    labelText: 'Function name',
                    helperText: 'Replace with one of your own functions.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _rpc,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("rpc(fn, args: {'limit': 5})"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Last response',
            child: ResultView(
              response: _result,
              placeholder: 'Run a query to see the raw response.',
            ),
          ),
          const SizedBox(height: 12),
          const InfoCard(
            icon: Icons.shield_outlined,
            title: 'Row-level security',
            body:
                'Logged out, queries use the anon key — RLS is default-deny '
                'unless your table policy allows anon. After login, queries run '
                'as the user, so policies see auth.uid().',
          ),
          const SizedBox(height: 12),
          const InfoCard(
            icon: Icons.code,
            title: 'Create the table',
            body:
                'In the SQL editor:\n\n'
                'create table posts (\n'
                '  id bigint generated always as identity primary key,\n'
                '  title text not null,\n'
                '  published boolean not null default false\n'
                ');\n\n'
                'Then add an RLS policy (or enable anon access) so this screen '
                'can read/write.',
          ),
        ],
      ),
    );
  }

  Widget _postTile(Map<String, dynamic> row) {
    final published = row['published'] == true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: IconButton(
        tooltip: published ? 'Unpublish' : 'Publish',
        icon: Icon(
          published ? Icons.check_circle : Icons.circle_outlined,
          color: published ? Colors.green : null,
        ),
        onPressed: _busy ? null : () => _togglePublished(row),
      ),
      title: Text('${row['title']}'),
      subtitle: Text('id: ${row['id']} · published: $published'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: _busy ? null : () => _delete(row),
      ),
    );
  }
}
