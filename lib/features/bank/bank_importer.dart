import '../../core/utils/ids.dart';
import '../../data/repositories/bank_message_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/entities/common.dart';
import '../../domain/entities/finance_transaction.dart';
import '../../domain/usecases/category_guesser.dart';
import 'bank_channel.dart';

/// Nhãn đã dịch dùng khi tạo giao dịch tự động.
class BankLabels {
  const BankLabels({
    required this.incomeName,
    required this.expenseName,
    required this.autoNote,
  });

  final String incomeName;
  final String expenseName;

  /// Có chứa "{bank}".
  final String autoNote;
}

/// Chuyển sự kiện thông báo ngân hàng -> giao dịch và lưu (không trùng).
class BankImporter {
  BankImporter({
    required this.channel,
    required this.transactions,
    required this.userId,
    required this.categoryIdForKey,
    required this.labels,
    this.messages,
    this.locate,
    this.placeName,
  });

  final BankChannel channel;

  /// Lưu thông báo gốc (số dư ngân hàng + xem lại tin gốc). null = không lưu.
  final BankMessageRepository? messages;
  final TransactionRepository transactions;
  final String userId;

  /// Khóa danh mục mặc định -> id danh mục (null nếu user đã xóa danh mục đó).
  final Future<String?> Function(String key) categoryIdForKey;
  final BankLabels labels;

  /// Vị trí hiện tại khi app đang mở (thông báo chưa kèm vị trí). null = không gắn vị trí.
  final Future<({double lat, double lng})?> Function()? locate;

  /// Toạ độ -> tên địa điểm (đường, phường, quận). null / lỗi = để trống.
  final Future<String?> Function(double lat, double lng)? placeName;

  /// Chỉ lấy GPS ngay cho thông báo vừa tới (người dùng còn ở gần chỗ giao dịch).
  static const _freshForLocation = Duration(minutes: 2);

  bool _running = false;

  /// Lấy hàng chờ từ Android, lưu vào DB, xác nhận để Android xóa. Trả về số giao dịch mới.
  Future<int> importPending() async {
    if (_running) return 0;
    _running = true;
    try {
      final events = await channel.getPending();
      if (events.isEmpty) return 0;
      var created = 0;
      final done = <String>[];
      for (final e in events) {
        try {
          // Thông báo này đã nhập rồi (ack lần trước bị lỗi) -> chỉ xác nhận.
          if (await messages?.exists(e.id) ?? false) {
            done.add(e.id);
            continue;
          }
          final (id, duplicate) = await resolveId(e);
          await messages?.save(toMessage(e, txId: id));
          if (!duplicate) {
            final key = guessCategoryKey(e);
            final catId = key == null ? null : await categoryIdForKey(key);
            final (lat, lng, place) = await _where(e);
            final tx = toTransaction(
              e,
              userId: userId,
              categoryId: catId,
              labels: labels,
              id: id,
              latitude: lat,
              longitude: lng,
              locationName: place,
            );
            if (await transactions.importIfAbsent(tx)) created++;
          }
          done.add(e.id);
        } catch (_) {
          // Giữ lại trong hàng chờ, thử lần sau.
        }
      }
      await channel.ackPending(done);
      return created;
    } finally {
      _running = false;
    }
  }

  /// Mã cũ (theo thông báo trên từng máy) — chỉ dùng khi không xếp được chỗ.
  static String transactionId(BankEvent e) => Ids.deterministic('smart-finance/bank/${e.id}');

  /// Dấu vân tay của 1 giao dịch ngân hàng, giống nhau trên mọi điện thoại cùng nhận
  /// thông báo. Có số dư: chiều + số tiền + số dư sau GD (không phụ thuộc tên ngân hàng,
  /// vì SMS và app của cùng ngân hàng có thể ghi khác nhau). Không có số dư: thêm tên ngân hàng.
  static String fingerprint(BankEvent e) => e.balance >= 0
      ? 'b|${e.direction}|${e.amount}|${e.balance}'
      : 'n|${e.bank.trim().toLowerCase()}|${e.direction}|${e.amount}';

  /// Hai máy nhận cùng 1 thông báo lệch nhau tối đa chừng này thì coi là trùng.
  static Duration duplicateWindow(BankEvent e) =>
      e.balance >= 0 ? const Duration(hours: 6) : const Duration(minutes: 30);

  /// Có [userId]: 2 tài khoản trên cùng máy không bao giờ trùng mã (mã là khoá chính toàn server).
  static String slotId(String userId, String fingerprint, int slot) =>
      Ids.deterministic('smart-finance/bank/v2/$userId/$fingerprint/$slot');

