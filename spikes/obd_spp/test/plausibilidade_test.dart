import 'package:flutter_test/flutter_test.dart';
import 'package:obd_spp/nucleo/plausibilidade.dart';

void main() {
  final t0 = DateTime(2026, 11, 28, 10);

  test('leituras corrompidas já vistas são marcadas', () {
    final f = FiltroPlausibilidade();
    expect(f.avaliar('corrente BMS', correnteRealBms(-1200), t0), isNotNull); // Bus current −1200 A
    expect(f.avaliar('célula', 7462, t0), isNotNull); // célula 7.462 mV
    expect(f.avaliar('célula', 3650, t0), isNull);
    expect(f.avaliar('corrente BMS', correnteRealBms(310), t0), isNull); // 10 A descarga
  });

  test('faixas do OBD padrão', () {
    final f = FiltroPlausibilidade();
    expect(f.avaliar('tensão HV', 384, t0), isNull);
    expect(f.avaliar('tensão HV', 1023.98, t0), isNotNull);
    expect(f.avaliar('V/I', -10, t0), isNull);
    expect(f.avaliar('V/I', -3276.8, t0), isNotNull);
    expect(f.avaliar('bateria 12 V', 12.4, t0), isNull);
    expect(f.avaliar('bateria 12 V', 3.1, t0), isNotNull);
  });

  test('hodômetro não volta; SoC não salta', () {
    final f = FiltroPlausibilidade();
    expect(f.avaliar('hodômetro', 38197.1, t0), isNull);
    expect(f.avaliar('hodômetro', 38197.3, t0.add(const Duration(seconds: 5))), isNull);
    expect(f.avaliar('hodômetro', 38100.0, t0.add(const Duration(seconds: 6))), contains('voltou'));
    expect(f.avaliar('SoC', 60.0, t0), isNull);
    expect(f.avaliar('SoC', 60.4, t0.add(const Duration(seconds: 2))), isNull);
    expect(f.avaliar('SoC', 75.0, t0.add(const Duration(seconds: 3))), contains('salto'));
    // a leitura suspeita não vira referência: a próxima normal passa
    expect(f.avaliar('SoC', 60.8, t0.add(const Duration(seconds: 4))), isNull);
  });

  test('sinal sem faixa não é marcado', () {
    expect(FiltroPlausibilidade().avaliar('desconhecido', 1e9, t0), isNull);
  });
}
