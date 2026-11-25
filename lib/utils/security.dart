import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final Random _secureRandom = Random.secure();

/// Genera un ID univoco (UUID v4) usando un generatore crittograficamente sicuro.
String generateId() {
  final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String toHex(int value) => value.toRadixString(16).padLeft(2, '0');
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    if (i == 4 || i == 6 || i == 8 || i == 10) {
      buffer.write('-');
    }
    buffer.write(toHex(bytes[i]));
  }
  return buffer.toString();
}

/// Genera un token di sessione casuale (32 byte in Base64 URL-safe).
String generateToken() {
  final bytes = List<int>.generate(32, (_) => _secureRandom.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// Calcola l'hash SHA-256 della password abbinato a un salt casuale ("salt$hash").
String hashPassword(String password) {
  final saltBytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
  final salt = base64UrlEncode(saltBytes);
  final digest = sha256.convert(utf8.encode('$salt:$password')).toString();
  return '$salt\$$digest';
}

/// Verifica una password in chiaro confrontandola con il formato "salt$hash".
bool verifyPassword(String password, String storedHash) {
  final parts = storedHash.split('\$');
  if (parts.length != 2) return false;

  final salt = parts[0];
  final expectedHash = parts[1];
  final actualHash = sha256.convert(utf8.encode('$salt:$password')).toString();

  // Confronto a tempo costante per evitare timing attack.
  if (actualHash.length != expectedHash.length) return false;
  var diff = 0;
  for (var i = 0; i < actualHash.length; i++) {
    diff |= actualHash.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
  }
  return diff == 0;
}
