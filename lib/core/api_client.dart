import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'env.dart';

class ApiClient {
  final Dio _dio;
  // Token de backend (bearer) establecido tras un login exitoso contra tu API.
  // Si está presente, se usará como Authorization en lugar del token de Supabase.
  static String? backendAccessToken;

  ApiClient._(this._dio);

  factory ApiClient() {
    final dio = Dio(
      BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        headers: const {'Content-Type': 'application/json; charset=utf-8'},
        // No lances excepción por 4xx (deja que lo manejemos)
        validateStatus: (code) => code != null && code < 500,
      ),
    );

    // Añade Bearer si hay sesión (prioriza token del backend si existe)
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final backendToken = ApiClient.backendAccessToken;
          if (backendToken != null && backendToken.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $backendToken';
          } else {
            final session = Supabase.instance.client.auth.currentSession;
            final accessToken = session?.accessToken;
            if (accessToken != null && accessToken.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $accessToken';
            }
          }
          handler.next(options);
        },
      ),
    );

    return ApiClient._(dio);
  }

  Dio _noAuth() => Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
      validateStatus: (code) => code != null && code < 500,
    ),
  );

  // --- Utilidad: parsear respuesta en Map de forma segura ---
  Map<String, dynamic> _asMap(Response res) {
    if (res.data == null) return {'status': res.statusCode};
    if (res.data is Map<String, dynamic>) {
      final map = Map<String, dynamic>.from(res.data as Map<String, dynamic>);
      // Asegura que siempre devolvemos el status HTTP.
      map.putIfAbsent('status', () => res.statusCode);
      return map;
    }
    if (res.data is List) {
      // Si la API devuelve un array JSON, envuélvelo en 'data' para consumo homogéneo
      final list = List<dynamic>.from(res.data as List);
      return {'status': res.statusCode, 'data': list};
    }
    final s = res.data.toString();
    if (s.isEmpty) return {'status': res.statusCode};
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'status': res.statusCode, 'data': decoded};
    } catch (_) {
      return {'status': res.statusCode, 'raw': s};
    }
  }

  String _prettyDioError(DioException e) {
    // Errores típicos de CORS / Mixed Content en Web
    final msg = e.message ?? '';
    if (msg.contains('XMLHttpRequest error') ||
        msg.contains('Failed to fetch') ||
        msg.contains('Network Error')) {
      return 'No se pudo alcanzar la API. Posible CORS / Mixed Content / URL inválida (${Env.apiBaseUrl}).';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Tiempo de espera agotado conectando a la API.';
    }
    return 'Error de red: $msg';
  }

  // --- Health ---
  Future<String> checkBackend() async {
    final d = _noAuth();
    try {
      final res = await d.get('/health').timeout(const Duration(seconds: 8));
      return 'HEALTH: ${res.statusCode} ${res.data}';
    } on DioException catch (e) {
      return _prettyDioError(e);
    } on Exception {
      // intenta descubrir openapi
      try {
        final res = await d
            .get('/openapi.json')
            .timeout(const Duration(seconds: 8));
        final map = _asMap(res);
        final paths = (map['paths'] as Map?)?.keys.take(5).join('\n - ');
        return 'OpenAPI detectado. Endpoints:\n - ${paths ?? 's/a'}';
      } catch (_) {
        rethrow;
      }
    }
  }

  // --- Helpers genéricos seguros con timeout ---
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio
          .get(path, queryParameters: query)
          .timeout(const Duration(seconds: 12));
      return _asMap(res);
    } on DioException catch (e) {
      throw Exception(_prettyDioError(e));
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio
          .post(path, data: body, queryParameters: query)
          .timeout(const Duration(seconds: 12));
      return _asMap(res);
    } on DioException catch (e) {
      throw Exception(_prettyDioError(e));
    }
  }

  // --- Integración explícita con tu FastAPI ---
  Future<Map<String, dynamic>> createUser({
    required String user,
    required String email,
    required String psswd,
  }) async {
    final r = await postJson('/users', {
      'user': user,
      'email': email,
      'psswd': psswd,
    });
    final code = r['status'] as int?; // si lo llenó _asMap
    if (code != null && code >= 400) {
      throw Exception('API /users respondió $code: ${jsonEncode(r)}');
    }
    return r;
  }

  Future<Map<String, dynamic>> loginBackend({
    required String user,
    required String psswd,
  }) async {
    final r = await postJson('/auth/login', {'user': user, 'psswd': psswd});
    final code = r['status'] as int?;
    if (code != null && code >= 400) {
      throw Exception('API /auth/login respondió $code: ${jsonEncode(r)}');
    }
    return r;
  }

  // --- Ranking distritos ---
  Future<List<dynamic>> getDistrictRanking({String period = 'week'}) async {
    try {
      final res = await getJson('/Reportes/ranking/distritos', query: {
        'period': period,
      });
      final code = res['status'] as int?;
      if (code != null && code >= 400) {
        throw Exception('Error HTTP $code al obtener ranking');
      }
      final data = res['data'];
      if (data is List) return data;
      return [];
    } catch (e) {
      // Relanzar con mensaje más claro
      if (e.toString().contains('XMLHttpRequest') || 
          e.toString().contains('Network') ||
          e.toString().contains('CORS')) {
        throw Exception('No se pudo conectar con el servidor. Verifica que el backend esté corriendo.');
      }
      rethrow;
    }
  }
}
