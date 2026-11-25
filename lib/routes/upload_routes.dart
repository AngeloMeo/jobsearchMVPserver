import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../storage/database.dart';
import '../utils/http_helpers.dart';

class UploadRoutes {
  final Database db;

  UploadRoutes(this.db);

  void register(Router router) {
    router.get('/uploads/<fileName>', _serveUploadedPdf);
  }

  Future<Response> _serveUploadedPdf(Request request, String fileName) async {
    final sanitized = p.basename(fileName);
    if (sanitized != fileName ||
        sanitized.isEmpty ||
        sanitized == '.' ||
        sanitized == '..' ||
        fileName.contains('/') ||
        fileName.contains('\\')) {
      return errorResponse(400, 'Nome file non valido.');
    }

    final file = File(p.join(db.uploadsDirectory.path, sanitized));
    if (!await file.exists()) {
      return errorResponse(404, 'File non trovato.');
    }

    final bytes = await file.readAsBytes();
    return Response.ok(
      bytes,
      headers: {
        'Content-Type': 'application/pdf',
        'Content-Disposition': 'inline; filename="$sanitized"',
        'Content-Length': bytes.length.toString(),
      },
    );
  }
}
