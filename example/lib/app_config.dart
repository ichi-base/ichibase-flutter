import 'package:shared_preferences/shared_preferences.dart';

/// Which database(s) the configured ichibase project exposes.
///
/// Free projects ship with exactly one database. Running both Postgres and
/// MongoDB on a single project requires a Pro plan (dedicated VPS).
enum DbFlavor { postgres, mongo, both }

extension DbFlavorLabel on DbFlavor {
  String get label => switch (this) {
        DbFlavor.postgres => 'Postgres only',
        DbFlavor.mongo => 'Mongo only',
        DbFlavor.both => 'Both (Pro)',
      };

  /// The value persisted to [SharedPreferences].
  String get storageValue => name;

  static DbFlavor fromStorage(String? value) => switch (value) {
        'mongo' => DbFlavor.mongo,
        'both' => DbFlavor.both,
        _ => DbFlavor.postgres,
      };
}

/// The user-supplied configuration for the example app: which ichibase project
/// to talk to and which database surface(s) to show.
class AppConfig {
  AppConfig({
    required this.slug,
    required this.anonKey,
    required this.flavor,
  });

  /// The project slug, e.g. `myapp` for `https://myapp.ichibase.net`.
  final String slug;

  /// The publishable anon key (`ich_pub_…`). Safe to ship in a client app.
  final String anonKey;

  /// Which database surface(s) to expose in the UI.
  final DbFlavor flavor;

  /// The active configuration, made available without a [BuildContext] so
  /// screens can read the chosen [flavor]/[slug] (the SDK client itself is
  /// reached via `Ichibase.instance`). Set by [load] and [save], cleared by
  /// [clear].
  static AppConfig? current;

  /// The base URL the SDK is pointed at.
  String get url => 'https://$slug.ichibase.net';

  // ── SharedPreferences keys ─────────────────────────────────────────────
  static const _kSlug = 'ichibase.cfg.slug';
  static const _kAnonKey = 'ichibase.cfg.anonKey';
  static const _kFlavor = 'ichibase.cfg.flavor';

  /// Load the saved configuration, or `null` if the app has not been set up.
  static Future<AppConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final slug = prefs.getString(_kSlug);
    final anonKey = prefs.getString(_kAnonKey);
    if (slug == null || slug.isEmpty || anonKey == null || anonKey.isEmpty) {
      return null;
    }
    final config = AppConfig(
      slug: slug,
      anonKey: anonKey,
      flavor: DbFlavorLabel.fromStorage(prefs.getString(_kFlavor)),
    );
    current = config;
    return config;
  }

  /// Persist this configuration and make it the [current] one.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSlug, slug);
    await prefs.setString(_kAnonKey, anonKey);
    await prefs.setString(_kFlavor, flavor.storageValue);
    current = this;
  }

  /// Forget the saved configuration (used by "Change project").
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSlug);
    await prefs.remove(_kAnonKey);
    await prefs.remove(_kFlavor);
    current = null;
  }
}
