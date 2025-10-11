import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'env.dart';

class ApiClient {
  final Dio _dio;

  ApiClient._(this._dio);

  factory ApiClient() {
    final dio = Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    // Añade Bearer si hay sesión
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final session = Supabase.instance.client.auth.currentSession;
      final accessToken = session?.accessToken;
      if (accessToken != null && accessToken.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $accessToken';
      }
      handler.next(options);
    }));

    return ApiClient._(dio);
  }

  // Cliente sin auth para evitar preflight en pings web
  Dio _noAuth() => Dio(BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ));

  // --- Ping de salud ---
  Future<String> checkBackend() async {
    final d = _noAuth();
    try {
      final res = await d.get('/health');
      return 'HEALTH: ${res.statusCode} ${res.data}';
    } on DioException catch (_) {
      final res = await d.get('/openapi.json');
      final map = res.data is Map ? res.data as Map : jsonDecode(res.data);
      final paths = (map['paths'] as Map?)?.keys.take(5).join('\n - ');
      return 'OpenAPI detectado. Endpoints:\n - ${paths ?? 's/a'}';
    }
  }

  // --- Helpers genéricos para tus features ---
  Future<Map<String, dynamic>> getJson(String path, {Map<String, dynamic>? query}) async {
    final res = await _dio.get(path, queryParameters: query);
    return res.data is Map<String, dynamic>
        ? res.data as Map<String, dynamic>
        : (jsonDecode(res.data as String) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body, {Map<String, dynamic>? query}) async {
    final res = await _dio.post(path, data: body, queryParameters: query);
    return res.data is Map<String, dynamic>
        ? res.data as Map<String, dynamic>
        : (jsonDecode(res.data as String) as Map<String, dynamic>);
  }
}
