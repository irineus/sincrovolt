import 'package:flutter_test/flutter_test.dart';
import 'package:obd_spp/nucleo/mascara_vin.dart';
import 'package:obd_spp/nucleo/registro.dart';
import 'package:obd_spp/nucleo/resposta_elm.dart';
import 'package:obd_spp/nucleo/decodificadores.dart';

import 'apoio.dart';

/// Mesma regra de VIN da tool/varrer_segredos.sh.
final _vinRegex = RegExp(r'(^|[^A-Za-z0-9])[A-HJ-NPR-Z0-9]{17}([^A-Za-z0-9]|$)');

void main() {
  test('mascararVin deixa só os 3 primeiros', () {
    expect(mascararVin(vinFalso), 'LGW**************');
  });

  for (final (nome, bruta) in [
    ('ATH1', respostaVinAth1()),
    ('ATS0', respostaVinCompacta()),
    ('ATH0', respostaVinAth0()),
  ]) {
    test('hex do VIN mascarado na resposta bruta ($nome)', () {
      final m = mascararVinEmHex(bruta);
      // os 3 primeiros bytes ficam; dos outros 14 não sobra nenhum
      expect(m.replaceAll(' ', ''), contains(hexDe('LGW').replaceAll(' ', '')));
      for (final c in vinFalso.substring(3).split('').toSet()) {
        final h = hexDe(c);
        final linhasDeDado = m.split('\r').where((l) => l.trim().isNotEmpty).map((l) {
          final t = l.trim();
          return nome == 'ATS0' ? t.substring(5) : t.split(' ').skip(nome == 'ATH0' ? 1 : 2).join(' ');
        });
        for (final l in linhasDeDado.skip(1)) {
          expect(l.replaceAll(' ', ''), isNot(contains(h)), reason: 'byte $h de "$c" ficou visível em "$l"');
        }
      }
      expect(m.split('**').length - 1, 14);
      // e o VIN não decodifica mais
      expect(decodificar('0902', interpretar(m, comando: '0902')).single.texto, startsWith('ilegível'));
    });
  }

  test('resposta sem VIN passa intacta', () {
    const b = '7E8 06 41 00 BE 3F A8 13\r7E9 06 41 00 98 18 80 11\r';
    expect(mascararVinEmHex(b), b);
  });

  test('log exportado não tem VIN nem hex do VIN', () {
    final r = Registro();
    final t = DateTime(2026, 11, 28, 10, 0, 0, 42);
    r.adicionar(Entrada(t, Sentido.pedido, '0902   [modo 09]'));
    r.adicionar(Entrada(t, Sentido.resposta, respostaVinAth1().trim(), latenciaMs: 180));
    final l = decodificar('0902', interpretar(respostaVinAth1(), comando: '0902')).single;
    r.adicionar(Entrada(t, Sentido.decodificado, l.toString()));
    final texto = r.exportar(cabecalho: 'teste $vinFalso');
    expect(texto, isNot(contains(vinFalso)));
    expect(_vinRegex.hasMatch(texto), isFalse);
    expect(texto, contains('LGW**************'));
    expect(texto, contains('10:00:00.042 →'));
    expect(texto, contains('(180 ms)'));
    expect(texto, contains('7E8 10 14 49 02 01 4C 47 57 | 7E8 21 ** ** ** ** ** ** **'));
  });
}
