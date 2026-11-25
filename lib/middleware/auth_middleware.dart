import 'package:shelf/shelf.dart';

import '../models/company.dart';
import '../storage/database.dart';
import '../utils/http_helpers.dart';

typedef AuthenticatedHandler =
    Future<Response> Function(Request request, Company company);

/// Extracts the Bearer token from the `Authorization` header, validates it
/// against the database, and passes the authenticated [Company] to [handler].
Handler requireAuth(Database db, AuthenticatedHandler handler) {
  return (Request request) async {
    final authHeader = request.headers['authorization'];
    if (authHeader == null || authHeader.trim().isEmpty) {
      return errorResponse(401, 'Header Authorization mancante.');
    }

    final parts = authHeader.trim().split(RegExp(r'\s+'));
    if (parts.length != 2 || parts[0].toLowerCase() != 'bearer') {
      return errorResponse(
        401,
        'Formato Authorization non valido. Usa: Bearer <token>',
      );
    }

    final token = parts[1].trim();
    if (token.isEmpty) {
      return errorResponse(401, 'Token vuoto o non valido.');
    }

    final company = db.findCompanyByToken(token);
    if (company == null) {
      return errorResponse(401, 'Token non valido o sessione scaduta.');
    }

    return handler(request, company);
  };
}
