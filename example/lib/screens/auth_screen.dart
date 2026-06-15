import 'package:flutter/material.dart';
import 'package:ichibase/ichibase.dart';

import '../widgets/result_view.dart';
import '../widgets/section_card.dart';

/// The centrepiece: a hands-on tour of the whole auth surface — signup, login,
/// the logged-in panel, password reset, a live auth-state feed, and notes on
/// OAuth and per-user data access.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  Ichibase get _ichi => Ichibase.instance;

  // Shared credential fields across signup/login.
  final _email = TextEditingController();
  final _password = TextEditingController();

  // Email verification (OTP / token) + password reset.
  final _otpCode = TextEditingController();
  final _verifyToken = TextEditingController();
  final _resetEmail = TextEditingController();

  IchibaseResponse<dynamic>? _result;
  Map<String, dynamic>? _user;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _otpCode.dispose();
    _verifyToken.dispose();
    _resetEmail.dispose();
    super.dispose();
  }

  /// Run [action], capture its [IchibaseResponse], and surface errors.
  Future<void> _run(
    Future<IchibaseResponse<dynamic>> Function() action, {
    String? successMessage,
  }) async {
    setState(() => _busy = true);
    try {
      final res = await action();
      if (!mounted) return;
      setState(() => _result = res);
      if (res.ok && successMessage != null) {
        _snack(successMessage);
      } else if (!res.ok) {
        _snack('${res.error?.code}: ${res.error?.detail}', error: true);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Unexpected error: $e', error: true);
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

  Future<void> _login() async {
    await _run(
      () => _ichi.auth.login(
        email: _email.text.trim(),
        password: _password.text,
      ),
      successMessage: 'Logged in.',
    );
  }

  Future<void> _signup() async {
    await _run(
      () => _ichi.auth.signup(
        email: _email.text.trim(),
        password: _password.text,
      ),
      successMessage: 'Signed up. Check your inbox to verify.',
    );
  }

  Future<void> _refresh() async {
    await _run(_ichi.auth.refresh, successMessage: 'Token refreshed.');
  }

  Future<void> _getUser() async {
    setState(() => _busy = true);
    try {
      final user = await _ichi.auth.getUser();
      if (!mounted) return;
      setState(() {
        _user = user;
        _result = IchibaseResponse<dynamic>(data: user);
      });
    } catch (e) {
      if (!mounted) return;
      _snack('getUser failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    try {
      await _ichi.auth.logout();
      if (!mounted) return;
      setState(() {
        _user = null;
        _result = null;
      });
      _snack('Logged out.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Auth'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Sign up'),
              Tab(text: 'Log in'),
              Tab(text: 'Session'),
              Tab(text: 'Reset / Info'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSignup(),
            _buildLogin(),
            _buildSession(),
            _buildResetAndInfo(),
          ],
        ),
      ),
    );
  }

  // ── (1) Sign up ─────────────────────────────────────────────────────────
  Widget _buildSignup() {
    return _tab([
      SectionCard(
        title: 'Create an account',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _emailField(),
            const SizedBox(height: 12),
            _passwordField(),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _signup,
              child: const Text('Sign up'),
            ),
          ],
        ),
      ),
      SectionCard(
        title: 'Email verification',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'After signup ichibase emails a verification link and/or a code. '
              'Confirm with either flow below, or resend.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _otpCode,
              decoration: const InputDecoration(
                labelText: 'OTP code (from the email)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                        () => _ichi.auth.verifyEmailOtp(
                            _email.text.trim(), _otpCode.text.trim()),
                        successMessage: 'Email verified (OTP).',
                      ),
              child: const Text('Verify with OTP'),
            ),
            const Divider(height: 28),
            TextField(
              controller: _verifyToken,
              decoration: const InputDecoration(
                labelText: 'Verification token (from the link)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                        () => _ichi.auth.verifyEmail(_verifyToken.text.trim()),
                        successMessage: 'Email verified (token).',
                      ),
              child: const Text('Verify with token'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                        () => _ichi.auth
                            .resendVerification(_email.text.trim()),
                        successMessage: 'Verification email resent.',
                      ),
              child: const Text('Resend verification email'),
            ),
          ],
        ),
      ),
      _resultCard(),
    ]);
  }

  // ── (2) Log in ───────────────────────────────────────────────────────────
  Widget _buildLogin() {
    return _tab([
      SectionCard(
        title: 'Log in',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _emailField(),
            const SizedBox(height: 12),
            _passwordField(),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _login,
              child: const Text('Log in'),
            ),
            const SizedBox(height: 8),
            Text(
              'On success the session is persisted automatically by the SDK '
              'and every later data call runs AS this user.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const InfoCard(
        icon: Icons.shield_outlined,
        title: 'Data runs as the user',
        body:
            'Logged out, calls use the anon key. After login, the SDK swaps in '
            "the user's access token, so Postgres RLS and Mongo collection "
            'policies see auth.uid() — every read/write is scoped to them.',
      ),
      _resultCard(),
    ]);
  }

  // ── (3) Session panel ─────────────────────────────────────────────────────
  Widget _buildSession() {
    final session = _ichi.session;
    final signedIn = session != null;
    return _tab([
      SectionCard(
        title: 'Current session',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _kv('Signed in', signedIn ? 'yes' : 'no'),
            if (signedIn) ...[
              _kv('User email',
                  (session.user?['email'] as String?) ?? '—'),
              _kv('Access token', _truncate(session.accessToken)),
              _kv('Refresh token', _truncate(session.refreshToken)),
              _kv('Expires at', _expiry(session.expiresAt)),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: !signedIn || _busy ? null : _getUser,
                  icon: const Icon(Icons.person_outline),
                  label: const Text('getUser()'),
                ),
                OutlinedButton.icon(
                  onPressed: !signedIn || _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('refresh()'),
                ),
                OutlinedButton.icon(
                  onPressed: !signedIn || _busy ? null : _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('logout()'),
                ),
              ],
            ),
          ],
        ),
      ),
      if (_user != null)
        SectionCard(
          title: 'getUser() result',
          child: ResultView(response: IchibaseResponse<dynamic>(data: _user)),
        ),
      const _LiveAuthStatePanel(),
      _resultCard(),
    ]);
  }

  // ── (4) Reset + OAuth/info ────────────────────────────────────────────────
  Widget _buildResetAndInfo() {
    return _tab([
      SectionCard(
        title: 'Request a password reset',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _resetEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                        () => _ichi.auth
                            .requestPasswordReset(_resetEmail.text.trim()),
                        successMessage:
                            'If the email exists, a reset link was sent.',
                      ),
              child: const Text('Send reset email'),
            ),
            const SizedBox(height: 8),
            Text(
              'The email contains a token. Your app collects a new password and '
              'calls auth.confirmPasswordReset(token, newPassword).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const InfoCard(
        icon: Icons.alternate_email,
        title: 'OAuth (Google / Apple)',
        body:
            'Per-project social login is enabled in the dashboard. The client '
            'opens <project>.ichibase.net/auth/oauth/<provider>/authorize'
            '?redirect=<your-deep-link> in a browser; the provider redirects '
            'back to your app\'s deep link with the session. Deep-linking is '
            'app-specific (e.g. uni_links / app_links), so it is described here '
            'but not wired up in this example.',
      ),
      const InfoCard(
        icon: Icons.lock_clock_outlined,
        title: 'Sessions persist across restarts',
        body:
            'Persistence is automatic: after Ichibase.initialize() in main(), '
            'the SDK saves the session (a file on mobile/desktop, localStorage '
            'on web) and rehydrates it on the next launch — no SessionStore '
            'wiring. To harden the refresh token, pass a flutter_secure_storage '
            'adapter as the optional store: argument.',
      ),
      _resultCard(),
    ]);
  }

  // ── shared bits ───────────────────────────────────────────────────────────
  Widget _tab(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final c in children) ...[c, const SizedBox(height: 12)],
      ],
    );
  }

  Widget _emailField() => TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Email',
          border: OutlineInputBorder(),
        ),
      );

  Widget _passwordField() => TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Password',
          border: OutlineInputBorder(),
        ),
      );

  Widget _resultCard() => SectionCard(
        title: 'Last response',
        child: ResultView(
          response: _result,
          placeholder: 'Run an auth action to see the raw response here.',
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(k,
                  style:
                      Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
        ),
      );

  static String _truncate(String s) =>
      s.length <= 24 ? s : '${s.substring(0, 12)}…${s.substring(s.length - 8)}';

  static String _expiry(int? epochSec) {
    if (epochSec == null) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    final left = dt.difference(DateTime.now());
    final mins = left.inMinutes;
    final rel = mins >= 0 ? 'in ${mins}m' : '${-mins}m ago';
    return '${dt.toLocal()} ($rel)';
  }
}

