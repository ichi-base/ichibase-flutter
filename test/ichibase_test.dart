import 'package:ichibase/ichibase.dart';
import 'package:test/test.dart';

void main() {
  test('rejects service (ich_admin_) keys — anon only', () {
    expect(
      () => Ichibase.createClient('https://x.ichibase.net', 'ich_admin_abc'),
      throwsArgumentError,
    );
  });

  test('requires a non-empty key', () {
    expect(
      () => Ichibase.createClient('https://x.ichibase.net', ''),
      throwsArgumentError,
    );
  });

  test('normalizes the url (strips a trailing slash)', () {
    final c = Ichibase.createClient('https://x.ichibase.net/', 'ich_pub_abc');
    expect(c.url, 'https://x.ichibase.net');
    c.dispose();
  });

  test('from() builds a chainable query builder', () {
    final c = Ichibase.createClient('https://x.ichibase.net', 'ich_pub_abc');
    final qb = c.from('posts').select('*').eq('id', 1).limit(10);
    expect(qb, isA<PostgrestQueryBuilder>());
    c.dispose();
  });

  test('top-level createClient() works and starts signed out', () {
    final c = createClient('https://x.ichibase.net', 'ich_pub_abc');
    expect(c, isA<Ichibase>());
    expect(c.session, isNull);
    c.dispose();
  });

  test('mongo + realtime accessors are wired', () {
    final c = createClient('https://x.ichibase.net', 'ich_pub_abc');
    expect(c.mongo, isA<Mongo>());
    expect(c.realtime, isA<RealtimeClient>());
    expect(c.functions, isA<Functions>());
    c.dispose();
  });
}
