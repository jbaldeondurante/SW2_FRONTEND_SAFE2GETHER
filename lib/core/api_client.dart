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

    // Interceptor para añadir el token de Supabase si existe (DIP con Supabase)
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final session = Supabase.instance.client.auth.currentSession;
        final accessToken = session?.accessToken;
        if (accessToken != null && accessToken.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $accessToken';
        }
        handler.next(options);
      },
      onError: (e, handler) {
        // Aquí podrías mapear errores de red a mensajes de UI
        handler.next(e);
      },
    ));

    return ApiClient._(dio);
  }

  /// Intenta /health; si no existe, consulta /openapi.json (FastAPI lo expone por defecto)
  Future<String> checkBackend() async {
    try {
      final res = await _dio.get('/health');
      return 'HEALTH: ${res.statusCode} ${res.data}';
    } on DioException catch (_) {
      // Fallback al OpenAPI de FastAPI
      final res = await _dio.get('/openapi.json');
      // recortamos para mostrar nombres de endpoints si existen
      final map = res.data is Map ? res.data as Map : jsonDecode(res.data);
      final paths = (map['paths'] as Map?)?.keys.take(5).join('\n - ');
      return 'OpenAPI detectado. Endpoints:\n - ${paths ?? 's/a'}';
    }
  }
}
