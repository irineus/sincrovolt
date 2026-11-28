// Lista explícita de comandos permitidos do spike (CLAUDE.md, regra 1: OBD é só leitura).
//
// É o ÚNICO caminho até o socket: o transporte Bluetooth (lib/plataforma) só aceita um
// [Permitido], e um [Permitido] só nasce aqui dentro (construtor privado). Qualquer texto
// que não esteja na lista vira [Recusado] ANTES de sair do celular, com o motivo visível.
//
// Dart puro: sem Flutter, testado em test/comandos_permitidos_test.dart.

/// Resultado da avaliação de um comando.
sealed class Veredito {
  const Veredito(this.digitado);

  /// O texto como a pessoa (ou a tela) pediu.
  final String digitado;
}

/// Comando que pode sair para o adaptador.
final class Permitido extends Veredito {
  const Permitido._(super.digitado, this.comando, this.categoria, this.bytes);

  /// Comando normalizado (maiúsculas, sem espaços), ex.: `0100`, `ATSH7E0`.
  final String comando;

  /// Categoria da lista, para o log (ex.: "modo 22 (leitura por DID)").
  final String categoria;

  /// Exatamente o que vai para o socket (comando + CR, ou o espaço que encerra o ATMA).
  final String bytes;

  /// `true` quando o comando não espera o prompt `>` (o ATMA fica escutando).
  bool get abreMonitor => comando == 'ATMA';
}

/// Comando barrado antes de sair.
final class Recusado extends Veredito {
  const Recusado(super.digitado, this.motivo);

  final String motivo;
}

/// Serviços (primeiro byte) proibidos, com o nome para a mensagem. Nenhum deles passa;
/// a lista existe só para a mensagem ser clara. O que decide é a lista de PERMITIDOS.
const Map<String, String> servicosProibidos = {
  '02': 'freeze frame (fora da lista do spike)',
  '03': 'leitura de códigos de falha (fora da lista do spike)',
  '04': 'APAGA códigos de falha',
  '05': 'monitor de sonda (fora da lista do spike)',
  '06': 'resultados de testes de bordo (fora da lista do spike)',
  '07': 'códigos pendentes (fora da lista do spike)',
  '08': 'controle de sistema de bordo',
  '0A': 'códigos permanentes (fora da lista do spike)',
  '10': 'troca de sessão de diagnóstico',
  '11': 'RESET de módulo',
  '14': 'APAGA informação de diagnóstico',
  '19': 'leitura de DTC UDS (fora da lista do spike)',
  '27': 'acesso de segurança',
  '28': 'controle de comunicação',
  '2C': 'definição dinâmica de DID',
  '2E': 'ESCRITA por DID',
  '2F': 'controle de entrada/saída',
  '31': 'controle de rotina',
  '34': 'pedido de download (gravação)',
  '35': 'pedido de upload',
  '36': 'transferência de dados',
  '37': 'fim de transferência',
  '3B': 'ESCRITA por identificador local (KWP)',
  '3D': 'ESCRITA em memória',
  '3E': 'tester present (mantém sessão)',
  '85': 'controle de gravação de DTC',
};

/// Encerramento do ATMA: um espaço, SEM CR. Qualquer caractere interrompe o monitor; o
/// espaço foi escolhido porque, se o adaptador já não estiver monitorando, o ELM327
/// ignora espaços na entrada — e um CR sozinho REPETIRIA o último comando.
const String encerramentoMonitor = ' ';

final RegExp _soPermitidos = RegExp(r'^[0-9A-Z]+$');
final RegExp _hex = RegExp(r'^[0-9A-F]+$');

/// Comandos AT exatos da lista.
const Set<String> _atFixos = {
  'ATZ', // reinicia o adaptador
  'ATE0', // eco desligado
  'ATL0', // sem line feed
  'ATS0', // sem espaços na resposta
  'ATH1', // mostra o cabeçalho CAN
  'ATSP0', // protocolo automático
  'ATDP', // descreve o protocolo
  'ATRV', // tensão no pino 16 (bateria 12 V)
  'ATAT0', 'ATAT1', 'ATAT2', // temporização adaptativa
  'ATMA', // monitor (só escuta)
};

/// Comandos AT com argumento. Cabeçalhos só na faixa de diagnóstico 11 bits 7xx.
final List<(RegExp, String)> _atComArgumento = [
  (RegExp(r'^ATST[0-9A-F]{2}$'), 'AT timeout'),
  (RegExp(r'^ATSH7[0-9A-F]{2}$'), 'AT cabeçalho 11 bits (7xx)'),
  (RegExp(r'^ATCRA7[0-9A-F]{2}$'), 'AT filtro de recepção (7xx)'),
];

/// Pedidos OBD/UDS permitidos: só leitura, um PID/DID por pedido.
final List<(RegExp, String)> _obd = [
  (RegExp(r'^01[0-9A-F]{2}$'), 'modo 01 (dados correntes)'),
  (RegExp(r'^09[0-9A-F]{2}$'), 'modo 09 (informação do veículo)'),
  (RegExp(r'^22[0-9A-F]{4}$'), 'modo 22 (leitura por DID)'),
];

/// Tamanho máximo de um comando normalizado (o maior da lista é `ATCRA7xx`, 8).
const int tamanhoMaximo = 8;

/// Normaliza: maiúsculas, sem espaços nem tabulação. Não remove outros caracteres —
/// eles são motivo de recusa, não de limpeza.
String normalizar(String texto) =>
    texto.toUpperCase().replaceAll(RegExp(r'[ \t]'), '');

/// Avalia um comando contra a lista. É a única função que cria um [Permitido].
Veredito avaliar(String digitado) {
  final c = normalizar(digitado);
  if (c.isEmpty) {
    return Recusado(digitado, 'comando vazio (um CR sozinho repetiria o último comando)');
  }
  if (!_soPermitidos.hasMatch(c)) {
    return Recusado(digitado, 'caractere fora de 0-9/A-Z (CR, ponto e vírgula, quebra de linha…)');
  }
  if (c.length > tamanhoMaximo) {
    return Recusado(digitado, 'comando maior que $tamanhoMaximo caracteres');
  }
  if (c.startsWith('AT')) {
    if (_atFixos.contains(c)) return Permitido._(digitado, c, 'AT de configuração', '$c\r');
    for (final (re, cat) in _atComArgumento) {
      if (re.hasMatch(c)) return Permitido._(digitado, c, cat, '$c\r');
    }
    return Recusado(digitado, 'AT fora da lista ($c)');
  }
  if (!_hex.hasMatch(c)) {
    return Recusado(digitado, 'pedido OBD precisa ser hexadecimal');
  }
  if (c.length.isOdd) {
    return Recusado(digitado, 'pedido OBD com número ímpar de dígitos');
  }
  for (final (re, cat) in _obd) {
    if (re.hasMatch(c)) return Permitido._(digitado, c, cat, '$c\r');
  }
  final servico = c.substring(0, 2);
  final nome = servicosProibidos[servico];
  if (nome != null) {
    return Recusado(digitado, 'serviço $servico — $nome — PROIBIDO (só leitura)');
  }
  if (servico == '01' || servico == '09' || servico == '22') {
    return Recusado(digitado, 'serviço $servico com tamanho errado (um PID/DID por pedido)');
  }
  return Recusado(digitado, 'serviço $servico fora da lista');
}

/// O espaço que encerra o ATMA, como [Permitido] (para passar pelo mesmo caminho).
Permitido encerrarMonitor() =>
    const Permitido._('(parar monitor)', '(parar monitor)', 'encerramento do ATMA', encerramentoMonitor);
