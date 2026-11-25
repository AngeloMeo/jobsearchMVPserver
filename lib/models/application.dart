class JobApplication {
  final String id;
  final String jobId;
  final String nome;
  final String cognome;
  final String email;
  final String cvFileName;
  final String dataInvio;

  const JobApplication({
    required this.id,
    required this.jobId,
    required this.nome,
    required this.cognome,
    required this.email,
    required this.cvFileName,
    required this.dataInvio,
  });

  factory JobApplication.fromJson(Map<String, dynamic> json) {
    return JobApplication(
      id: json['id'] as String,
      jobId: json['jobId'] as String,
      nome: json['nome'] as String,
      cognome: json['cognome'] as String,
      email: json['email'] as String,
      cvFileName: json['cvFileName'] as String,
      dataInvio: json['dataInvio'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'jobId': jobId,
      'nome': nome,
      'cognome': cognome,
      'email': email,
      'cvFileName': cvFileName,
      'dataInvio': dataInvio,
    };
  }

  Map<String, dynamic> toResponseJson({required String baseUrl}) {
    final cvPath = '/uploads/$cvFileName';
    return {
      ...toJson(),
      'cvPath': cvPath,
      'cvUrl': '$baseUrl$cvPath',
    };
  }
}
