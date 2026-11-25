import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:jobsearch_mvp_server/server_app.dart';
import 'package:jobsearch_mvp_server/storage/database.dart';

Future<void> main(List<String> args) async {
  const port = 8080;

  // 1. Inizializza la persistenza (cartelle ./data, ./uploads e file db.json)
  final db = await Database.open(dataPath: 'data', uploadsPath: 'uploads');

  // 2. Costruisce l'handler HTTP con middleware (CORS, errori, log) e route API
  final handler = createServerHandler(db);

  // 3. Avvia il server su 0.0.0.0:8080 (raggiungibile da altri dispositivi in LAN)
  final server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    port,
  );
  server.autoCompress = true;

  await _printStartupBanner(server.port, db);
}

Future<void> _printStartupBanner(int port, Database db) async {
  print('============================================================');
  print('  Job Board MVP Server avviato con successo!');
  print('============================================================');
  print('  In ascolto su : 0.0.0.0:$port');
  print('  Localhost     : http://localhost:$port');
  print('  Emulatore AVD : http://10.0.2.2:$port');

  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) {
          print('  IP Rete (${iface.name}): http://${addr.address}:$port');
        }
      }
    }
  } catch (_) {
    print('  IP Rete       : impossibile rilevare gli indirizzi locali');
  }

  print('------------------------------------------------------------');
  print('  Database JSON : ${db.dataDirectory.absolute.path}');
  print('  Cartella CV   : ${db.uploadsDirectory.absolute.path}');
  print('============================================================');
}
