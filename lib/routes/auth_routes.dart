import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../middleware/auth_middleware.dart';
import '../models/company.dart';
import '../storage/database.dart';
import '../utils/http_helpers.dart';
import '../utils/security.dart';

class AuthRoutes {
  final Database db;

  AuthRoutes(this.db);

  void register(Router router) {
    router.post('/auth/register', _register);
    router.post('/auth/login', _login);
    router.post('/auth/logout', requireAuth(db, _logout));
  }

  Future<Response> _register(Request request) async {
    try {
      final body = await readJsonBody(request);
      if (body == null) {
        return errorResponse(400, 'Body JSON mancante.');
      }

      final nomeAzienda = (body['nomeAzienda'] as String?)?.trim() ?? '';
      final email = (body['email'] as String?)?.trim().toLowerCase() ?? '';
      final password = (body['password'] as String?) ?? '';

      if (nomeAzienda.isEmpty || email.isEmpty || password.isEmpty) {
        return errorResponse(
          400,
          'I campi nomeAzienda, email e password sono obbligatori.',
        );
      }

      if (!isValidEmail(email)) {
        return errorResponse(400, 'Formato email non valido.');
      }

      if (password.length < 6) {
        return errorResponse(
          400,
          'La password deve contenere almeno 6 caratteri.',
        );
      }

      if (db.findCompanyByEmail(email) != null) {
        return errorResponse(
          409,
          'Esiste già un\'azienda registrata con questa email.',
        );
      }

      final company = Company(
        id: generateId(),
        nomeAzienda: nomeAzienda,
        email: email,
        passwordHash: hashPassword(password),
      );

      await db.insertCompany(company);

      return jsonResponse(201, {
        'message': 'Azienda registrata con successo.',
        'company': company.toPublicJson(),
      });
    } on FormatException {
      return errorResponse(400, 'Body JSON non valido.');
    }
  }

  Future<Response> _login(Request request) async {
    try {
      final body = await readJsonBody(request);
      if (body == null) {
        return errorResponse(400, 'Body JSON mancante.');
      }

      final email = (body['email'] as String?)?.trim().toLowerCase() ?? '';
      final password = (body['password'] as String?) ?? '';

      if (email.isEmpty || password.isEmpty) {
        return errorResponse(400, 'Email e password sono obbligatorie.');
      }

      final company = db.findCompanyByEmail(email);
      if (company == null || !verifyPassword(password, company.passwordHash)) {
        return errorResponse(401, 'Credenziali non valide.');
      }

      final token = generateToken();
      await db.updateCompanyToken(company.id, token);

      return jsonResponse(200, {
        'token': token,
        'companyId': company.id,
        'nomeAzienda': company.nomeAzienda,
      });
    } on FormatException {
      return errorResponse(400, 'Body JSON non valido.');
    }
  }

  Future<Response> _logout(Request request, Company company) async {
    await db.updateCompanyToken(company.id, null);
    return jsonResponse(200, {'message': 'Logout effettuato con successo.'});
  }
}
