import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'routes/auth_routes.dart';
import 'routes/job_routes.dart';
import 'routes/upload_routes.dart';
import 'storage/database.dart';
import 'utils/http_helpers.dart';

/// Costruisce l'intera pipeline HTTP del server:
/// Richiesta -> CORS -> Gestione Errori -> Log -> Router (Endpoint).
Handler createServerHandler(Database db, {bool enableLogging = true}) {
  final router = Router(
    notFoundHandler: (Request request) {
      return errorResponse(
        404,
        'Endpoint non trovato: ${request.method} ${request.requestedUri.path}',
      );
    },
  );

  // Endpoint di health-check veloce per verificare che il server risponda.
  router.get('/', (Request request) {
    return jsonResponse(200, {
      'status': 'ok',
      'service': 'jobsearch_mvp_server',
    });
  });

  AuthRoutes(db).register(router);
  JobRoutes(db).register(router);
  UploadRoutes(db).register(router);

  var pipeline = const Pipeline()
      .addMiddleware(corsMiddleware())
      .addMiddleware(_errorHandlingMiddleware());

  if (enableLogging) {
    pipeline = pipeline.addMiddleware(logRequests());
  }

  return pipeline.addHandler(router.call);
}

Middleware _errorHandlingMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      try {
        return await innerHandler(request);
      } catch (e) {
        return errorResponse(500, 'Errore interno del server: $e');
      }
    };
  };
}
