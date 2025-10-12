// lib/core/geocoding_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

import 'env.dart';

class GeocodingService {
  /// 🗺️ Coordenadas por dirección (Google Geocoding)
  Future<LocationResult?> getCoordinatesFromAddress(String address) async {
    final clean = address.trim();
    if (clean.isEmpty) return null;

    try {
      String fullAddress = clean;
      final low = clean.toLowerCase();
      if (!low.contains('lima') && !low.contains('perú') && !low.contains('peru')) {
        fullAddress = '$clean, Lima, Perú';
      }

      final apiKey = Env.googleMapsApiKey;
      if (apiKey.isEmpty) {
        throw Exception('Google Maps API Key no configurada');
      }

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeComponent(fullAddress)}'
        '&key=$apiKey',
      );

      final res = await http.get(url);
      if (res.statusCode != 200) {
        print('Geocoding HTTP ${res.statusCode}: ${res.body}');
        return null;
      }

      final data = jsonDecode(res.body);
      if (data['status'] == 'OK' && data['results'].isNotEmpty) {
        final loc = data['results'][0]['geometry']['location'];
        final formatted = data['results'][0]['formatted_address'];
        return LocationResult(
          latitude: (loc['lat'] as num).toDouble(),
          longitude: (loc['lng'] as num).toDouble(),
          formattedAddress: formatted.toString(),
        );
      }

      print('Geocoding falló: ${data['status']} / ${data['error_message']}');
      return null;
    } catch (e) {
      print('Error en geocodificación: $e');
      return null;
    }
  }

  /// 📍 Ubicación actual (Geolocator)
  Future<LocationResult?> getCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return null;
      }
      if (perm == LocationPermission.deniedForever) return null;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return LocationResult(
        latitude: pos.latitude,
        longitude: pos.longitude,
        formattedAddress: 'Mi ubicación',
      );
    } catch (e) {
      print('Error obteniendo ubicación: $e');
      return null;
    }
  }

  /// 🔍 Sugerencias de direcciones (Google Places Autocomplete)
  Future<List<String>> searchAddresses(String query) async {
  final q = query.trim();
  if (q.length < 3) return [];

  try {
    // Llamamos a TU backend (usa Env.apiBaseUrl que ya tienes)
    final url = Uri.parse('${Env.apiBaseUrl}/places/autocomplete?q=${Uri.encodeComponent(q)}');

    final res = await http.get(url);
    if (res.statusCode != 200) {
      print('Proxy places HTTP ${res.statusCode}: ${res.body}');
      return [];
    }

    final data = jsonDecode(res.body);
    final status = data['status'];
    if (status == 'OK') {
      final preds = (data['predictions'] as List);
      return preds.map((p) => p['description'].toString()).toList();
    } else {
      print('Proxy places error: $status / ${data['error_message']}');
      return [];
    }
  } catch (e) {
    print('Proxy places exception: $e');
    return [];
  }
}
}

class LocationResult {
  final double latitude;
  final double longitude;
  final String formattedAddress;

  LocationResult({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
  });
}
