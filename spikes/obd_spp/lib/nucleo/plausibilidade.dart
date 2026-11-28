// Filtro de plausibilidade: MARCA leitura absurda (não descarta). Dart puro.
//
// Leituras corrompidas já vistas no H6 GT (EVAPP-8): Bus current −1200 A e célula
// 7.462 mV. As faixas abaixo são largas de propósito: pegam o absurdo, não o raro.

/// Faixa aceitável de um sinal, na unidade de exibição.
class Faixa {
  const Faixa(this.min, this.max, this.unidade);
  final double min;
  final double max;
  final String unidade;

  String? avaliar(double v) => v < min || v > max
      ? 'fora de [${_f(min)}, ${_f(max)}] $unidade'
      : null;
}

String _f(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Faixas por sinal. As do BMS (corrente real = Bus current − 300, células, SoH,
/// temperaturas) valem quando os DIDs forem conhecidos.
const Map<String, Faixa> faixas = {
  'SoC': Faixa(0, 100, '%'),
  'hodômetro': Faixa(0, 1000000, 'km'),
  'tensão HV': Faixa(100, 600, 'V'),
  'V/I': Faixa(-400, 400, 'A'), // corrente do 019A
  'corrente BMS': Faixa(-400, 400, 'A'), // Bus current − 300
  'célula': Faixa(2000, 4500, 'mV'),
  'SoH': Faixa(50, 100, '%'),
  'temperatura': Faixa(-40, 80, '°C'),
  'bateria 12 V': Faixa(9, 16, 'V'),
  'rpm': Faixa(0, 8000, 'rpm'),
  'combustível': Faixa(0, 100, '%'),
};

/// Salto máximo entre duas leituras seguidas (mesmo sinal, até [janela] de distância).
const Map<String, double> saltoMaximo = {
  'SoC': 3, // pontos percentuais
  'hodômetro': 5, // km
};

/// Filtro com memória da última leitura de cada sinal.
class FiltroPlausibilidade {
  FiltroPlausibilidade({this.janela = const Duration(seconds: 30)});

  final Duration janela;
  final Map<String, (double, DateTime)> _ultima = {};

  /// Devolve o motivo da suspeita, ou `null` se plausível.
  String? avaliar(String sinal, double valor, DateTime quando) {
    final faixa = faixas[sinal];
    final foraDaFaixa = faixa?.avaliar(valor);
    if (foraDaFaixa != null) return foraDaFaixa; // não vira referência para o próximo
    String? motivo;
    final anterior = _ultima[sinal];
    if (anterior != null) {
      final (v0, t0) = anterior;
      final dt = quando.difference(t0);
      if (sinal == 'hodômetro' && valor < v0) {
        motivo = 'hodômetro voltou (${_f(v0)} → ${_f(valor)} km)';
      }
      final salto = saltoMaximo[sinal];
      if (motivo == null && salto != null && dt <= janela && (valor - v0).abs() > salto) {
        motivo = 'salto de ${_f((valor - v0).abs())} em ${dt.inMilliseconds} ms';
      }
    }
    if (motivo == null) _ultima[sinal] = (valor, quando);
    return motivo;
  }
}

/// Corrente real da bateria a partir do Bus current do BMS (EVAPP-8).
double correnteRealBms(double busCurrent) => busCurrent - 300;