/// (5) A live panel driven by `ichi.onAuthStateChange`, showing the last event.
class _LiveAuthStatePanel extends StatefulWidget {
  const _LiveAuthStatePanel();

  @override
  State<_LiveAuthStatePanel> createState() => _LiveAuthStatePanelState();
}

class _LiveAuthStatePanelState extends State<_LiveAuthStatePanel> {
  final List<String> _log = [];

  @override
  Widget build(BuildContext context) {
    final ichi = Ichibase.instance;
    return SectionCard(
      title: 'Live auth state (onAuthStateChange)',
      child: StreamBuilder<({AuthEvent event, Session? session})>(
        stream: ichi.onAuthStateChange,
        builder: (context, snap) {
          if (snap.hasData) {
            final ev = snap.data!;
            final email = ev.session?.user?['email'] as String?;
            final entry =
                '${TimeOfDay.now().format(context)}  ${ev.event.name}'
                '${email != null ? '  ($email)' : ''}';
            // Append once per new event.
            if (_log.isEmpty || _log.last != entry) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _log.add(entry));
              });
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Events appear here as you sign in, refresh, or log out.',
              ),
              const SizedBox(height: 8),
              if (_log.isEmpty)
                Text('No events yet.',
                    style: Theme.of(context).textTheme.bodySmall)
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in _log.reversed.take(8))
                        Text(l,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
