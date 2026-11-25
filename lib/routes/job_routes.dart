import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:shelf_router/shelf_router.dart';

import '../middleware/auth_middleware.dart';
import '../models/application.dart';
import '../models/company.dart';
import '../models/job.dart';
import '../storage/database.dart';
import '../utils/http_helpers.dart';
import '../utils/security.dart';

class JobRoutes {
  static const int maxCvBytes = 15 * 1024 * 1024; // 15 MB

  final Database db;

  JobRoutes(this.db);

  void register(Router router) {
    router.get('/jobs', _getAllJobs);
    router.post('/jobs', requireAuth(db, _createJob));
    router.get('/company/jobs', requireAuth(db, _getCompanyJobs));
    router.post('/jobs/<jobId>/apply', _applyToJob);
    router.get(
      '/jobs/<jobId>/applications',
      requireAuth(db, _getJobApplications),
    );
  }

  Future<Response> _getAllJobs(Request request) async {
    final jobs = db.getAllJobs().map((j) => j.toJson()).toList();
    return jsonResponse(200, jobs);
  }

  Future<Response> _createJob(Request request, Company company) async {
    try {
      final body = await readJsonBody(request);
      if (body == null) {
        return errorResponse(400, 'Body JSON mancante.');
      }

      final titolo = (body['titolo'] as String?)?.trim() ?? '';
      final descrizione = (body['descrizione'] as String?)?.trim() ?? '';

      if (titolo.isEmpty || descrizione.isEmpty) {
        return errorResponse(
          400,
          'I campi titolo e descrizione sono obbligatori.',
        );
      }

      final job = Job(
        id: generateId(),
        companyId: company.id,
        nomeAzienda: company.nomeAzienda,
        titolo: titolo,
        descrizione: descrizione,
        dataPubblicazione: DateTime.now().toUtc().toIso8601String(),
      );

      await db.insertJob(job);
      return jsonResponse(201, job.toJson());
    } on FormatException {
      return errorResponse(400, 'Body JSON non valido.');
    }
  }

  Future<Response> _getCompanyJobs(Request request, Company company) async {
    final jobs = db
        .getJobsByCompany(company.id)
        .map((j) => j.toJson())
        .toList();
    return jsonResponse(200, jobs);
  }

  Future<Response> _applyToJob(Request request, String jobId) async {
    final job = db.findJobById(jobId);
    if (job == null) {
      return errorResponse(404, 'Annuncio non trovato.');
    }

    // Estrae i dati multipart/form-data (campi testuali + file PDF).
    final form = request.formData();
    if (form == null) {
      return errorResponse(
        400,
        'La richiesta deve essere di tipo multipart/form-data.',
      );
    }

    String? nome;
    String? cognome;
    String? email;
    String? cvOriginalFilename;
    String? cvContentType;
    Uint8List? cvBytes;

    try {
      await for (final part in form.formData) {
        if (part.name == 'nome') {
          nome = (await part.part.readString()).trim();
        } else if (part.name == 'cognome') {
          cognome = (await part.part.readString()).trim();
        } else if (part.name == 'email') {
          email = (await part.part.readString()).trim().toLowerCase();
        } else if (part.name == 'cv') {
          cvOriginalFilename = part.filename;
          cvContentType = part.part.headers['content-type']?.toLowerCase();
          cvBytes = await part.part.readBytes();
        } else {
          await part.part.drain<void>();
        }
      }
    } catch (_) {
      return errorResponse(
        400,
        'Errore durante la lettura del body multipart/form-data.',
      );
    }

    if (nome == null ||
        nome.isEmpty ||
        cognome == null ||
        cognome.isEmpty ||
        email == null ||
        email.isEmpty) {
      return errorResponse(
        400,
        'I campi nome, cognome ed email sono obbligatori.',
      );
    }

    if (!isValidEmail(email)) {
      return errorResponse(400, 'Formato email non valido.');
    }

    if (cvBytes == null || cvBytes.isEmpty) {
      return errorResponse(400, 'Il file CV (campo "cv") è obbligatorio.');
    }

    if (cvBytes.length > maxCvBytes) {
      return errorResponse(
        413,
        'Il file CV supera la dimensione massima consentita (15 MB).',
      );
    }

    if (!_isPdfFile(cvBytes, cvOriginalFilename, cvContentType)) {
      return errorResponse(
        400,
        'Il file caricato deve essere un documento PDF valido.',
      );
    }

    final safeBaseName = _sanitizeFileName(
      p.basenameWithoutExtension(cvOriginalFilename ?? 'cv'),
    );
    final uniqueFileName =
        '${DateTime.now().millisecondsSinceEpoch}_${generateId().substring(0, 8)}_$safeBaseName.pdf';

    final destinationFile = File(
      p.join(db.uploadsDirectory.path, uniqueFileName),
    );
    await destinationFile.writeAsBytes(cvBytes, flush: true);

    final application = JobApplication(
      id: generateId(),
      jobId: job.id,
      nome: nome,
      cognome: cognome,
      email: email,
      cvFileName: uniqueFileName,
      dataInvio: DateTime.now().toUtc().toIso8601String(),
    );

    await db.insertApplication(application);

    final baseUrl = extractBaseUrl(request);
    return jsonResponse(201, application.toResponseJson(baseUrl: baseUrl));
  }

  Future<Response> _getJobApplications(
    Request request,
    Company company,
  ) async {
    // shelf_router salva i parametri dell'URL (es. <jobId>) dentro request.params.
    final jobId = request.params['jobId'];
    if (jobId == null || jobId.isEmpty) {
      return errorResponse(400, 'jobId mancante.');
    }

    final job = db.findJobById(jobId);
    if (job == null) {
      return errorResponse(404, 'Annuncio non trovato.');
    }

    // Solo l'azienda proprietaria dell'annuncio può leggerne le candidature.
    if (job.companyId != company.id) {
      return errorResponse(
        403,
        'Non hai i permessi per visualizzare le candidature di questo annuncio.',
      );
    }

    final baseUrl = extractBaseUrl(request);
    final applications = db
        .getApplicationsByJob(jobId)
        .map((a) => a.toResponseJson(baseUrl: baseUrl))
        .toList();

    return jsonResponse(200, applications);
  }

  bool _isPdfFile(
    Uint8List bytes,
    String? filename,
    String? contentType,
  ) {
    // Verifica i primi 5 byte del file ("%PDF-").
    final hasPdfHeader =
        bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D;

    if (hasPdfHeader) return true;

    final hasPdfExtension =
        filename != null && filename.toLowerCase().endsWith('.pdf');
    final hasPdfMime =
        contentType != null && contentType.contains('application/pdf');

    return hasPdfExtension || hasPdfMime;
  }

  String _sanitizeFileName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (cleaned.isEmpty) return 'cv';
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }
}
