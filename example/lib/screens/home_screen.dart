import 'package:flutter/material.dart';
import 'package:ichibase/ichibase.dart';

import '../app_config.dart';
import 'auth_screen.dart';
import 'database_screen.dart';
import 'functions_screen.dart';
import 'mongo_screen.dart';
import 'pro_features_screen.dart';
import 'realtime_screen.dart';
import 'storage_screen.dart';

/// The hub. Shows the project slug, a live auth chip, and tiles into each
/// feature area (filtered by the configured database flavor).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onChangeProject});

  /// Called when the user clears the config to switch projects.
  final VoidCallback onChangeProject;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _confirmChangeProject() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change project?'),
        content: const Text(
          'This clears the saved slug, key, and any persisted session, then '
          'returns to the setup screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AppConfig.clear();
    if (!mounted) return;
    widget.onChangeProject();
  }

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.current!;
    final flavor = config.flavor;

    final tiles = <_Feature>[
      _Feature(
        icon: Icons.lock_outline,
        title: 'Auth',
        subtitle: 'Sign up, log in, sessions, reset, OAuth notes',
        builder: (_) => const AuthScreen(),
      ),
      if (flavor != DbFlavor.mongo)
        _Feature(
          icon: Icons.table_rows_outlined,
          title: 'Database (Postgres)',
          subtitle: 'CRUD on a posts table, RLS, RPC',
          builder: (_) => const DatabaseScreen(),
        ),
      if (flavor != DbFlavor.postgres)
        _Feature(
          icon: Icons.data_object,
          title: 'MongoDB',
          subtitle: 'CRUD on an orders collection, policies',
          builder: (_) => const MongoScreen(),
        ),
      _Feature(
        icon: Icons.bolt_outlined,
        title: 'Realtime',
        subtitle: 'Subscribe to live INSERT/UPDATE/DELETE',
        builder: (_) => const RealtimeScreen(),
      ),
      _Feature(
        icon: Icons.cloud_outlined,
        title: 'Storage',
        subtitle: 'Public reads, signed URLs, uploads via Edge Function',
        builder: (_) => const StorageScreen(),
      ),
      _Feature(
        icon: Icons.functions,
        title: 'Edge Functions',
        subtitle: 'Invoke a deployed function with a JSON body',
        builder: (_) => const FunctionsScreen(),
      ),
      _Feature(
        icon: Icons.workspace_premium_outlined,
        title: 'Pro features',
        subtitle: 'Search, Redis, schedules, dual DB, dedicated VPS',
        builder: (_) => const ProFeaturesScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ichibase example',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text(
              '${config.slug}.ichibase.net · ${flavor.label}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Center(child: AuthChip()),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'change') _confirmChangeProject();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'change',
                child: ListTile(
                  leading: Icon(Icons.swap_horiz),
                  title: Text('Change project'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final f = tiles[i];
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                child: Icon(f.icon,
                    color: Theme.of(context).colorScheme.primary),
              ),
              title: Text(f.title),
              subtitle: Text(f.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: f.builder),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Feature {
  const _Feature({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
}

/// A live chip in the AppBar reflecting auth state via `onAuthStateChange`.
class AuthChip extends StatefulWidget {
  const AuthChip({super.key});

  @override
  State<AuthChip> createState() => _AuthChipState();
}

class _AuthChipState extends State<AuthChip> {
  // Seed from the current session; the StreamBuilder tracks changes after.
  final Session? _session = Ichibase.instance.session;

  @override
  Widget build(BuildContext context) {
    final ichi = Ichibase.instance;
    return StreamBuilder<({AuthEvent event, Session? session})>(
      stream: ichi.onAuthStateChange,
      builder: (context, snap) {
        final session = snap.hasData ? snap.data!.session : _session;
        final signedIn = session != null;
        final email = session?.user?['email'] as String?;
        final color =
            signedIn ? Colors.green : Theme.of(context).colorScheme.outline;
        return Chip(
          visualDensity: VisualDensity.compact,
          avatar: Icon(
            signedIn ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
            color: color,
          ),
          label: Text(
            signedIn ? (email ?? 'signed in') : 'signed out',
            style: const TextStyle(fontSize: 12),
          ),
        );
      },
    );
  }
}
