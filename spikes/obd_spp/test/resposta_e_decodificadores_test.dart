import 'package:flutter_test/flutter_test.dart';
import 'package:obd_spp/nucleo/decodificadores.dart';
import 'package:obd_spp/nucleo/resposta_elm.dart';

import 'apoio.dart';

List<Leitura> dec(String cmd, String bruta) => decodificar(cmd, interpretar(bruta, comando: cmd));

void main() {
  group('VIN multiquadro', () {
    test('ATH1 com espaços', () {
      final l = dec('0902', respostaVinAth1());
      expect(l.single.sinal, 'VIN');
      expect(l.single.texto, vinFalso);
      expect(l.single.ecu, '7E8');
    });
    test('ATH1 + ATS0 (compacto)', () => expect(dec('0902', respostaVinCompacta()).single.texto, vinFalso));
    test('ATH0 com linhas numeradas', () => expect(dec('0902', respostaVinAth0()).single.texto, vinFalso));
    test('multiquadro incompleto não vira VIN', () {
      final corte = respostaVinAth1().split('\r').take(2).join('\r');
      expect(dec('0902', corte).single.texto, startsWith('ilegível'));
    });
  });

  test('0100 de dois módulos com eco e SEARCHING', () {
    final r = interpretar('0100\rSEARCHING...\r7E8 06 41 00 BE 3F A8 13\r7E9 06 41 00 98 18 80 11\r\r', comando: '0100');
    expect(r.mensagens.map((m) => m.ecu), ['7E8', '7E9']);
    expect(pidsSuportados('00', [0xBE, 0x3F, 0xA8, 0x13]).take(6), ['01', '03', '04', '05', '06', '07']);
  });

  test('01A6: 4 bytes × 0,1 km', () {
    final l = dec('01A6', '7E8 06 41 A6 00 05 D4 13').single;
    expect(l.texto, '38197,1 km');
    expect(l.valores['hodômetro'], closeTo(38197.1, 1e-9));
  });

  test('015B: A × 100 / 255', () {
    final l = dec('015B', '7E8 03 41 5B F2').single;
    expect(l.valores['SoC'], closeTo(94.902, 0.001));
    expect(l.texto, startsWith('94.90 %'));
    expect(dec('015B', '7E8 03 41 5B FF').single.valores['SoC'], 100);
    expect(dec('015B', '7E8 03 41 5B 00').single.valores['SoC'], 0);
  });

  group('019A: tensão ÷64 V, corrente ×0,1 A com sinal (positiva = descarga)', () {
    test('carga (negativa)', () {
      final l = dec('019A', '7E8 07 41 9A 03 60 00 FF 9C').single;
      expect(l.valores['tensão HV'], 384);
      expect(l.valores['V/I'], -10);
      expect(l.texto, contains('(carga)'));
    });
    test('descarga (positiva)', () {
      final l = dec('019A', '7E8 07 41 9A 03 5C 40 00 C8').single;
      expect(l.valores['tensão HV'], closeTo(369.0, 1e-9));
      expect(l.valores['V/I'], 20);
      expect(l.texto, contains('(descarga)'));
    });
    test('fronteira do sinal: 7FFF e 8000', () {
      expect(tensaoCorrente([3, 0, 0, 0x7F, 0xFF])!.$2, 32767);
      expect(tensaoCorrente([3, 0, 0, 0x80, 0x00])!.$2, -32768);
    });
  });

  test('erros do adaptador', () {
    expect(interpretar('NO DATA\r\r', comando: '015B').erro, 'NO DATA');
    expect(interpretar('?\r', comando: '0100').erro, '?');
    expect(interpretar('UNABLE TO CONNECT\r', comando: '0100').erro, 'UNABLE TO CONNECT');
    expect(dec('015B', 'NO DATA').single.texto, 'NO DATA');
  });

  test('resposta negativa vira texto com o NRC', () {
    final l = dec('22F190', '7EC 03 7F 22 31').single;
    expect(l.texto, contains('DID inexistente'));
  });

  test('modo 22 positivo: bytes e leituras candidatas', () {
    final l = dec('220100', '7EC 05 62 01 00 01 F4').single;
    expect(l.sinal, 'DID 0100');
    expect(l.texto, contains('u16: 500'));
  });

  test('DID que devolve VIN em ASCII sai mascarado', () {
    final bytes = vinFalso.codeUnits;
    final t = candidatasDid(bytes);
    expect(t, contains('LGW**************'));
    expect(t, isNot(contains(vinFalso)));
    expect(t, isNot(contains(bytes.skip(3).join(' '))));
  });

  test('ATRV vira tensão da bateria 12 V', () {
    expect(dec('ATRV', '12.6V').single.valores['bateria 12 V'], 12.6);
  });

  test('formatarDecimos', () {
    expect(formatarDecimos(381971), '38197,1');
    expect(formatarDecimos(-100), '-10,0');
    expect(formatarDecimos(5), '0,5');
  });
}
