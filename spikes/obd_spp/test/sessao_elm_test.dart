import 'package:flutter_test/flutter_test.dart';
import 'package:obd_spp/elm/sessao_elm.dart';
import 'package:obd_spp/nucleo/registro.dart';

import 'apoio.dart';

void main() {
  test('comando proibido não chega ao transporte', () async {
    final t = TransporteFalso({});
    final s = SessaoElm(t, Registro());
    for (final c in ['04', '1003', '2701', '2EF190', '', 'ATPP0CSV']) {
      final troca = await s.enviar(c);
      expect(troca.recusada, isTrue, reason: c);
      expect(troca.falha, startsWith('RECUSADO'));
    }
    expect(t.escritos, isEmpty);
  });

  test('pedido permitido sai com CR e volta decodificado', () async {
    final t = TransporteFalso({'015B': '7E8 03 41 5B F2'});
    final r = Registro();
    final s = SessaoElm(t, r);
    final troca = await s.enviar('01 5b');
    expect(t.escritos, ['015B\r']);
    expect(troca.sucesso, isTrue);
    expect(troca.leituras.single.valores['SoC'], closeTo(94.9, 0.01));
    expect(r.entradas.map((e) => e.sentido), [Sentido.pedido, Sentido.resposta, Sentido.decodificado]);
  });

  test('timeout e resposta atrasada não contaminam o próximo pedido', () async {
    final t = TransporteFalso({'015B': null, '019A': '7E8 07 41 9A 03 60 00 FF 9C'});
    final r = Registro();
    final s = SessaoElm(t, r);
    final a = await s.enviar('015B', limite: const Duration(milliseconds: 50));
    expect(a.falha, startsWith('TIMEOUT'));
    t.injetar('7E8 03 41 5B 10\r\r>'); // chega depois do timeout
    final b = await s.enviar('019A');
    expect(b.sucesso, isTrue);
    expect(b.leituras.single.valores['V/I'], -10);
    expect(r.entradas.any((e) => e.texto.startsWith('resposta atrasada descartada')), isTrue);
  });

  test('ATMA liga o monitor; outro pedido é barrado; parar manda só um espaço', () async {
    final t = TransporteFalso({'ATMA': null});
    final s = SessaoElm(t, Registro());
    final linhas = <String>[];
    s.aoLinhaMonitor = linhas.add;
    await s.enviar('ATMA');
    expect(s.monitorando, isTrue);
    t.injetar('7E8 03 41 0D 00\r3A1 08 01 02');
    t.injetar('\r');
    await Future<void>.delayed(Duration.zero);
    expect(linhas, ['7E8 03 41 0D 00', '3A1 08 01 02']);
    final barrado = await s.enviar('0100');
    expect(barrado.falha, contains('monitor'));
    final parar = s.pararMonitor();
    await Future<void>.delayed(Duration.zero);
    t.injetar('STOPPED\r\r>');
    final p = await parar;
    expect(p.falha, isNull);
    expect(s.monitorando, isFalse);
    expect(t.escritos, ['ATMA\r', ' ']);
  });

  test('ATSH muda o cabeçalho ativo e ATZ volta ao 7DF', () async {
    final t = TransporteFalso({'ATSH7E4': 'OK', 'ATZ': 'ELM327 v1.5'});
    final s = SessaoElm(t, Registro());
    await s.enviar('ATSH7E4');
    expect(s.cabecalho, '7E4');
    await s.enviar('ATZ');
    expect(s.cabecalho, '7DF');
  });
}
