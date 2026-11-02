import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';
import '../models/reminder.dart';

/// A place returned by the backend (Google Places).
class PlaceCandidate {
  const PlaceCandidate({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String name;
  final String address;
  final double lat;
  final double lng;

  factory PlaceCandidate.fromJson(Map<String, dynamic> j) => PlaceCandidate(
        name: (j['name'] as String?) ?? '',
        address: (j['address'] as String?) ?? '',
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
      );
}

/// Result of parsing a spoken reminder.
class ParseResult {
  const ParseResult({
    required this.task,
    required this.locationType,
    required this.locationName,
    this.locationQuery,
    this.candidates = const [],
  });

  final String task;
  final LocationType locationType;
  final String locationName;
  final String? locationQuery;
  final List<PlaceCandidate> candidates;

  factory ParseResult.fromJson(Map<String, dynamic> j) => ParseResult(
        task: (j['task'] as String?) ?? '',
        locationType: LocationType.fromName(j['location_type'] as String?),
        locationName: (j['location_name'] as String?) ?? '',
        locationQuery: j['location_query'] as String?,
        candidates: ((j['candidates'] as List?) ?? [])
            .map((e) => PlaceCandidate.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AiServiceException implements Exception {
  const AiServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Calls the Surya backend (/v1/parse, /v1/nearby, /v1/confirm).
///
/// Behind an interface (§5) so the UI/geofencing can be tested with a fake and
/// the transport can be swapped. Attaches the caller's Firebase ID token.
abstract class AiService {
  Future<ParseResult> parse(String text, {double? lat, double? lng});

  Future<List<PlaceCandidate>> nearby(
    String query,
    double lat,
    double lng, {
    int radiusMeters,
    int limit,
  });

  Future<String> confirm(String task, String locationName, String assistantName);
}

class HttpAiService implements AiService {
  HttpAiService({FirebaseAuth? auth, String? baseUrl})
      : _auth = auth ?? FirebaseAuth.instance,
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final FirebaseAuth _auth;
  final String _baseUrl;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final token = await _auth.currentUser?.getIdToken();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(Uri.parse('$_baseUrl$path'));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      req.add(utf8.encode(jsonEncode(body)));
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return jsonDecode(text) as Map<String, dynamic>;
      }
      throw AiServiceException('Request failed (${resp.statusCode}).');
    } on SocketException {
      throw const AiServiceException('Could not reach the server.');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<ParseResult> parse(String text, {double? lat, double? lng}) async {
    final json = await _post('/v1/parse', {
      'text': text,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return ParseResult.fromJson(json);
  }

  @override
  Future<List<PlaceCandidate>> nearby(
    String query,
    double lat,
    double lng, {
    int radiusMeters = 30000,
    int limit = 20,
  }) async {
    final json = await _post('/v1/nearby', {
      'query': query,
      'lat': lat,
      'lng': lng,
      'radius_meters': radiusMeters,
      'limit': limit,
    });
    return ((json['places'] as List?) ?? [])
        .map((e) => PlaceCandidate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<String> confirm(
      String task, String locationName, String assistantName) async {
    final json = await _post('/v1/confirm', {
      'task': task,
      'location_name': locationName,
      'assistant_name': assistantName,
    });
    return (json['message'] as String?) ?? '';
  }
}
