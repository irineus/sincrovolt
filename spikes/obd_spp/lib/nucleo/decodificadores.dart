// Decodificação dos pedidos do spike. Dart puro.
//
// Fórmulas (Decisões vigentes, EVAPP-6/7/10):
//   0902  VIN em ASCII, multiquadro: 49 02 01 + 17 bytes
//   01A6  hodômetro: A·2^24 + B·2^16 + C·2^8 + D, em passos de 0,1 km
//   015B  SoC (escala do BMS): A × 100 / 255
//   019A  tensão (B·256 + C) / 64 V; corrente (D·256 + E) com sinal × 0,1 A,
//         positiva = descarga
//
// Unidade de domínio (energia/distância) só se decide no EVAPP-22: aqui os valores
// ficam no INTEIRO do protocolo (passos de 0,1 km, 1/64 V, 0,1 A) e só viram texto
// na exibição.

import 'mascara_vin.dart';
import 'resposta_elm.dart';

/// Uma leitura decodificada de um módulo.
class Leitura {
  Leitura(this.ecu, this.sinal, this.texto, {this.valores = const {}, this.suspeita});

  final String ecu;
  final String sinal;
  final String texto;

  /// Valores numéricos por sinal, na unidade de exibição (para o filtro de
  /// plausibilidade). O 019A traz dois: tensão HV e corrente.
  final Map<String, double> valores;

  /// Motivo da suspeita do filtro de plausibilidade, ou `null` se plausível.
  String? suspeita;

  @override
  String toString() => '$ecu $sinal = $texto${suspeita == null ? '' : ' ⚠ $suspeita'}';
}

/// Decodifica a resposta de [comando] (normalizado). Respostas negativas e erros do
/// adaptador viram uma [Leitura] com o texto do problema.
List<Leitura> decodificar(String comando, RespostaElm r) {
  if (comando.startsWith('AT')) {
    final v = _tensaoAtrv(comando, r);
    return [Leitura('ELM', comando, r.linhas.join(' | '), valores: v == null ? const {} : {'bateria 12 V': v})];
  }
  if (r.erro != null && r.vazia) {
    return [Leitura('ELM', comando, r.erro!)];
  }
  final saida = <Leitura>[];
  final sid = int.parse(comando.substring(0, 2), radix: 16);
  for (final m in r.mensagens) {
    if (m.negativa) {
      saida.add(Leitura(m.ecu, comando, 'negativa ${m.hex} (${nomeNrc(m.nrc)})'));
      continue;
    }
    if (m.bytes.isEmpty || m.bytes[0] != sid + 0x40) {
      saida.add(Leitura(m.ecu, comando, 'inesperada: ${m.hex}'));
      continue;
    }
    saida.add(_decodificarPositiva(comando, m));
  }
  return saida;
}

double? _tensaoAtrv(String comando, RespostaElm r) {
  if (comando != 'ATRV' || r.linhas.isEmpty) return null;
  final m = RegExp(r'(\d+(?:\.\d+)?)V').firstMatch(r.linhas.last);
  return m == null ? null : double.parse(m.group(1)!);
}

Leitura _decodificarPositiva(String comando, Mensagem m) {
  final b = m.bytes;
  final pid = comando.substring(2);
  if (comando.startsWith('01')) {
    final dados = b.length >= 2 ? b.sublist(2) : <int>[];
    switch (pid) {
      case '00' || '20' || '40' || '60' || '80' || 'A0' || 'C0':
        return Leitura(m.ecu, comando, 'suportados: ${pidsSuportados(pid, dados).join(' ')}');
      case 'A6':
        final h = hodometroDecimos(dados);
        return h == null
            ? Leitura(m.ecu, 'hodômetro', 'curta: ${m.hex}')
            : Leitura(m.ecu, 'hodômetro', '${formatarDecimos(h)} km', valores: {'hodômetro': h / 10});
      case '5B':
        if (dados.isEmpty) return Leitura(m.ecu, 'SoC', 'curta: ${m.hex}');
        final soc = socPercent(dados[0]);
        return Leitura(m.ecu, 'SoC',
            '${soc.toStringAsFixed(2)} % (A=${dados[0]}; ÷0,95 = ${(soc / 0.95).toStringAsFixed(2)} %)',
            valores: {'SoC': soc});
      case '9A':
        final vi = tensaoCorrente(dados);
        if (vi == null) return Leitura(m.ecu, 'V/I', 'curta: ${m.hex}');
        final (v, i) = vi;
        return Leitura(m.ecu, 'V/I',
            '${(v / 64).toStringAsFixed(2)} V; ${formatarDecimos(i)} A ${i > 0 ? '(descarga)' : i < 0 ? '(carga)' : ''}',
            valores: {'tensão HV': v / 64, 'V/I': i / 10});
      case '0C':
        if (dados.length < 2) return Leitura(m.ecu, 'rpm', 'curta: ${m.hex}');
        final rpm = (dados[0] * 256 + dados[1]) / 4;
        return Leitura(m.ecu, 'rpm', rpm.toStringAsFixed(0), valores: {'rpm': rpm});
      case '2F':
        if (dados.isEmpty) return Leitura(m.ecu, 'combustível', 'curta: ${m.hex}');
        final p = dados[0] * 100 / 255;
        return Leitura(m.ecu, 'combustível', '${p.toStringAsFixed(1)} %', valores: {'combustível': p});
    }
    return Leitura(m.ecu, comando, m.hex);
  }
  if (comando == '0902') {
    final vin = vinDe(b);
    return vin == null
        ? Leitura(m.ecu, 'VIN', 'ilegível: ${m.hex}')
        : Leitura(m.ecu, 'VIN', vin);
  }
  if (comando.startsWith('22')) {
    if (b.length < 3) return Leitura(m.ecu, 'DID $pid', 'curta: ${m.hex}');
    return Leitura(m.ecu, 'DID $pid', candidatasDid(b.sublist(3)));
  }
  return Leitura(m.ecu, comando, m.hex);
}

