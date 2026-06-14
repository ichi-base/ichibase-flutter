import 'package:ichibase/ichibase.dart';

Future<void> main() async {
  final ichi = Ichibase.createClient(
    'https://your-project.ichibase.net',
    'ich_pub_your_anon_key', // publishable (anon) key — safe to ship
  );

  // ── Database (PostgREST) ──────────────────────────────────────────
  final posts = await ichi.from('posts').select('*').eq('published', true).limit(20);
  if (posts.ok) {
    print('posts: ${posts.data}');
  } else {
    print('error: ${posts.error}');
  }

  await ichi.from('posts').insert({'title': 'Hello from Dart'});

  // ── Auth ───────────────────────────────────────────────────────────
  final login = await ichi.auth.login(email: 'a@b.com', password: 'secret');
  if (login.ok) {
    // Now runs as the user — RLS sees auth.uid().
    await ichi.from('posts').insert({'title': 'mine'});
    final me = await ichi.auth.getUser();
    print('signed in as: $me');
  }

  // ── Mongo ──────────────────────────────────────────────────────────
  await ichi.mongo.collection('orders').insertOne({'total': 42});
  final orders = await ichi.mongo.collection('orders').find({'total': {'\$gt': 10}});
  print('orders: ${orders.data}');

  // ── Realtime ───────────────────────────────────────────────────────
  final sub = ichi.realtime.subscribe(
    kind: 'postgres',
    table: 'messages',
    events: ['INSERT'],
    onMessage: (msg) => print('new message: ${msg['record']}'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  sub.unsubscribe();

  ichi.dispose();
}
