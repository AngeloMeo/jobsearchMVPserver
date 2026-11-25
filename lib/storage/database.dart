import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/application.dart';
import '../models/company.dart';
import '../models/job.dart';

/// Gestisce la persistenza su file JSON (`data/db.json`) e la cartella `uploads/`.
/// Mantiene i dati in memoria per letture veloci e li salva su disco ad ogni modifica.
class Database {
  final Directory dataDirectory;
  final Directory uploadsDirectory;
  final File _dbFile;

  final List<Company> _companies = [];
  final List<Job> _jobs = [];
  final List<JobApplication> _applications = [];

  // Coda per serializzare le scritture su file ed evitare corruzioni concorrenti.
  Future<void> _writeQueue = Future.value();

  Database._({
    required this.dataDirectory,
    required this.uploadsDirectory,
    required File dbFile,
  }) : _dbFile = dbFile;

  /// Crea le cartelle necessarie e carica i dati salvati da disco.
  static Future<Database> open({
    String dataPath = 'data',
    String uploadsPath = 'uploads',
  }) async {
    final dataDir = Directory(dataPath);
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }

    final uploadsDir = Directory(uploadsPath);
    if (!await uploadsDir.exists()) {
      await uploadsDir.create(recursive: true);
    }

    final dbFile = File(p.join(dataDir.path, 'db.json'));
    final db = Database._(
      dataDirectory: dataDir,
      uploadsDirectory: uploadsDir,
      dbFile: dbFile,
    );

    await db._load();
    return db;
  }

  Future<void> _load() async {
    if (!await _dbFile.exists()) {
      await _persistNow();
      return;
    }

    final content = await _dbFile.readAsString();
    if (content.trim().isEmpty) {
      await _persistNow();
      return;
    }

    final json = jsonDecode(content) as Map<String, dynamic>;
    final companiesJson = (json['companies'] as List<dynamic>?) ?? [];
    final jobsJson = (json['jobs'] as List<dynamic>?) ?? [];
    final appsJson = (json['applications'] as List<dynamic>?) ?? [];

    _companies.clear();
    _companies.addAll(
      companiesJson.map((e) => Company.fromJson(e as Map<String, dynamic>)),
    );

    _jobs.clear();
    _jobs.addAll(
      jobsJson.map((e) => Job.fromJson(e as Map<String, dynamic>)),
    );

    _applications.clear();
    _applications.addAll(
      appsJson.map((e) => JobApplication.fromJson(e as Map<String, dynamic>)),
    );
  }

  Future<void> _save() {
    _writeQueue = _writeQueue.then((_) => _persistNow());
    return _writeQueue;
  }

  Future<void> _persistNow() async {
    final payload = {
      'companies': _companies.map((c) => c.toJson()).toList(),
      'jobs': _jobs.map((j) => j.toJson()).toList(),
      'applications': _applications.map((a) => a.toJson()).toList(),
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);

    // Scrittura su file temporaneo + rename per evitare file troncati in caso di crash.
    final tempFile = File('${_dbFile.path}.tmp');
    await tempFile.writeAsString(encoded, flush: true);
    if (await _dbFile.exists()) {
      await _dbFile.delete();
    }
    await tempFile.rename(_dbFile.path);
  }

  // --- Aziende ---

  Company? findCompanyByEmail(String email) {
    final normalized = email.trim().toLowerCase();
    for (final company in _companies) {
      if (company.email.toLowerCase() == normalized) {
        return company;
      }
    }
    return null;
  }

  Company? findCompanyByToken(String token) {
    for (final company in _companies) {
      if (company.token != null && company.token == token) {
        return company;
      }
    }
    return null;
  }

  Future<void> insertCompany(Company company) async {
    _companies.add(company);
    await _save();
  }

  Future<void> updateCompanyToken(String companyId, String? token) async {
    final index = _companies.indexWhere((c) => c.id == companyId);
    if (index == -1) return;
    _companies[index] = _companies[index].withToken(token);
    await _save();
  }

  // --- Annunci di lavoro ---

  List<Job> getAllJobs() {
    final copy = List<Job>.from(_jobs);
    copy.sort((a, b) => b.dataPubblicazione.compareTo(a.dataPubblicazione));
    return copy;
  }

  List<Job> getJobsByCompany(String companyId) {
    final filtered = _jobs.where((j) => j.companyId == companyId).toList();
    filtered.sort((a, b) => b.dataPubblicazione.compareTo(a.dataPubblicazione));
    return filtered;
  }

  Job? findJobById(String jobId) {
    for (final job in _jobs) {
      if (job.id == jobId) {
        return job;
      }
    }
    return null;
  }

  Future<void> insertJob(Job job) async {
    _jobs.add(job);
    await _save();
  }

  // --- Candidature ---

  List<JobApplication> getApplicationsByJob(String jobId) {
    final filtered = _applications.where((a) => a.jobId == jobId).toList();
    filtered.sort((a, b) => b.dataInvio.compareTo(a.dataInvio));
    return filtered;
  }

  Future<void> insertApplication(JobApplication application) async {
    _applications.add(application);
    await _save();
  }
}
