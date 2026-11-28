// Regras da varredura de DIDs (modo 22). Dart puro: a tela só executa o que estas
// funções decidem.
//
//   7F 22 31             → DID inexistente: segue
//   7F 22 33 / 7E / 7F   → exige acesso de segurança ou outra sessão: PARA ("pare e pergunte")
//   7F 22 11             → o módulo não aceita modo 22: pula o cabeçalho
//   62 DD DD …           → achado
//   NO DATA / sem nada   → sem resposta (N seguidas = cabeçalho mudo: pula)

import 'resposta_elm.dart';

enum Desfecho {
  achado,
  inexistente,
  pareEPergunte,
  moduloSemModo22,
  semResposta,
  outraNegativa,
}

class ResultadoDid {
  ResultadoDid(this.did, this.desfecho, this.ecu, this.detalhe, [this.dados = const []]);
  final int did;
  final Desfecho desfecho;
  final String ecu;
  final String detalhe;

  /// Bytes de dado (depois de `62 DD DD`) quando [Desfecho.achado].
  final List<int> dados;
}

/// NRC que mandam parar a varredura e perguntar ao usuário.
const Set<int> nrcPareEPergunte = {0x33, 0x7E, 0x7F};

/// Classifica a resposta ao pedido `22 <did>`.
ResultadoDid classificarDid(int did, RespostaElm r) {
  final alto = did >> 8;
  final baixo = did & 0xFF;
  ResultadoDid? negativa;
  for (final m in r.mensagens) {
    final b = m.bytes;
    if (b.length >= 3 && b[0] == 0x62 && b[1] == alto && b[2] == baixo) {
      return ResultadoDid(did, Desfecho.achado, m.ecu, m.hex, b.sublist(3));
    }
    if (m.negativa && b.length >= 3 && b[1] == 0x22) {
      final nrc = b[2];
      if (nrcPareEPergunte.contains(nrc)) {
        // a mais grave vence: devolve já
        return ResultadoDid(did, Desfecho.pareEPergunte, m.ecu, m.hex);
      }
      if (nrc == 0x78) continue; // pendente: a resposta final vem na mesma leitura
      final d = switch (nrc) {
        0x31 => Desfecho.inexistente,
        0x11 => Desfecho.moduloSemModo22,
        _ => Desfecho.outraNegativa,
      };
      negativa ??= ResultadoDid(did, d, m.ecu, m.hex);
    }
  }
  return negativa ?? ResultadoDid(did, Desfecho.semResposta, '', r.erro ?? r.linhas.join(' '));
}

/// Interpreta "7E0" ou "7A0-7AF" em lista de cabeçalhos 11 bits (só 7xx).
List<int>? faixaDeCabecalhos(String texto) => _faixa(texto, 3, 0x700, 0x7FF, 256);

/// Interpreta "F190" ou "0100-01FF" em lista de DIDs (máximo [maximo] por rodada).
List<int>? faixaDeDids(String texto, {int maximo = 4096}) => _faixa(texto, 4, 0, 0xFFFF, maximo);

List<int>? _faixa(String texto, int digitos, int min, int max, int maximo) {
  final t = texto.toUpperCase().replaceAll(' ', '');
  final re = RegExp('^([0-9A-F]{$digitos})(?:-([0-9A-F]{$digitos}))?\$');
  final m = re.firstMatch(t);
  if (m == null) return null;
  final a = int.parse(m.group(1)!, radix: 16);
  final b = m.group(2) == null ? a : int.parse(m.group(2)!, radix: 16);
  if (a > b || a < min || b > max || b - a + 1 > maximo) return null;
  return [for (var x = a; x <= b; x++) x];
}
