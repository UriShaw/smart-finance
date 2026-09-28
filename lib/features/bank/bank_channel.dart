import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Giao dịch nhận diện từ thông báo ngân hàng (do Android service tạo).
class BankEvent {
  const BankEvent({
    required this.id,
    required this.pkg,
    required this.bank,
    required this.direction,
    required this.amount,
    required this.balance,
    required this.content,
    required this.postedAt,
    this.sender = '',
    this.account = '',
    this.title = '',
    this.text = '',
  });

  final String id;
  final String pkg;
  final String bank;

  /// 1 = tiền vào, -1 = tiền ra.
  final int direction;

  /// Số tiền (đồng).
  final int amount;

  /// Số dư sau giao dịch, -1 nếu thông báo không có.
  final int balance;
  final String content;
  final DateTime postedAt;

  /// Tên người chuyển (chỉ tiền vào; "" nếu nội dung là mã).
  final String sender;

  /// 4 số cuối tài khoản/thẻ ("" nếu thông báo không ghi).
  final String account;

  /// Tiêu đề + nội dung thông báo gốc (chỉ lưu trên máy).
  final String title;
  final String text;

  bool get isIncome => direction > 0;

  static BankEvent? tryParse(Map<Object?, Object?> m) {
    final id = m['id'];
    final amount = m['amount'];
    final dir = m['direction'];
    if (id is! String || amount is! int || dir is! int || amount <= 0) return null;
    final posted = m['postedAt'];
    return BankEvent(
      id: id,
      pkg: (m['pkg'] as String?) ?? '',
      bank: (m['bank'] as String?) ?? '',
      direction: dir >= 0 ? 1 : -1,
      amount: amount,
      balance: (m['balance'] as int?) ?? -1,
      content: (m['content'] as String?) ?? '',
      sender: (m['sender'] as String?) ?? '',
      account: (m['account'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      text: (m['text'] as String?) ?? '',
      postedAt: posted is int ? DateTime.fromMillisecondsSinceEpoch(posted) : DateTime.now(),
    );
  }
}

class BankLogEntry {
  const BankLogEntry({
    required this.time,
    required this.pkg,
    required this.bank,
    required this.saved,
    required this.reason,
    required this.amount,
    required this.direction,
    required this.preview,
  });

  final DateTime time;
  final String pkg;
  final String bank;
  final bool saved;
  final String reason;
  final int amount;
  final int direction;
  final String preview;

  static BankLogEntry fromMap(Map<Object?, Object?> m) => BankLogEntry(
        time: DateTime.fromMillisecondsSinceEpoch((m['time'] as int?) ?? 0),
        pkg: (m['pkg'] as String?) ?? '',
        bank: (m['bank'] as String?) ?? '',
        saved: m['saved'] == true,
        reason: (m['reason'] as String?) ?? '',
        amount: (m['amount'] as int?) ?? 0,
        direction: (m['direction'] as int?) ?? 0,
        preview: (m['preview'] as String?) ?? '',
      );
}

class BankConfig {
  const BankConfig({
    this.enabled = false,
    this.speak = true,
    this.speakExpense = true,
    this.allow = const [],
    this.block = const [],
    this.pending = 0,
    this.volumeBoost = true,
    this.voice = 'female',
    this.chime = 'default',
    this.rate = 1.0,
    this.pitch = 1.0,
    this.batteryIgnored = false,
  });

  final bool enabled;
  final bool speak;
  final bool speakExpense;
  final List<String> allow;
  final List<String> block;
  final int pending;

  /// Khuếch đại âm lượng khi đọc (tính năng app cũ).
  final bool volumeBoost;

  /// 'female' | 'male'.
  final String voice;

  /// 'default' (ting_ting.mp3) | 'ting' (chuông tổng hợp) | 'none'.
  final String chime;
  final double rate;
  final double pitch;

  /// Đã được bỏ qua tối ưu hoá pin (chỉ đọc).
  final bool batteryIgnored;

  BankConfig copyWith({
    bool? enabled,
    bool? speak,
    bool? speakExpense,
    List<String>? allow,
    List<String>? block,
    bool? volumeBoost,
    String? voice,
    String? chime,
    double? rate,
    double? pitch,
  }) =>
      BankConfig(
        enabled: enabled ?? this.enabled,
        speak: speak ?? this.speak,
        speakExpense: speakExpense ?? this.speakExpense,
        allow: allow ?? this.allow,
        block: block ?? this.block,
        pending: pending,
        volumeBoost: volumeBoost ?? this.volumeBoost,
        voice: voice ?? this.voice,
        chime: chime ?? this.chime,
        rate: rate ?? this.rate,
        pitch: pitch ?? this.pitch,
        batteryIgnored: batteryIgnored,
      );
}

class BankTestResult {
  const BankTestResult({
    required this.accepted,
    required this.reason,
    required this.amount,
    required this.direction,
    required this.balance,
    required this.bank,
    required this.content,
    required this.announcement,
  });

  final bool accepted;
  final String reason;
  final int amount;
  final int direction;
  final int balance;
  final String bank;
  final String content;
  final String announcement;
}

/// Cầu nối tới Android (BankChannel.java). Trên Windows/iOS mọi hàm là no-op.
class BankChannel {
  BankChannel();

  static const _ch = MethodChannel('smart_finance/bank');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  void setOnPending(VoidCallback? onPending) {
    if (!supported) return;
    _ch.setMethodCallHandler(onPending == null
        ? null
        : (call) async {
            if (call.method == 'pendingChanged') onPending();
            return null;
          });
  }

  Future<bool> isPermissionGranted() async =>
      supported && (await _ch.invokeMethod<bool>('isPermissionGranted') ?? false);

  Future<void> openPermissionSettings() => _call('openPermissionSettings');
  Future<void> openAppDetails() => _call('openAppDetails');
  Future<void> openBatterySettings() => _call('openBatterySettings');

  Future<BankConfig> getConfig() async {
    if (!supported) return const BankConfig();
    final m = await _ch.invokeMethod<Map<Object?, Object?>>('getConfig') ?? const {};
    List<String> list(Object? v) => v is List ? v.whereType<String>().toList() : const <String>[];
    return BankConfig(
      enabled: m['enabled'] == true,
      speak: m['speak'] != false,
      speakExpense: m['speakExpense'] != false,
      allow: list(m['allow']),
      block: list(m['block']),
      pending: (m['pending'] as int?) ?? 0,
      volumeBoost: m['volumeBoost'] != false,
      voice: (m['voice'] as String?) ?? 'female',
      chime: (m['chime'] as String?) ?? 'default',
      rate: (m['rate'] as num?)?.toDouble() ?? 1.0,
      pitch: (m['pitch'] as num?)?.toDouble() ?? 1.0,
      batteryIgnored: m['batteryIgnored'] == true,
    );
  }

  Future<void> setAudio(BankConfig c) async {
    if (!supported) return;
    await _ch.invokeMethod<void>('setAudio', {
      'volumeBoost': c.volumeBoost,
      'voice': c.voice,
      'chime': c.chime,
      'rate': c.rate,
      'pitch': c.pitch,
    });
  }

  /// Âm báo + đọc câu mẫu với cài đặt hiện tại.
  Future<void> preview(String text) async {
    if (!supported) return;
    await _ch.invokeMethod<void>('preview', {'text': text});
  }

  /// Giả lập một tin nhắn ngân hàng: nhận diện, lưu giao dịch, đọc to (như app cũ).
  Future<BankTestResult?> simulate(String text) async {
    if (!supported) return null;
    final m = await _ch.invokeMethod<Map<Object?, Object?>>('simulate', {'text': text});
    return m == null ? null : _result(m);
  }

  Future<void> restartListener() => _call('restartListener');
  Future<void> openTtsSettings() => _call('openTtsSettings');
  Future<void> openAutostart() => _call('openAutostart');
  Future<void> requestIgnoreBattery() => _call('requestIgnoreBattery');

  Future<void> setConfig(BankConfig c) async {
    if (!supported) return;
    await _ch.invokeMethod<void>('setConfig', {
      'enabled': c.enabled,
      'speak': c.speak,
      'speakExpense': c.speakExpense,
      'allow': c.allow,
      'block': c.block,
    });
  }

  Future<List<BankEvent>> getPending() async {
    if (!supported) return const [];
    final list = await _ch.invokeMethod<List<Object?>>('getPending') ?? const [];
    final out = <BankEvent>[];
    for (final e in list) {
      if (e is! Map<Object?, Object?>) continue;
      final ev = BankEvent.tryParse(e);
      if (ev != null) out.add(ev);
    }
    return out;
  }

  Future<void> ackPending(List<String> ids) async {
    if (!supported || ids.isEmpty) return;
    await _ch.invokeMethod<void>('ackPending', {'ids': ids});
  }

  Future<List<BankLogEntry>> getLog() async {
    if (!supported) return const [];
    final list = await _ch.invokeMethod<List<Object?>>('getLog') ?? const [];
    return [
      for (final e in list)
        if (e is Map<Object?, Object?>) BankLogEntry.fromMap(e),
    ].reversed.toList();
  }

  Future<void> clearLog() => _call('clearLog');

  Future<BankTestResult?> testParse({
    required String pkg,
    required String title,
    required String text,
  }) async {
    if (!supported) return null;
    final m = await _ch.invokeMethod<Map<Object?, Object?>>(
        'testParse', {'pkg': pkg, 'title': title, 'text': text});
    if (m == null) return null;
    return _result(m);
  }

  static BankTestResult _result(Map<Object?, Object?> m) {
    return BankTestResult(
      accepted: m['accepted'] == true,
      reason: (m['reason'] as String?) ?? '',
      amount: (m['amount'] as int?) ?? 0,
      direction: (m['direction'] as int?) ?? 0,
      balance: (m['balance'] as int?) ?? -1,
      bank: (m['bank'] as String?) ?? '',
      content: (m['content'] as String?) ?? '',
      announcement: (m['announcement'] as String?) ?? '',
    );
  }

  Future<void> speak(String text) async {
    if (!supported) return;
    await _ch.invokeMethod<void>('speak', {'text': text});
  }

  Future<List<String>> supportedBanks() async {
    if (!supported) return const [];
    final list = await _ch.invokeMethod<List<Object?>>('supportedBanks') ?? const [];
    return list.whereType<String>().toList();
  }

  Future<void> _call(String method) async {
    if (!supported) return;
    await _ch.invokeMethod<void>(method);
  }
}
