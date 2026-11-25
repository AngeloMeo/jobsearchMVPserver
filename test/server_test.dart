import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import 'package:jobsearch_mvp_server/server_app.dart';
import 'package:jobsearch_mvp_server/storage/database.dart';

void main() {
  late Directory tempDir;
  late Database db;
  late HttpServer server;
  late String baseUrl;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('jobsearch_mvp_test_');
    db = await Database.open(
      dataPath: p.join(tempDir.path, 'data'),
      uploadsPath: p.join(tempDir.path, 'uploads'),
    );
    server = await shelf_io.serve(
      createServerHandler(db, enableLogging: false),
      InternetAddress.loopbackIPv4,
      0,
    );
    baseUrl = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('CORS headers are present on OPTIONS and normal responses', () async {
    final optionsReq = http.Request('OPTIONS', Uri.parse('$baseUrl/jobs'));
    final streamed = await optionsReq.send();
    expect(streamed.statusCode, 200);
    expect(streamed.headers['access-control-allow-origin'], '*');
    expect(streamed.headers['access-control-allow-methods'], contains('POST'));

    final getRes = await http.get(Uri.parse('$baseUrl/jobs'));
    expect(getRes.statusCode, 200);
    expect(getRes.headers['access-control-allow-origin'], '*');
  });

  test(
    'Full flow: auth, jobs, multipart CV upload, applications, PDF serve, persistence',
    () async {
      // 1. Register company A
      final regA = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nomeAzienda': 'Tech Srl',
          'email': 'hr@techsrl.it',
          'password': 'password123',
        }),
      );
      expect(regA.statusCode, 201);

      // Duplicate email returns 409
      final regDup = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nomeAzienda': 'Tech Duplicate',
          'email': 'HR@techsrl.it',
          'password': 'password123',
        }),
      );
      expect(regDup.statusCode, 409);

      // Register company B
      final regB = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nomeAzienda': 'Other Corp',
          'email': 'jobs@othercorp.it',
          'password': 'password123',
        }),
      );
      expect(regB.statusCode, 201);

      // 2. Login company A & B
      final loginA = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': 'hr@techsrl.it',
          'password': 'password123',
        }),
      );
      expect(loginA.statusCode, 200);
      final loginAData = jsonDecode(loginA.body) as Map<String, dynamic>;
      final tokenA = loginAData['token'] as String;
      expect(loginAData['nomeAzienda'], 'Tech Srl');
      expect(loginAData['companyId'], isNotEmpty);

      final loginB = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': 'jobs@othercorp.it',
          'password': 'password123',
        }),
      );
      final tokenB =
          (jsonDecode(loginB.body) as Map<String, dynamic>)['token'] as String;

      // 3. Unauthorized POST /jobs fails with 401
      final unauthPost = await http.post(
        Uri.parse('$baseUrl/jobs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'titolo': 'Dev', 'descrizione': 'Flutter dev'}),
      );
      expect(unauthPost.statusCode, 401);

      // 4. Company A creates a job
      final createJobA = await http.post(
        Uri.parse('$baseUrl/jobs'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $tokenA',
        },
        body: jsonEncode({
          'titolo': 'Flutter Developer',
          'descrizione': 'Cerchiamo sviluppatore mobile Flutter/Dart.',
        }),
      );
      expect(createJobA.statusCode, 201);
      final jobAData = jsonDecode(createJobA.body) as Map<String, dynamic>;
      final jobIdA = jobAData['id'] as String;

      // Company B creates a job
      final createJobB = await http.post(
        Uri.parse('$baseUrl/jobs'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $tokenB',
        },
        body: jsonEncode({
          'titolo': 'Backend Dart Developer',
          'descrizione': 'Esperienza con Shelf.',
        }),
      );
      expect(createJobB.statusCode, 201);

      // 5. Public GET /jobs returns both jobs
      final allJobsRes = await http.get(Uri.parse('$baseUrl/jobs'));
      expect(allJobsRes.statusCode, 200);
      final allJobs = jsonDecode(allJobsRes.body) as List<dynamic>;
      expect(allJobs.length, 2);

      // 6. Protected GET /company/jobs returns only company A's job
      final companyAJobsRes = await http.get(
        Uri.parse('$baseUrl/company/jobs'),
        headers: {'Authorization': 'Bearer $tokenA'},
      );
      expect(companyAJobsRes.statusCode, 200);
      final companyAJobs = jsonDecode(companyAJobsRes.body) as List<dynamic>;
      expect(companyAJobs.length, 1);
      expect(
        (companyAJobs.first as Map<String, dynamic>)['titolo'],
        'Flutter Developer',
      );

      // 7. Public multipart POST /jobs/<jobId>/apply
      final pdfBytes = utf8.encode('%PDF-1.4\n%Fake PDF content for test\n%%EOF');
      final multipartReq = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/jobs/$jobIdA/apply'),
      )
        ..fields['nome'] = 'Mario'
        ..fields['cognome'] = 'Rossi'
        ..fields['email'] = 'mario.rossi@example.com'
        ..files.add(
          http.MultipartFile.fromBytes(
            'cv',
            pdfBytes,
            filename: 'curriculum_mario.pdf',
            contentType: MediaType('application', 'pdf'),
          ),
        );

      final applyStreamed = await multipartReq.send();
      final applyBody = await applyStreamed.stream.bytesToString();
      expect(applyStreamed.statusCode, 201);
      final applyJson = jsonDecode(applyBody) as Map<String, dynamic>;
      final cvFileName = applyJson['cvFileName'] as String;
      expect(cvFileName, endsWith('.pdf'));

      // 8. Company B cannot view Company A's applications (403)
      final forbiddenApps = await http.get(
        Uri.parse('$baseUrl/jobs/$jobIdA/applications'),
        headers: {'Authorization': 'Bearer $tokenB'},
      );
      expect(forbiddenApps.statusCode, 403);

      // Company A can view applications and receives cvUrl & cvPath
      final appsRes = await http.get(
        Uri.parse('$baseUrl/jobs/$jobIdA/applications'),
        headers: {'Authorization': 'Bearer $tokenA'},
      );
      expect(appsRes.statusCode, 200);
      final appsList = jsonDecode(appsRes.body) as List<dynamic>;
      expect(appsList.length, 1);
      final firstApp = appsList.first as Map<String, dynamic>;
      expect(firstApp['nome'], 'Mario');
      expect(firstApp['cvFileName'], cvFileName);
      expect(firstApp['cvPath'], '/uploads/$cvFileName');
      expect(firstApp['cvUrl'], '$baseUrl/uploads/$cvFileName');

      // 9. GET /uploads/<fileName> serves PDF with application/pdf
      final pdfRes = await http.get(
        Uri.parse('$baseUrl/uploads/$cvFileName'),
      );
      expect(pdfRes.statusCode, 200);
      expect(pdfRes.headers['content-type'], 'application/pdf');
      expect(pdfRes.bodyBytes, pdfBytes);

      // 10. Logout invalidates token
      final logoutRes = await http.post(
        Uri.parse('$baseUrl/auth/logout'),
        headers: {'Authorization': 'Bearer $tokenA'},
      );
      expect(logoutRes.statusCode, 200);

      final afterLogoutRes = await http.get(
        Uri.parse('$baseUrl/company/jobs'),
        headers: {'Authorization': 'Bearer $tokenA'},
      );
      expect(afterLogoutRes.statusCode, 401);

      // 11. Restart persistence check: reopening Database loads all persisted data
      final reopenedDb = await Database.open(
        dataPath: p.join(tempDir.path, 'data'),
        uploadsPath: p.join(tempDir.path, 'uploads'),
      );
      expect(reopenedDb.getAllJobs().length, 2);
      expect(reopenedDb.getApplicationsByJob(jobIdA).length, 1);
      expect(reopenedDb.findCompanyByEmail('hr@techsrl.it'), isNotNull);
    },
  );
}
