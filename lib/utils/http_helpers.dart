import 'dart:convert';

import 'package:shelf/shelf.dart';

const Map<String, String> corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
      'Origin, Content-Type, Accept, Authorization, X-Requested-With',
  'Access-Control-Max-Age': '86400',
};

/// Middleware Shelf: intercetta le richieste prima/dopo gli endpoint.
/// Risponde alle preflight OPTIONS e aggiunge gli header CORS a tutte le risposte.
Middleware corsMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method.toUpperCase() == 'OPTIONS') {
        return Response.ok('', headers: corsHeaders);
      }

      final response = await innerHandler(request);
      return response.change(headers: corsHeaders);
    };
  };
}

Response jsonResponse(int statusCode, Object? data) {
  return Response(
    statusCode,
    body: jsonEncode(data),
    headers: const {'Content-Type': 'application/json; charset=utf-8'},
  );
}

Response errorResponse(int statusCode, String message) {
  return jsonResponse(statusCode, {'error': message});
}

/// Legge e decodifica il body JSON della richiesta; restituisce null se vuoto.
Future<Map<String, dynamic>?> readJsonBody(Request request) async {
  final raw = await request.readAsString();
  if (raw.trim().isEmpty) return null;

  final decoded = jsonDecode(raw);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  return null;
}

/// Ricostruisce lo schema + host + porta (es. http://192.168.1.10:8080)
/// usando l'URL con cui il client ha contattato il server.
String extractBaseUrl(Request request) {
  final uri = request.requestedUri;
  final hasExplicitPort =
      (uri.scheme == 'http' && uri.port != 80) ||
      (uri.scheme == 'https' && uri.port != 443);
  return hasExplicitPort
      ? '${uri.scheme}://${uri.host}:${uri.port}'
      : '${uri.scheme}://${uri.host}';
}

bool isValidEmail(String email) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
}