  /// Chọn mã giao dịch cho [e] để nhiều điện thoại ra CÙNG một mã -> không trùng khi đồng bộ.
  ///
  /// Duyệt các "chỗ" 0, 1, 2... của dấu vân tay:
  /// - chỗ trống -> dùng chỗ đó (giao dịch mới);
  /// - chỗ đã có giao dịch do CHÍNH máy này nhập (có thông báo gốc trên máy) -> đó là một
  ///   giao dịch thật khác cùng số tiền/số dư -> xét chỗ tiếp theo;
  /// - chỗ đã có giao dịch từ máy khác đồng bộ về, thời gian gần nhau -> máy này nhận
  ///   chậm hơn: trả về duplicate = true (không tạo giao dịch mới, chỉ gắn thông báo gốc).
  /// Hai máy chưa kịp đồng bộ mà cùng nhập thì cũng ra cùng mã, server tự gộp làm một.
  Future<(String id, bool duplicate)> resolveId(BankEvent e) async {
    final fp = fingerprint(e);
    final window = duplicateWindow(e);
    for (var slot = 0; slot < 100; slot++) {
      final id = slotId(userId, fp, slot);
      final existing = await transactions.getById(id);
      if (existing == null) return (id, false);
      final own = await messages?.byTransaction(id) != null;
      if (!own && existing.date.difference(e.postedAt).abs() <= window) return (id, true);
    }
    return (transactionId(e), false);
  }

  static BankMessage toMessage(BankEvent e, {String? txId}) => BankMessage(
        id: e.id,
        txId: txId ?? transactionId(e),
        pkg: e.pkg,
        bank: e.bank,
        account: e.account,
        title: e.title,
        body: e.text.isEmpty ? e.content : e.text,
        direction: e.direction,
        amount: e.amount,
        balance: e.balance,
        postedAt: e.postedAt,
      );

  /// Vị trí của giao dịch: điện thoại đã lấy lúc nhận thông báo, hoặc (app đang mở,
  /// thông báo vừa tới) lấy GPS ngay. Kèm tên địa điểm nếu tra được.
  Future<(double?, double?, String?)> _where(BankEvent e) async {
    final getLocation = locate;
    if (getLocation == null) return (null, null, null);
    var lat = e.lat, lng = e.lng;
    if ((lat == null || lng == null) &&
        DateTime.now().difference(e.postedAt).abs() <= _freshForLocation) {
      final p = await getLocation();
      lat = p?.lat;
      lng = p?.lng;
    }
    if (lat == null || lng == null) return (null, null, null);
    String? place;
    try {
      place = await placeName?.call(lat, lng);
    } catch (_) {}
    return (lat, lng, place);
  }

  static String? guessCategoryKey(BankEvent e) {
    final fromContent = e.content.isEmpty ? null : CategoryGuesser.guessKey(e.content);
    if (fromContent != null) {
      // Chỉ nhận danh mục cùng loại thu/chi.
      const incomeKeys = {'cat_salary', 'cat_bonus', 'cat_investment', 'cat_other_income'};
      final isIncomeKey = incomeKeys.contains(fromContent);
      if (isIncomeKey == e.isIncome) return fromContent;
    }
    return e.isIncome ? 'cat_other_income' : 'cat_other_expense';
  }

  static FinanceTransaction toTransaction(
    BankEvent e, {
    required String userId,
    required String? categoryId,
    required BankLabels labels,
    String? id,
    double? latitude,
    double? longitude,
    String? locationName,
  }) {
    final content = e.content.trim();
    final base = e.isIncome ? labels.incomeName : labels.expenseName;
    // Tiền vào có tên người chuyển -> "Nhận tiền · Nguyễn Văn A" (dễ nhận ra hơn mã giao dịch).
    var name = e.isIncome && e.sender.isNotEmpty
        ? '$base · ${e.sender}'
        : (content.isEmpty ? '$base · ${e.bank}' : content);
    if (name.length > 120) name = name.substring(0, 120);
    var note = labels.autoNote.replaceAll('{bank}', e.bank);
    if (e.isIncome && e.sender.isNotEmpty && content.isNotEmpty) note = '$note\n$content';
    return FinanceTransaction(
      id: id ?? transactionId(e),
      userId: userId,
      name: name,
      amountMinor: e.amount * 100,
      type: e.isIncome ? TxType.income : TxType.expense,
      categoryId: categoryId,
      note: note,
      date: e.postedAt,
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
      createdAt: e.postedAt,
      // updated_at = thời điểm thông báo: nếu user sửa giao dịch trên máy khác thì
      // bản sửa luôn mới hơn (LWW) và không bị ghi đè.
      updatedAt: e.postedAt,
    );
  }
}
