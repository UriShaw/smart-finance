/// Cấu hình môi trường, truyền vào lúc build bằng
/// `--dart-define-from-file=config/env.json` (script build tự làm).
///
/// KHÔNG đặt service-role key ở đây. Chỉ URL + anon key (public, được RLS bảo vệ).
class Env {
  const Env._();

  /// Máy chủ Supabase gắn lúc build (config/env.json) — không đổi được trong app.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const String appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'development');
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  /// Khoá Maps SDK for Android (Google Cloud). Rỗng -> dùng OpenStreetMap.
  /// Gradle đọc cùng giá trị này để ghi vào AndroidManifest (android/app/build.gradle.kts).
  static const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  /// OAuth client loại "Web application" của project Google Cloud "UriShaw" — cùng project
  /// với client Android (package + SHA-1) và màn Branding "Smart Finance". Đăng nhập gốc
  /// Android xin ID token cho client này; ID phải có trong Supabase → Auth → Google →
  /// Client IDs. Client ID là định danh công khai (không phải secret).
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '246181472090-d83ksv22igdjk2afgiqegdv6va6vgkpa.apps.googleusercontent.com',
  );
  static const int oauthDesktopPort = int.fromEnvironment('OAUTH_DESKTOP_PORT', defaultValue: 3789);

  /// Deep link cho Android/iOS (khai báo trong AndroidManifest bởi script).
  static const String mobileRedirect = 'io.smartfinance.app://login-callback';

  /// Redirect loopback cho Windows/macOS/Linux.
  static String get desktopRedirect => 'http://localhost:$oauthDesktopPort/auth-callback';

  static bool get cloudConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// true khi Supabase.initialize thành công (main.dart). Nếu khởi tạo lỗi,
  /// app chạy offline thay vì crash.
  static bool cloudReady = false;
}
