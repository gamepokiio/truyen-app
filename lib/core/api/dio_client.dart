import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const kBaseUrl = 'https://truyencv.io/wp-json';
const _storage = FlutterSecureStorage();

/// Cache store dùng chung — MemCacheStore: in-memory, không cần init
/// TTL 5 phút cho chapter/novel list (đủ cho 1 session đọc truyện)
final _cacheStore = MemCacheStore(maxSize: 10 * 1024 * 1024); // 10 MB

final _cacheOptions = CacheOptions(
  store: _cacheStore,
  policy: CachePolicy.refreshForceCache, // dùng cache nếu có, fetch nếu hết TTL
  maxStale: const Duration(minutes: 5),
  hitCacheOnErrorExcept: [401, 403],     // dùng cache kể cả khi lỗi network
  keyBuilder: CacheOptions.defaultCacheKeyBuilder,
);

/// Dio dùng cho auth / user endpoints (không cache)
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: kBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));
  dio.interceptors.add(_JwtInterceptor());
  return dio;
});

/// Dio dùng cho content endpoints (novel, chapter) — có HTTP cache
/// Cache hit → 0ms, không tốn bandwidth, không chờ server
final cachedDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: kBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));
  dio.interceptors
    ..add(_JwtInterceptor())
    ..add(DioCacheInterceptor(options: _cacheOptions));
  return dio;
});

class _JwtInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: 'jwt_token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err);
  }
}

/// Lưu JWT token
Future<void> saveToken(String token) async {
  await _storage.write(key: 'jwt_token', value: token);
}

/// Xóa JWT token (logout)
Future<void> clearToken() async {
  await _storage.delete(key: 'jwt_token');
}

/// Đọc JWT token hiện tại
Future<String?> getToken() async {
  return _storage.read(key: 'jwt_token');
}
