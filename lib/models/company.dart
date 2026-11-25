class Company {
  final String id;
  final String nomeAzienda;
  final String email;
  final String passwordHash;
  final String? token;

  const Company({
    required this.id,
    required this.nomeAzienda,
    required this.email,
    required this.passwordHash,
    this.token,
  });

  /// Restituisce una copia dell'azienda aggiornando solo il token di sessione.
  Company withToken(String? newToken) {
    return Company(
      id: id,
      nomeAzienda: nomeAzienda,
      email: email,
      passwordHash: passwordHash,
      token: newToken,
    );
  }

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as String,
      nomeAzienda: json['nomeAzienda'] as String,
      email: json['email'] as String,
      passwordHash: json['password'] as String,
      token: json['token'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nomeAzienda': nomeAzienda,
      'email': email,
      'password': passwordHash,
      'token': token,
    };
  }

  /// Versione senza password e token da restituire al client.
  Map<String, dynamic> toPublicJson() {
    return {
      'id': id,
      'nomeAzienda': nomeAzienda,
      'email': email,
    };
  }
}
