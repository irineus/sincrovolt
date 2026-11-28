// Máscara de VIN para o log exportado (CLAUDE.md, regra 3: só os 3 primeiros caracteres
// visíveis, o resto `*`). Dart puro.
//
// O VIN aparece de dois jeitos: em texto (decodificado) e em HEX na resposta bruta do
// 0902 (ou de um DID como o F190). As duas formas são mascaradas. Na dúvida, mascara:
// um trecho de 17 bytes que pareça VIN dentro de qualquer resposta também vira `**`.

import 'resposta_elm.dart';

/// Caracteres de VIN (sem I, O e Q).
final RegExp _vinTexto = RegExp(r'(?<![A-Za-z0-9])[A-HJ-NPR-Z0-9]{17}(?![A-Za-z0-9])');

bool _ehCaractereVin(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A && c != 0x49 && c != 0x4F && c != 0x51);

bool _temDigitoELetra(Iterable<int> cs) =>
    cs.any((c) => c >= 0x30 && c <= 0x39) && cs.any((c) => c >= 0x41);

/// `LGW` + 14 caracteres → `LGW**************`.
String mascararVin(String vin) =>
    vin.length <= 3 ? vin : vin.substring(0, 3) + '*' * (vin.length - 3);

/// Mascara todo VIN de 17 caracteres (com dígito e letra) em texto livre.
String mascararVinEmTexto(String texto) => texto.replaceAllMapped(_vinTexto, (m) {
      final v = m.group(0)!;
      return _temDigitoELetra(v.codeUnits) ? mascararVin(v) : v;
    });

class _Ref {
  _Ref(this.linha, this.token);
  final int linha;
  final int token;
}

/// Mascara, na resposta bruta, os bytes 4..17 de todo trecho de 17 bytes que pareça VIN
/// (mesma regra da varredura de segredos). Mantém cabeçalhos, PCI e o formato da linha.
String mascararVinEmHex(String bruta) {
  final linhas = bruta.split(RegExp(r'(?<=[\r\n])'));
  final tokens = <List<String>>[];
  final compacta = <bool>[];
  // payload por mensagem: lista de referências (linha, token) de cada byte de dado
  final payloads = <String, List<_Ref>>{};
  var semCabecalho = 0;

  for (var i = 0; i < linhas.length; i++) {
    final conteudo = linhas[i].replaceAll(RegExp(r'[\r\n]'), '');
    final t = conteudo.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    final ehCompacta = t.length == 1 && t.first.length > 3;
    if (ehCompacta) {
      // "7E803415BF2" → ["7E8", "06", "41", ...] para mascarar; remonta sem espaço
      final s = t.first;
      final cab = s.length.isOdd ? [s.substring(0, 3)] : <String>[];
      final resto = s.length.isOdd ? s.substring(3) : s;
      t
        ..clear()
        ..addAll(cab)
        ..addAll([for (var k = 0; k + 1 < resto.length; k += 2) resto.substring(k, k + 2)]);
    }
    tokens.add(t);
    compacta.add(ehCompacta);

    final q = quebrarLinha(conteudo.trim().toUpperCase());
    if (q == null) continue;
    final (ecu, bytes, ehIndice) = q;
    final primeiroByte = t.length - bytes.length; // índice do 1º token de byte
    if (ecu.isEmpty) {
      final chave = ehIndice && !conteudo.trim().startsWith('0:') ? '?$semCabecalho' : '?${++semCabecalho}';
      final lista = payloads.putIfAbsent(chave, () => []);
      for (var k = 0; k < bytes.length; k++) {
        lista.add(_Ref(i, primeiroByte + k));
      }
      continue;
    }
    if (bytes.isEmpty) continue;
    final tipo = bytes[0] >> 4;
    final pulo = tipo == 1 ? 2 : 1; // PCI (e tamanho, no primeiro quadro)
    if (tipo == 0 || tipo == 1) payloads[ecu] = [];
    final lista = payloads[ecu];
    if (lista == null || tipo > 2) continue;
    for (var k = pulo; k < bytes.length; k++) {
      lista.add(_Ref(i, primeiroByte + k));
    }
  }

  for (final refs in payloads.values) {
    final valores = [for (final r in refs) int.tryParse(tokens[r.linha][r.token], radix: 16) ?? -1];
    var k = 0;
    while (k + 17 <= valores.length) {
      final janela = valores.sublist(k, k + 17);
      if (janela.every(_ehCaractereVin) && _temDigitoELetra(janela)) {
        for (var j = k + 3; j < k + 17; j++) {
          tokens[refs[j].linha][refs[j].token] = '**';
        }
        k += 17;
      } else {
        k++;
      }
    }
  }

  final saida = StringBuffer();
  for (var i = 0; i < linhas.length; i++) {
    final fim = RegExp(r'[\r\n]+$').firstMatch(linhas[i])?.group(0) ?? '';
    final original = linhas[i].replaceAll(RegExp(r'[\r\n]'), '');
    if (tokens[i].isEmpty) {
      saida.write(original);
    } else {
      final recuo = RegExp(r'^\s*').firstMatch(original)!.group(0)!;
      saida.write(recuo + tokens[i].join(compacta[i] ? '' : ' '));
    }
    saida.write(fim);
  }
  return saida.toString();
}

/// Máscara completa de uma linha de log: hex e texto.
String mascararTudo(String s) => mascararVinEmTexto(mascararVinEmHex(s));
