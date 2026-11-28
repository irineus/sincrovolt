// Teste-portão da lista de comandos permitidos (CLAUDE.md regras 1 e 4).
import 'package:flutter_test/flutter_test.dart';
import 'package:obd_spp/nucleo/comandos_permitidos.dart';

void main() {
  group('permitidos', () {
    const casos = {
      'ATZ': 'ATZ', 'ATE0': 'ATE0', 'ATL0': 'ATL0', 'ATS0': 'ATS0', 'ATH1': 'ATH1',
      'ATSP0': 'ATSP0', 'ATDP': 'ATDP', 'ATRV': 'ATRV', 'ATST32': 'ATST32', 'ATAT1': 'ATAT1',
      'ATSH7E0': 'ATSH7E0', 'AT SH 7DF': 'ATSH7DF', 'ATCRA7E8': 'ATCRA7E8', 'ATMA': 'ATMA',
      'atz': 'ATZ', '0100': '0100', '01 A6': '01A6', '015B': '015B', '019A': '019A',
      '0902': '0902', '22F190': '22F190', '22 01 00': '220100',
    };
    casos.forEach((digitado, normalizado) {
      test('"$digitado" passa como $normalizado', () {
        final v = avaliar(digitado);
        expect(v, isA<Permitido>(), reason: v is Recusado ? v.motivo : '');
        final p = v as Permitido;
        expect(p.comando, normalizado);
        expect(p.bytes, '$normalizado\r');
      });
    });

    test('encerramento do ATMA é um espaço sem CR', () {
      expect(encerrarMonitor().bytes, ' ');
    });
  });

  group('recusados (nada disto pode sair para o adaptador)', () {
    const proibidos = [
      // os do critério de aceite do EVAPP-11
      '04', '10', '14', '27', '2E', '2F', '31', '3B',
      // com argumentos típicos de uso real
      '1003', '1002', '1101', '14FFFFFF', '2701', '2702', '2EF19041', '2F010203',
      '31010203', '3B9001', '3E00', '8502', '2803', '3D', '34', '36', '37',
      // OBD fora da lista
      '03', '07', '0A', '02', '05', '06', '08', '19', '0101 04',
      // tamanho errado nos modos permitidos
      '01', '010', '01000', '09', '22', '22F1', '22F19', '22F19001', '220100F190',
      // vazio e lixo
      '', '   ', '\r', '\n', '04\r', '0100\r04', '0100;04', 'ZZ', '!@#', 'ÇÃ', 'G1',
      // AT fora da lista (inclusive os que gravam no adaptador)
      'ATPP0CSV', 'ATPPFFON', 'ATWS', 'ATD', 'ATI', 'ATSP6', 'ATBRD23', 'ATSH6F0',
      'ATSH7E', 'ATSH7E00', 'ATSH18DA10F1', 'ATCRA', 'ATCRA6E8', 'ATST', 'ATST1', 'ATAT3',
      'ATMA1', 'ATBI', 'ATCAF0', 'ATFCSD300000', 'ATH0', 'ATE1', 'ATLP',
    ];
    for (final c in proibidos) {
      test('"${c.replaceAll('\r', r'\r').replaceAll('\n', r'\n')}" é recusado', () {
        expect(avaliar(c), isA<Recusado>());
      });
    }

    test('mensagem de recusa nomeia o serviço proibido', () {
      final v = avaliar('04') as Recusado;
      expect(v.motivo, contains('APAGA'));
      expect((avaliar('2E F1 90') as Recusado).motivo, contains('ESCRITA'));
      expect((avaliar('') as Recusado).motivo, contains('vazio'));
    });
  });
}
