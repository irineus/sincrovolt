// Log do spike: hora de cada pedido e resposta, e a exportação com VIN mascarado.
// Dart puro.

import 'mascara_vin.dart';

enum Sentido { pedido, resposta, recusa, decodificado, nota }

class Entrada {
  Entrada(this.hora, this.sentido, this.texto, {this.latenciaMs});
  final DateTime hora;
  final Sentido sentido;
  final String texto;

  /// Para respostas: tempo desde o pedido.
  final int? latenciaMs;
}

String _dois(int n) => n.toString().padLeft(2, '0');

/// `13:05:09.042`
String horaComMs(DateTime t) =>
    '${_dois(t.hour)}:${_dois(t.minute)}:${_dois(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';

const Map<Sentido, String> _seta = {
  Sentido.pedido: '→',
  Sentido.resposta: '←',
  Sentido.recusa: '✖',
  Sentido.decodificado: '=',
  Sentido.nota: '#',
};

/// Uma linha do log. Respostas multilinha ficam numa linha só, com ` | `.
String formatarEntrada(Entrada e) {
  final texto = e.texto.replaceAll(RegExp(r'[\r\n]+'), ' | ').trim();
  final lat = e.latenciaMs == null ? '' : ' (${e.latenciaMs} ms)';
  return '${horaComMs(e.hora)} ${_seta[e.sentido]} $texto$lat';
}

class Registro {
  final List<Entrada> entradas = [];

  void adicionar(Entrada e) => entradas.add(e);

  void limpar() => entradas.clear();

  /// Texto para "Copiar log": cabeçalho + entradas, SEMPRE com o VIN mascarado.
  /// A máscara roda na resposta crua (hex) antes de juntar as linhas.
  String exportar({required String cabecalho}) {
    final b = StringBuffer()
      ..writeln('# spike OBD SincroVolt (EVAPP-11) — VIN mascarado, sem GPS')
      ..writeln('# ${mascararVinEmTexto(cabecalho)}');
    for (final e in entradas) {
      final mascarada = Entrada(e.hora, e.sentido, mascararTudo(e.texto), latenciaMs: e.latenciaMs);
      b.writeln(mascararVinEmTexto(formatarEntrada(mascarada)));
    }
    return b.toString();
  }
}
