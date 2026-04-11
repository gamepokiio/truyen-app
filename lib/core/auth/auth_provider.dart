import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../api/dio_client.dart';
import '../api/novel_api.dart';
import '../../shared/models/novel_model.dart';

part 'auth_provider.g.dart';

// ─── Error parser ─────────────────────────────────────────────────────────────
// WP REST API trả về {code, message, data:{status}} khi lỗi.
// Ưu tiên lấy message từ response body, fallback theo HTTP status code.

String _parseError(Object e) {
  if (e is DioException) {
    // Thử đọc message từ response body (WP REST API format)
    try {
      final data = e.response?.data;
      if (data is Map) {
        final wpMsg = data['message'] as String?;
        final wpCode = data['code'] as String?;
        if (wpMsg != null && wpMsg.isNotEmpty) {
          return _wpMessageVi(wpCode, wpMsg);
        }
      }
    } catch (_) {}

    // Fallback theo HTTP status code
    final status = e.response?.statusCode;
    switch (status) {
      case 400: return 'Thông tin không hợp lệ. Vui lòng kiểm tra lại.';
      case 401: return 'Tên đăng nhập hoặc mật khẩu không đúng.';
      case 403: return 'Tài khoản không có quyền truy cập.';
      case 409: return 'Tên đăng nhập hoặc email đã được sử dụng.';
      case 422: return 'Dữ liệu không hợp lệ. Vui lòng kiểm tra lại.';
      case 429: return 'Quá nhiều yêu cầu. Vui lòng thử lại sau.';
      case 500:
      case 502:
      case 503: return 'Lỗi máy chủ. Vui lòng thử lại sau.';
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout) {
          return 'Kết nối quá chậm. Vui lòng thử lại.';
        }
        if (e.type == DioExceptionType.connectionError) {
          return 'Không có kết nối mạng. Kiểm tra internet và thử lại.';
        }
        return 'Đã xảy ra lỗi. Vui lòng thử lại.';
    }
  }
  return 'Đã xảy ra lỗi. Vui lòng thử lại.';
}

// Ánh xạ WP error code → tiếng Việt thân thiện
String _wpMessageVi(String? code, String fallback) {
  switch (code) {
    case 'existing_user_login':   return 'Tên đăng nhập đã tồn tại.';
    case 'existing_user_email':   return 'Email này đã được sử dụng.';
    case 'invalid_username':      return 'Tên đăng nhập không tồn tại.';
    case 'invalid_email':         return 'Email không tồn tại trong hệ thống.';
    case 'incorrect_password':    return 'Mật khẩu không đúng.';
    case 'jwt_auth_bad_auth_header':
    case 'jwt_auth_bad_iss':
    case 'jwt_auth_bad_credentials': return 'Tên đăng nhập hoặc mật khẩu không đúng.';
    case 'jwt_auth_invalid_token':   return 'Phiên đăng nhập hết hạn. Vui lòng đăng nhập lại.';
    case 'registration-error-email-exists': return 'Email này đã được sử dụng.';
    case 'registration-error-username-invalid': return 'Tên đăng nhập không hợp lệ (chỉ chứa chữ, số, gạch dưới).';
    default: return fallback;
  }
}

class AuthState {
  final UserProfile? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});
}

@riverpod
class Auth extends _$Auth {
  @override
  Future<AuthState> build() async {
    final token = await getToken();
    if (token == null) return const AuthState();
    try {
      final api = UserApi(ref.read(dioProvider));
      final data = await api.getMe();
      return AuthState(user: UserProfile.fromJson(data));
    } catch (_) {
      await clearToken();
      return const AuthState();
    }
  }

  Future<void> login(String username, String password) async {
    state = const AsyncValue.loading();
    try {
      final api = UserApi(ref.read(dioProvider));
      final data = await api.login(username, password);
      final token = data['token'] as String;
      await saveToken(token);
      final me = await api.getMe();
      state = AsyncValue.data(AuthState(user: UserProfile.fromJson(me)));
    } catch (e) {
      state = AsyncValue.data(AuthState(error: _parseError(e)));
    }
  }

  Future<void> register(String username, String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final api = UserApi(ref.read(dioProvider));
      await api.register(username, email, password);
      // Tự động login sau khi đăng ký thành công
      await login(username, password);
    } catch (e) {
      state = AsyncValue.data(AuthState(error: _parseError(e)));
    }
  }

  Future<void> logout() async {
    await clearToken();
    state = const AsyncValue.data(AuthState());
  }

  Future<void> deleteAccount() async {
    try {
      final api = UserApi(ref.read(dioProvider));
      await api.deleteAccount();
      await clearToken();
      state = const AsyncValue.data(AuthState());
    } catch (e) {
      // Giữ state cũ, trả lỗi để UI hiển thị
      final current = state.valueOrNull ?? const AuthState();
      state = AsyncValue.data(AuthState(
        user: current.user,
        error: _parseError(e),
      ));
    }
  }
}
