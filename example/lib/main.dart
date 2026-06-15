import 'package:flutter/material.dart';
import 'package:ichibase/ichibase.dart';

import 'app_config.dart';
import 'screens/config_screen.dart';
import 'screens/home_screen.dart';

/// The ichibase brand color — used as the Material 3 seed.
const kBrand = Color(0xFFCB2957);

void main() {
  runApp(const IchibaseExampleApp());
}

class IchibaseExampleApp extends StatelessWidget {
  const IchibaseExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ichibase example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBrand,
          brightness: Brightness.dark,
        ),
        // No animations: keep transitions instant to match the dashboard feel.
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _NoTransitionsBuilder(),
            TargetPlatform.iOS: _NoTransitionsBuilder(),
            TargetPlatform.macOS: _NoTransitionsBuilder(),
            TargetPlatform.windows: _NoTransitionsBuilder(),
            TargetPlatform.linux: _NoTransitionsBuilder(),
          },
        ),
      ),
      home: const _Bootstrap(),
    );
  }
}

/// Decides the first screen: if a project is configured, initialize the global
/// [Ichibase] singleton and show [HomeScreen]; otherwise show [ConfigScreen].
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<AppConfig?> _future;

  @override
  void initState() {
    super.initState();
    _future = _bootstrap();
  }

  /// Load the saved config (if any) and bring up the global SDK client. Session
  /// persistence is automatic inside the SDK, so there is nothing to wire up.
  /// Returns the config (or `null` when the app has not been set up yet).
  Future<AppConfig?> _bootstrap() async {
    // AppConfig.load() also sets AppConfig.current.
    final config = await AppConfig.load();
    if (config != null) {
      // The SDK throws if the key is empty or an ich_admin_ (service) key.
      await Ichibase.initialize(config.url, config.anonKey);
    }
    return config;
  }

  void _reload() {
    // Block body (not `=>`): an arrow would return the assignment's value (a
    // Future), and setState rejects a callback that returns a Future.
    setState(() {
      _future = _bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppConfig?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final error = snap.error;
        if (error != null) {
          // initialize() rejected the config (e.g. a bad/empty key).
          return _ConfigError(error: error, onReset: _reload);
        }

        final config = snap.data;
        if (config == null) {
          // Not set up yet — show the config screen. On success it re-runs the
          // bootstrap to pick up (and initialize with) the saved config.
          return ConfigScreen(onConfigured: _reload);
        }
        // Configured and Ichibase.instance is live — host the app.
        return HomeScreen(onChangeProject: _reload);
      },
    );
  }
}

/// Shown when [Ichibase.initialize] rejects the saved config. Clears it and
/// returns to the setup screen.
class _ConfigError extends StatelessWidget {
  const _ConfigError({required this.error, required this.onReset});

  final Object error;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration error')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: kBrand),
            const SizedBox(height: 16),
            Text(
              'Could not build the client:\n$error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                await AppConfig.clear();
                onReset();
              },
              child: const Text('Re-enter project details'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A page transition builder that performs no animation.
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
