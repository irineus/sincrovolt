// Parser da resposta textual do ELM327: limpa o texto, detecta mensagens de erro do
// adaptador e remonta as mensagens ISO-TP (quadro único, primeiro quadro + consecutivos)
// por cabeçalho CAN. Dart puro.
//
// Formatos aceitos (todos vistos no KONNWEI v1.5 ou documentados no datasheet do ELM327):
//   ATH1, com espaços:  `7E8 03 41 5B F2`
//   ATH1, ATS0:         `7E803415BF2`
//   ATH0, quadro único: `41 5B F2`
//   ATH0, multiquadro:  `014` / `0: 49 02 01 4C 47 57` / `1: …`

/// Mensagens do ELM327 que significam "não veio dado".
const List<String> errosDoAdaptador = [
  'NO DATA',
  'CAN ERROR',
  'UNABLE TO CONNECT',
  'BUS INIT',
  'BUS BUSY',
  'BUS ERROR',
  'DATA ERROR',
  'BUFFER FULL',
  'FB ERROR',
  'RX ERROR',
  'STOPPED',
  'ACT ALERT',
  'LV RESET',
  'ERR',
  '?',
];

/// Uma mensagem remontada de um módulo.
class Mensagem {
  Mensagem(this.ecu, this.bytes);

  /// Cabeçalho de resposta (ex.: `7E8`), ou `?1`, `?2`… quando o ATH1 está desligado.
  final String ecu;
  final List<int> bytes;

  bool get negativa => bytes.isNotEmpty && bytes[0] == 0x7F;

  /// Código NRC (UDS) da resposta negativa `7F <serviço> <nrc>`.
  int? get nrc => negativa && bytes.length >= 3 ? bytes[2] : null;

  String get hex => bytes.map(hex2).join(' ');

  @override
  String toString() => '$ecu: $hex';
}

String hex2(int b) => b.toRadixString(16).toUpperCase().padLeft(2, '0');

/// Resposta já interpretada.
class RespostaElm {
  RespostaElm({
    required this.bruta,
    required this.linhas,
    required this.mensagens,
    this.erro,
  });

  /// Texto exatamente como chegou (sem o `>` final).
  final String bruta;

  /// Linhas úteis (sem eco, sem `SEARCHING...`, sem vazias).
  final List<String> linhas;

  /// Mensagens ISO-TP remontadas, na ordem em que começaram.
  final List<Mensagem> mensagens;

  /// Primeira mensagem de erro do adaptador, se houver (ex.: `NO DATA`).
  final String? erro;

  bool get vazia => mensagens.isEmpty;
}

final RegExp _hexPuro = RegExp(r'^[0-9A-F]+$');
final RegExp _indiceMultiquadro = RegExp(r'^([0-9A-F]):$');

/// Interpreta o texto recebido do adaptador para o comando [comando] (normalizado).
RespostaElm interpretar(String bruta, {String comando = ''}) {
  final semPrompt = bruta.replaceAll('>', '').replaceAll('\x00', '');
  final linhas = <String>[];
  for (final l in semPrompt.split(RegExp(r'[\r\n]+'))) {
    final t = l.trim().toUpperCase();
    if (t.isEmpty) continue;
    if (t.startsWith('SEARCHING')) continue;
    if (comando.isNotEmpty && t.replaceAll(' ', '') == comando) continue; // eco
    linhas.add(t);
  }

  String? erro;
  for (final l in linhas) {
    for (final e in errosDoAdaptador) {
      if (l == e || (e.length > 1 && l.contains(e))) {
        erro ??= l;
      }
    }
  }

  final mensagens = <Mensagem>[];
  if (!comando.startsWith('AT')) {
    _remontar(linhas, mensagens);
  }
  return RespostaElm(bruta: semPrompt, linhas: linhas, mensagens: mensagens, erro: erro);
}

