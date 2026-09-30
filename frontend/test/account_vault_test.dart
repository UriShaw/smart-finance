import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_finance/logic/auth/account_vault.dart';

SavedAccount acc(String id, String token, int minute, {String? name}) => SavedAccount(
      userId: id,
      refreshToken: token,
      email: '$id@gmail.com',
      name: name,
      lastUsed: DateTime(2026, 9, 29, 10, minute),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('lưu nhiều tài khoản, mới dùng gần nhất lên đầu', () async {
    final v = AccountVault();
    await v.save(acc('a', 't1', 0));
    await v.save(acc('b', 't2', 5));
    expect((await v.list()).map((a) => a.userId), ['b', 'a']);
  });

  test('cập nhật token của tài khoản đã có (không nhân đôi)', () async {
    final v = AccountVault();
    await v.save(acc('a', 't1', 0));
    await v.save(acc('a', 't1-new', 9));
    final all = await v.list();
    expect(all.length, 1);
    expect(all.single.refreshToken, 't1-new');
    expect((await v.find('a'))?.refreshToken, 't1-new');
  });

  test('bỏ tài khoản', () async {
    final v = AccountVault();
    await v.save(acc('a', 't1', 0));
    await v.save(acc('b', 't2', 1));
    await v.remove('a');
    expect((await v.list()).map((a) => a.userId), ['b']);
    expect(await v.find('a'), isNull);
  });

  test('nhãn: tên nếu có, không thì email', () {
    expect(acc('a', 't', 0, name: 'Uri').label, 'Uri');
    expect(acc('a', 't', 0).label, 'a@gmail.com');
  });

  test('dữ liệu hỏng -> danh sách rỗng, không crash', () async {
    SharedPreferences.setMockInitialValues({'sf_saved_accounts_v1': '{not json'});
    expect(await AccountVault().list(), isEmpty);
  });
}
