import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ichibase/ichibase.dart';

import '../widgets/result_view.dart';
import '../widgets/section_card.dart';

/// Generic Edge Function invoker: enter a name and a JSON body, hit invoke,
/// and inspect the response.
class FunctionsScreen extends StatefulWidget {
  const FunctionsScreen({super.key});

  @override
  State<FunctionsScreen> createState() => _FunctionsScreenState();
}

class _FunctionsScreenState extends State<FunctionsScreen> {
  final _name = TextEditingController(text: 'hello');
  final _body = TextEditingController(text: '{\n  "name": "world"\n}');

  IchibaseResponse<dynamic>? _result;
  bool _busy = false;
  String? _jsonError;

  Ichibase get _ichi => Ichibase.instance;

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _invoke() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Enter a function name.', error: true);
      return;
    }

    Object? body;
    final raw = _body.text.trim();
    if (raw.isNotEmpty) {
      try {
        body = jsonDecode(raw);
        setState(() => _jsonError = null);
      } catch (e) {
        setState(() => _jsonError = 'Invalid JSON: $e');
        return;
      }
    }

    setState(() => _busy = true);
    try {
      final res = await _ichi.functions.invoke(name, body: body);
      if (!mounted) return;
      setState(() => _result = res);
      if (!res.ok) {
        _snack('${res.error?.code}: ${res.error?.detail}', error: true);
      }
    } catch (e) {
      if (mounted) _snack('Unexpected error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      appBar: AppBar(title: const Text('Edge Functions')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(
            title: 'Invoke a function',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Function name',
                    helperText: 'POSTed to /functions/<name>',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  minLines: 4,
                  maxLines: 10,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'JSON body',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    errorText: _jsonError,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _invoke,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('invoke()'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Response',
            child: ResultView(
              response: _result,
              placeholder: 'Invoke a function to see res.data here.',
            ),
          ),
          const SizedBox(height: 12),
          const InfoCard(
            icon: Icons.key_outlined,
            title: 'Auth is automatic',
            body:
                'invoke() sends your project apikey, and when a user is signed '
                'in it also attaches their access token as a Bearer header — so '
                'the function can identify the caller and enforce policy.',
          ),
        ],
      ),
    );
  }
}