/// Separa uma linha em (cabeçalho, bytes) ou `null` se não for linha de dados.
/// Devolve cabeçalho vazio quando não há (ATH0).
(String, List<int>, bool)? quebrarLinha(String linha) {
  final tokens = linha.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return null;

  // ATH0 multiquadro: "0: 49 02 01 ..."
  final idx = _indiceMultiquadro.firstMatch(tokens.first);
  if (idx != null) {
    final bytes = _bytes(tokens.skip(1));
    return bytes == null ? null : ('', bytes, true);
  }

  if (tokens.length == 1) {
    final t = tokens.first;
    if (!_hexPuro.hasMatch(t)) return null;
    if (t.length == 3) return null; // marcador de tamanho do ATH0 multiquadro ("014")
    if (t.length.isOdd) {
      // ATH1 + ATS0: 3 dígitos de cabeçalho e pares
      final bytes = _pares(t.substring(3));
      return bytes == null ? null : (t.substring(0, 3), bytes, false);
    }
    final bytes = _pares(t);
    return bytes == null ? null : ('', bytes, false);
  }

  if (tokens.first.length == 3 && _hexPuro.hasMatch(tokens.first)) {
    final bytes = _bytes(tokens.skip(1));
    return bytes == null ? null : (tokens.first, bytes, false);
  }
  final bytes = _bytes(tokens);
  return bytes == null ? null : ('', bytes, false);
}

List<int>? _bytes(Iterable<String> tokens) {
  final r = <int>[];
  for (final t in tokens) {
    if (t.length != 2 || !_hexPuro.hasMatch(t)) return null;
    r.add(int.parse(t, radix: 16));
  }
  return r;
}

List<int>? _pares(String s) {
  if (s.length.isOdd) return null;
  final r = <int>[];
  for (var i = 0; i < s.length; i += 2) {
    r.add(int.parse(s.substring(i, i + 2), radix: 16));
  }
  return r;
}

class _EmAndamento {
  _EmAndamento(this.msg, this.esperado);
  final Mensagem msg;
  final int esperado;
}

void _remontar(List<String> linhas, List<Mensagem> saida) {
  final abertas = <String, _EmAndamento>{};
  var semCabecalho = 0;
  Mensagem? multiquadroSemCabecalho;

  for (final l in linhas) {
    final q = quebrarLinha(l);
    if (q == null) continue;
    final (ecu, bytes, ehIndiceAth0) = q;

    if (ecu.isEmpty) {
      // ATH0: o adaptador já tirou o PCI.
      if (ehIndiceAth0) {
        if (l.startsWith('0:') || multiquadroSemCabecalho == null) {
          multiquadroSemCabecalho = Mensagem('?${++semCabecalho}', []);
          saida.add(multiquadroSemCabecalho);
        }
        multiquadroSemCabecalho.bytes.addAll(bytes);
      } else {
        saida.add(Mensagem('?${++semCabecalho}', bytes));
      }
      continue;
    }

    if (bytes.isEmpty) continue;
    final pci = bytes[0];
    switch (pci >> 4) {
      case 0: // quadro único
        final n = pci & 0x0F;
        saida.add(Mensagem(ecu, bytes.sublist(1, (1 + n).clamp(1, bytes.length))));
        abertas.remove(ecu);
      case 1: // primeiro quadro
        if (bytes.length < 2) continue;
        final n = ((pci & 0x0F) << 8) | bytes[1];
        final m = Mensagem(ecu, bytes.sublist(2));
        saida.add(m);
        abertas[ecu] = _EmAndamento(m, n);
        _fechar(abertas, ecu);
      case 2: // consecutivo
        final a = abertas[ecu];
        if (a == null) continue;
        a.msg.bytes.addAll(bytes.sublist(1));
        _fechar(abertas, ecu);
      default: // 3 = controle de fluxo; ignorado
        continue;
    }
  }
  // Multiquadro incompleto continua na saída (com o que chegou): melhor ver o pedaço
  // do que esconder a falha.
}

void _fechar(Map<String, _EmAndamento> abertas, String ecu) {
  final a = abertas[ecu]!;
  if (a.msg.bytes.length >= a.esperado) {
    a.msg.bytes.removeRange(a.esperado, a.msg.bytes.length);
    abertas.remove(ecu);
  }
}
