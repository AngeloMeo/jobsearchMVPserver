class Job {
  final String id;
  final String companyId;
  final String nomeAzienda;
  final String titolo;
  final String descrizione;
  final String dataPubblicazione;

  const Job({
    required this.id,
    required this.companyId,
    required this.nomeAzienda,
    required this.titolo,
    required this.descrizione,
    required this.dataPubblicazione,
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['id'] as String,
      companyId: json['companyId'] as String,
      nomeAzienda: json['nomeAzienda'] as String,
      titolo: json['titolo'] as String,
      descrizione: json['descrizione'] as String,
      dataPubblicazione: json['dataPubblicazione'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'companyId': companyId,
      'nomeAzienda': nomeAzienda,
      'titolo': titolo,
      'descrizione': descrizione,
      'dataPubblicazione': dataPubblicazione,
    };
  }
}
