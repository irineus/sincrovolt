// tool/testar_verificador.dart — prova negativa das regras do verificador (EVAPP-75).
//
//   fvm dart run tool/testar_verificador.dart
//
// Par do tool/testar_varredura.sh: cada caso dá uma entrada (certa ou errada) às regras
// de tool/verificador/regras.dart e confere o veredicto. Sai com 1 se algum caso falhar.
// Roda no CI antes do verificador. Dart puro, sem package:test, sem pubspec.

import 'dart:io';

import 'verificador/regras.dart';

var _falhas = 0;

void _caso(String nome, Object? obtido, Object? esperado) {
  if (obtido == esperado) {
    stdout.writeln('  ok     $nome');
  } else {
    _falhas++;
    stdout.writeln('  FALHA  $nome: esperado <$esperado>, veio <$obtido>');
  }
}

// Saída real de `flutter --version --machine` (3.50.1), encurtada.
const _json = '''{
  "frameworkVersion": "3.50.1",
  "channel": "stable",
  "dartSdkVersion": "3.14.0"
}''';

// Aviso que o Flutter imprime na primeira execução numa máquina/container novo
// (pacote unified_analytics). Foi ele que fez o verificador acusar "o PATH resolve
// CLI" na nuvem (EVAPP-75): o JSON deixou de ser parseável e o regex pegou "CLI".
const _avisoPrimeiraExecucao = '''
  ╔════════════════════════════════════════════════════════════════════════════╗
  ║ The Flutter CLI developer tool uses Google Analytics to report usage and   ║
  ║ diagnostic data along with package dependencies, and crash reporting to    ║
  ║ send basic crash reports.                                                  ║
  ║                                                                            ║
  ║ Telemetry is not sent on the very first run. To disable reporting of       ║
  ║ telemetry, run this terminal command:                                      ║
  ║                                                                            ║
  ║     flutter --disable-analytics                                            ║
  ╚════════════════════════════════════════════════════════════════════════════╝
''';

void main() {
  stdout.writeln('versaoDoFlutter');
  _caso('JSON puro', versaoDoFlutter(_json), '3.50.1');
  _caso('aviso ANTES do JSON', versaoDoFlutter('$_avisoPrimeiraExecucao$_json'), '3.50.1');
  _caso('aviso DEPOIS do JSON', versaoDoFlutter('$_json\n$_avisoPrimeiraExecucao'), '3.50.1');
  _caso(
    'formato texto',
    versaoDoFlutter('Flutter 3.44.7 • channel stable • https://github.com/flutter/flutter.git'),
    '3.44.7',
  );
  _caso('só o aviso (sem versão) dá null, nunca "CLI"', versaoDoFlutter(_avisoPrimeiraExecucao), null);
  _caso('saída vazia dá null', versaoDoFlutter(''), null);
  _caso('chave sem fechar não trava', versaoDoFlutter('{ "frameworkVersion": "3.50.1"'), null);

  stdout.writeln('sdksDoLock');
  const lock = '''
packages:
  vector_math:
    dependency: transitive
    description:
      name: vector_math
    source: hosted
    version: "2.4.4"
sdks:
  dart: ">=3.14.0 <4.0.0"
  flutter: ">=3.47.0"
''';
  final sdks = sdksDoLock(lock);
  _caso('lê o dart', sdks['dart'], '>=3.14.0 <4.0.0');
  _caso('lê o flutter', sdks['flutter'], '>=3.47.0');
  _caso('não confunde "version" de pacote com sdk', sdks.length, 2);
  _caso('lock sem sdks dá vazio', sdksDoLock('packages:\n').isEmpty, true);

  stdout.writeln('violacaoDeRestricao');
  _caso('3.14.0 atende >=3.14.0 <4.0.0', violacaoDeRestricao('3.14.0', '>=3.14.0 <4.0.0'), null);
  _caso('3.50.1 atende >=3.47.0', violacaoDeRestricao('3.50.1', '>=3.47.0'), null);
  _caso('qualquer versão atende any', violacaoDeRestricao('3.12.2', 'any'), null);
  _caso(
    'pré-lançamento no limite: 3.18.0 atende >=3.18.0-18.0.pre.54',
    violacaoDeRestricao('3.18.0', '>=3.18.0-18.0.pre.54'),
    null,
  );
  // O caso real do EVAPP-9: lock regenerado pelo flutter global (Dart 3.13+) com o pin
  // ainda em 3.44.7 (Dart 3.12.2). Tem de reprovar.
  _caso(
    'Dart 3.12.2 NÃO atende >=3.13.0 <4.0.0 (caso do EVAPP-9)',
    violacaoDeRestricao('3.12.2', '>=3.13.0 <4.0.0'),
    '3.12.2 não atende ">=3.13.0 <4.0.0"',
  );
  _caso(
    'Flutter 3.44.7 NÃO atende >=3.47.0',
    violacaoDeRestricao('3.44.7', '>=3.47.0'),
    '3.44.7 não atende ">=3.47.0"',
  );
  _caso(
    'teto: 4.0.0 NÃO atende <4.0.0',
    violacaoDeRestricao('4.0.0', '>=3.14.0 <4.0.0'),
    '4.0.0 não atende ">=3.14.0 <4.0.0"',
  );
  _caso(
    'pré-lançamento abaixo do limite: 3.14.0-1.0.dev NÃO atende >=3.14.0',
    violacaoDeRestricao('3.14.0-1.0.dev', '>=3.14.0'),
    '3.14.0-1.0.dev não atende ">=3.14.0"',
  );
  _caso(
    'restrição ilegível é violação, não aprovação',
    violacaoDeRestricao('3.14.0', '>=banana'),
    'restrição ">=banana" ilegível',
  );

  stdout.writeln('');
  if (_falhas > 0) {
    stdout.writeln('testar_verificador: $_falhas CASO(S) FALHARAM');
    exit(1);
  }
  stdout.writeln('testar_verificador: TODOS OS CASOS OK');
}
