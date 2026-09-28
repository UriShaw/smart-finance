/// Cấu hình môi trường, truyền vào lúc build bằng
/// `--dart-define-from-file=config/env.json` (script build tự làm).
///
/// KHÔNG đặt service-role key ở đây. Chỉ URL + anon key (public, được RLS bảo vệ).
class Env {
  const Env._();

  static const String _buildUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _buildKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Máy chủ đang dùng: mặc định lấy từ lúc build, có thể đổi trong app
  /// (Cài đặt → Máy chủ) mà không cần build lại - xem CloudConfig.
  static String _url = _buildUrl;
  static String _key = _buildKey;

  static String get supabaseUrl => _url;
  static String get supabaseAnonKey => _key;

  /// Máy chủ gắn sẵn lúc build (config/env.json).
  static String get buildUrl => _buildUrl;
  static String get buildKey => _buildKey;

  static void useServer(String url, String key) {
    _url = url;
    _key = key;
  }

  static const String appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'development');
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  /// Khoá Maps SDK for Android (Google Cloud). Rỗng -> dùng OpenStreetMap.
  /// Gradle đọc cùng giá trị này để ghi vào AndroidManifest (android/app/build.gradle.kts).
  static const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
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
