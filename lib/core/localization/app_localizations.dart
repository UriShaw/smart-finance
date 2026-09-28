import 'package:flutter/widgets.dart';

import 'strings_en.dart';
import 'strings_vi.dart';
import 'strings_zh.dart';

/// Localization không cần code generation. Mọi chuỗi hiển thị lấy qua khóa
/// (spec M: không hard-code text trong widget).
class AppLocalizations {
  AppLocalizations(this.locale) : _map = _resolve(locale);

  final Locale locale;
  final Map<String, String> _map;

  static const supportedLocales = <Locale>[
    Locale('vi'),
    Locale('en'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate = _Delegate();

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      AppLocalizations(const Locale('vi'));

  static bool isTraditional(Locale l) =>
      l.languageCode == 'zh' &&
      (l.scriptCode == 'Hant' || const ['TW', 'HK', 'MO'].contains(l.countryCode));

  static Map<String, String> _resolve(Locale l) {
    switch (l.languageCode) {
      case 'en':
        return stringsEn;
      case 'zh':
        return isTraditional(l) ? stringsZhHant : stringsZhHans;
      default:
        return stringsVi;
    }
  }

  /// Tên locale dạng chuẩn cho intl (định dạng số/ngày).
  String get intlLocale {
    switch (locale.languageCode) {
      case 'en':
        return 'en_US';
      case 'zh':
        return isTraditional(locale) ? 'zh_TW' : 'zh_CN';
      default:
        return 'vi_VN';
    }
  }

  String t(String key, [Map<String, Object?> args = const {}]) {
    var s = _map[key] ?? stringsEn[key] ?? key;
    if (args.isNotEmpty) {
      args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
    }
    return s;
  }
}

class _Delegate extends LocalizationsDelegate<AppLocalizations> {
  const _Delegate();

  @override
  bool isSupported(Locale locale) => const ['vi', 'en', 'zh'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);

  @override
  bool shouldReload(_Delegate old) => false;
}

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String tr(String key, [Map<String, Object?> args = const {}]) =>
      AppLocalizations.of(this).t(key, args);
}
