// Medidor de taxa por sinal para o laço (tela d). Dart puro.

class EstatisticaSinal {
  EstatisticaSinal(this.comando);
  final String comando;
  int ok = 0;
  int falhas = 0;
  int suspeitas = 0;
  int _somaLatenciaMs = 0;
  int maxLatenciaMs = 0;

  void registrar({required bool sucesso, required int latenciaMs, bool suspeita = false}) {
    if (sucesso) {
      ok++;
      _somaLatenciaMs += latenciaMs;
      if (latenciaMs > maxLatenciaMs) maxLatenciaMs = latenciaMs;
    } else {
      falhas++;
    }
    if (suspeita) suspeitas++;
  }

  double get latenciaMediaMs => ok == 0 ? 0 : _somaLatenciaMs / ok;

  /// Amostras válidas por segundo no tempo decorrido.
  double amostrasPorSegundo(Duration decorrido) =>
      decorrido.inMilliseconds == 0 ? 0 : ok * 1000 / decorrido.inMilliseconds;

  /// Intervalo médio entre amostras válidas do mesmo sinal, em segundos.
  double? intervaloMedioS(Duration decorrido) => ok == 0 ? null : decorrido.inMilliseconds / 1000 / ok;

  String resumo(Duration decorrido) {
    final iv = intervaloMedioS(decorrido);
    return '$comando: $ok ok, $falhas falha(s), $suspeitas suspeita(s); '
        '${amostrasPorSegundo(decorrido).toStringAsFixed(2)} amostras/s'
        '${iv == null ? '' : ' (1 a cada ${iv.toStringAsFixed(2)} s)'}; '
        'latência média ${latenciaMediaMs.toStringAsFixed(0)} ms, máx $maxLatenciaMs ms';
  }
}
