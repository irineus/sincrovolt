import 'package:flutter_test/flutter_test.dart';
import 'package:obd_spp/nucleo/resposta_elm.dart';
import 'package:obd_spp/nucleo/taxa.dart';
import 'package:obd_spp/nucleo/varredura.dart';
import 'package:obd_spp/telas/taxa.dart' show entradaDoLaco;

Desfecho d(String bruta) => classificarDid(0x0100, interpretar(bruta, comando: '220100')).desfecho;

void main() {
  group('decisão da varredura', () {
    test('7F 22 31 = DID inexistente, segue', () => expect(d('7EC 03 7F 22 31'), Desfecho.inexistente));
    test('7F 22 33 = pare e pergunte', () => expect(d('7EC 03 7F 22 33'), Desfecho.pareEPergunte));
    test('7F 22 7E = pare e pergunte', () => expect(d('7EC 03 7F 22 7E'), Desfecho.pareEPergunte));
    test('7F 22 7F = pare e pergunte', () => expect(d('7EC 03 7F 22 7F'), Desfecho.pareEPergunte));
    test('7F 22 11 = módulo sem modo 22', () => expect(d('7EC 03 7F 22 11'), Desfecho.moduloSemModo22));
    test('7F 22 22 = outra negativa, segue', () => expect(d('7EC 03 7F 22 22'), Desfecho.outraNegativa));
    test('NO DATA = sem resposta', () => expect(d('NO DATA'), Desfecho.semResposta));
    test('positiva do DID certo = achado', () {
      final r = classificarDid(0x0100, interpretar('7EC 05 62 01 00 01 F4', comando: '220100'));
      expect(r.desfecho, Desfecho.achado);
      expect(r.dados, [0x01, 0xF4]);
      expect(r.ecu, '7EC');
    });
    test('positiva de OUTRO DID não conta como achado', () => expect(d('7EC 05 62 01 01 01 F4'), Desfecho.semResposta));
    test('78 pendente seguido da final = achado', () => expect(d('7EC 03 7F 22 78\r7EC 04 62 01 00 5E'), Desfecho.achado));
    test('pare-e-pergunte vence se outro módulo respondeu 31', () =>
        expect(d('7E8 03 7F 22 31\r7EC 03 7F 22 33'), Desfecho.pareEPergunte));
  });

  test('faixas de cabeçalho e de DID', () {
    expect(faixaDeCabecalhos('7E0'), [0x7E0]);
    expect(faixaDeCabecalhos('7a0-7a2'), [0x7A0, 0x7A1, 0x7A2]);
    expect(faixaDeCabecalhos('6F0'), isNull);
    expect(faixaDeCabecalhos('7E7-7E0'), isNull);
    expect(faixaDeDids('F190'), [0xF190]);
    expect(faixaDeDids('0100-01FF')!.length, 256);
    expect(faixaDeDids('0000-FFFF'), isNull); // acima de 4096 por rodada
  });

  test('entradas do laço de taxa', () {
    expect(entradaDoLaco('015B'), ('7DF', '015B'));
    expect(entradaDoLaco('7e4:22f190'), ('7E4', '22F190'));
    expect(entradaDoLaco('7E4:2EF190'), isNull);
    expect(entradaDoLaco('04'), isNull);
    expect(entradaDoLaco('ATZ'), isNull);
    expect(entradaDoLaco('6E4:220100'), isNull);
  });

  test('amostras por segundo', () {
    final e = EstatisticaSinal('015B');
    for (var i = 0; i < 24; i++) {
      e.registrar(sucesso: true, latenciaMs: 100 + i);
    }
    e.registrar(sucesso: false, latenciaMs: 3000);
    const dur = Duration(seconds: 12);
    expect(e.amostrasPorSegundo(dur), 2);
    expect(e.intervaloMedioS(dur), 0.5);
    expect(e.falhas, 1);
    expect(e.maxLatenciaMs, 123);
  });
}