/// PIDs suportados a partir do bitmask de 4 bytes da resposta 01 00/20/40…
List<String> pidsSuportados(String base, List<int> mascara) {
  final inicio = int.parse(base, radix: 16);
  final r = <String>[];
  for (var i = 0; i < mascara.length && i < 4; i++) {
    for (var bit = 0; bit < 8; bit++) {
      if (mascara[i] & (0x80 >> bit) != 0) {
        r.add(hex2(inicio + i * 8 + bit + 1));
      }
    }
  }
  return r;
}

/// VIN: pula `49 02` e o contador `01`, fica com os caracteres imprimíveis.
String? vinDe(List<int> payload) {
  if (payload.length < 3 || payload[0] != 0x49 || payload[1] != 0x02) return null;
  final dados = payload.sublist(payload[2] == 0x01 ? 3 : 2);
  final s = String.fromCharCodes(dados.where((c) => c >= 0x30 && c <= 0x5A));
  return s.length == 17 ? s : null;
}

/// Hodômetro em passos de 0,1 km (inteiro do protocolo).
int? hodometroDecimos(List<int> d) {
  if (d.length < 4) return null;
  return (d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3];
}

/// SoC do 015B em % (escala do BMS).
double socPercent(int a) => a * 100 / 255;

/// (tensão em 1/64 V, corrente em 0,1 A com sinal; positiva = descarga).
/// Aceita o byte de disponibilidade na frente (5 ou mais bytes).
(int, int)? tensaoCorrente(List<int> d) {
  if (d.length < 5) return null;
  final v = d[1] * 256 + d[2];
  var i = d[3] * 256 + d[4];
  if (i >= 0x8000) i -= 0x10000;
  return (v, i);
}

/// Formata um inteiro em décimos: 381953 → "38195,3"; -100 → "-10,0".
String formatarDecimos(int decimos) {
  final neg = decimos < 0;
  final a = decimos.abs();
  return '${neg ? '-' : ''}${a ~/ 10},${a % 10}';
}

/// Leituras candidatas de um DID desconhecido, para comparar com o Car Scanner.
String candidatasDid(List<int> d) {
  if (d.isEmpty) return '(sem dados)';
  final ascii = d.every((c) => c >= 0x20 && c <= 0x7E) ? String.fromCharCodes(d).trim() : null;
  if (ascii != null && ascii.length >= 17) {
    final mascarado = mascararVinEmTexto(ascii);
    if (mascarado != ascii) {
      // parece VIN (ex.: DID F190): nem bytes nem u8, só o texto mascarado
      return 'ASCII (parece VIN, mascarado): $mascarado';
    }
  }
  final partes = <String>[
    'bytes: ${d.map(hex2).join(' ')}',
    'u8: ${d.join(' ')}',
    if (ascii != null && ascii.isNotEmpty) 'ASCII: "$ascii"',
  ];
  if (d.length >= 2) {
    final u16 = d[0] * 256 + d[1];
    final s16 = u16 >= 0x8000 ? u16 - 0x10000 : u16;
    partes.add('u16: $u16 (÷10 ${(u16 / 10).toStringAsFixed(1)}; ÷100 ${(u16 / 100).toStringAsFixed(2)}; '
        's16 $s16; −300 ${u16 / 10 - 300} se ÷10)');
  }
  if (d.length == 1) partes.add('−40: ${d[0] - 40}; ÷2: ${d[0] / 2}; ×100/255: ${(d[0] * 100 / 255).toStringAsFixed(1)}');
  if (d.length >= 4) {
    final u32 = (d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3];
    partes.add('u32: $u32');
  }
  return partes.join(' | ');
}

/// Nomes dos NRC (ISO 14229) que importam no spike.
String nomeNrc(int? nrc) => switch (nrc) {
      0x10 => '10 rejeição geral',
      0x11 => '11 serviço não suportado',
      0x12 => '12 subfunção não suportada',
      0x13 => '13 tamanho incorreto',
      0x14 => '14 resposta longa demais',
      0x22 => '22 condições incorretas',
      0x31 => '31 fora de faixa (DID inexistente)',
      0x33 => '33 ACESSO DE SEGURANÇA negado',
      0x78 => '78 resposta pendente',
      0x7E => '7E subfunção não suportada NESTA SESSÃO',
      0x7F => '7F serviço não suportado NESTA SESSÃO',
      null => 'sem código',
      _ => '${hex2(nrc)} outro',
    };
