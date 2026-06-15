import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ichibase/ichibase.dart';

import '../app_config.dart';
import '../widgets/result_view.dart';
import '../widgets/section_card.dart';

/// Storage demo. The client has NO storage module: public files come straight
/// from the CDN, while private reads, signed uploads, and deletes go through
/// YOUR Edge Function (`files`), which holds the service key server-side.
///
/// See example/edge_functions/files.ts for the function this screen calls.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  // (a) Public read
  final _publicPath = TextEditingController(text: 'avatars/logo.png');
  String? _publicUrl;

  // (b) Private read
  final _privBucket = TextEditingController(text: 'private');
  final _privPath = TextEditingController(text: 'reports/q2.pdf');
  String? _privateUrl;

  // (c) Upload
  final _upBucket = TextEditingController(text: 'private');
  final _upPath = TextEditingController(text: 'notes/hello.txt');

  IchibaseResponse<dynamic>? _result;
  bool _busy = false;

  Ichibase get _ichi => Ichibase.instance;
  String get _slug => AppConfig.current!.slug;

  @override
  void dispose() {
    _publicPath.dispose();
    _privBucket.dispose();
    _privPath.dispose();
    _upBucket.dispose();
    _upPath.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  // (a) Public read — straight from the CDN, no auth.
  void _buildPublicUrl() {
    final path = _publicPath.text.trim();
    setState(() {
      _publicUrl = 'https://cdn.ichibase.net/$_slug/public/$path';
    });
  }

  // (b) Private read — ask the Edge Function for a token-bearing URL.
  Future<void> _signRead() async {
    setState(() => _busy = true);
    try {
      final res = await _ichi.functions.invoke('files', body: {
        'op': 'get',
        'bucket': _privBucket.text.trim(),
        'path': _privPath.text.trim(),
      });
      if (!mounted) return;
      setState(() => _result = res);
      if (!res.ok) {
        _snack('${res.error?.code}: ${res.error?.detail}', error: true);
        return;
      }
      final url = _readUrl(res.data);
      setState(() => _privateUrl = url);
      if (url == null) {
        _snack('Function returned no { url }.', error: true);
      }
    } catch (e) {
      if (mounted) _snack('Unexpected error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // (c) Upload — get a signed PUT url, then http.put the bytes ourselves.
  Future<void> _upload() async {
    setState(() => _busy = true);
    try {
      final res = await _ichi.functions.invoke('files', body: {
        'op': 'put',
        'bucket': _upBucket.text.trim(),
        'path': _upPath.text.trim(),
        'content_type': 'text/plain',
      });
      if (!mounted) return;
      setState(() => _result = res);
      if (!res.ok) {
        _snack('${res.error?.code}: ${res.error?.detail}', error: true);
        return;
      }
      final putUrl = _readUrl(res.data);
      if (putUrl == null) {
        _snack('Function returned no signed PUT url.', error: true);
        return;
      }
      // No file picker — generate bytes in-app so the example stays plugin-free.
      final bytes = utf8.encode('hello from ichibase @ ${DateTime.now()}');
      final put = await http.put(
        Uri.parse(putUrl),
        headers: const {'Content-Type': 'text/plain'},
        body: bytes,
      );
      if (!mounted) return;
      if (put.statusCode >= 200 && put.statusCode < 300) {
        _snack('Uploaded ${bytes.length} bytes (HTTP ${put.statusCode}).');
      } else {
        _snack('Upload failed: HTTP ${put.statusCode}', error: true);
      }
    } catch (e) {
      if (mounted) _snack('Unexpected error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _readUrl(dynamic data) {
    if (data is Map) {
      final u = data['url'];
      if (u is String) return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const InfoCard(
            icon: Icons.shield_outlined,
            title: 'No storage in the client — by design',
            body:
                'The anon client never sees the service key. Public files load '
                'from cdn.ichibase.net; private reads, uploads, and deletes go '
                'through your Edge Function (files), which signs URLs with the '
                'service key server-side. See example/edge_functions/files.ts.',
          ),
          const SizedBox(height: 12),

          // (a) PUBLIC ──────────────────────────────────────────────
          SectionCard(
            title: '(a) Public read (CDN)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _publicPath,
                  decoration: const InputDecoration(
                    labelText: 'Path within the public bucket',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _buildPublicUrl,
                  icon: const Icon(Icons.link),
                  label: const Text('Build CDN URL'),
                ),
                if (_publicUrl != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    _publicUrl!,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  _imagePreview(_publicUrl!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // (b) PRIVATE ─────────────────────────────────────────────
          SectionCard(
            title: '(b) Private read (signed URL)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _privBucket,
                  decoration: const InputDecoration(
                    labelText: 'Bucket',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _privPath,
                  decoration: const InputDecoration(
                    labelText: 'Path',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _signRead,
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text("invoke('files', op: 'get')"),
                ),
                if (_privateUrl != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'The URL carries a ?token=<jwt> query param that grants '
                    'temporary read access:',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    _privateUrl!,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  _imagePreview(_privateUrl!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // (c) UPLOAD ──────────────────────────────────────────────
          SectionCard(
            title: '(c) Upload (signed PUT)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _upBucket,
                  decoration: const InputDecoration(
                    labelText: 'Bucket',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _upPath,
                  decoration: const InputDecoration(
                    labelText: 'Path',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.upload_file),
                  label: const Text("invoke('files', op: 'put') + http.put"),
                ),
                const SizedBox(height: 8),
                Text(
                  'Generates a small text payload in-app (no file picker '
                  'plugin), then PUTs it to the signed URL.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          SectionCard(
            title: 'Last function response',
            child: ResultView(
              response: _result,
              placeholder: 'Sign a read or run an upload to see the response.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePreview(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        height: 160,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => Container(
          height: 120,
          alignment: Alignment.center,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(
            'Not an image, or not reachable yet.\n($error)',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    );
  }
}
