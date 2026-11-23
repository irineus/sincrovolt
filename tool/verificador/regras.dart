// tool/verificador/regras.dart — regras puras do verificador de ambiente (EVAPP-75).
//
// Só funções sem efeito colateral: entram textos, saem veredictos. Ficam fora do
// `tool/verificar_ambiente.dart` para que o `tool/testar_verificador.dart` as exercite
// com entradas certas E erradas (prova negativa, regra 4 do CLAUDE.md). Mesmo contrato
// do verificador: Dart puro, só `dart:convert`, sem pubspec e sem dependência.

import 'dart:convert';

final _versaoNumerica = RegExp(r'^\d+\.\d+\.\d+');

/// Versão do Flutter na saída de `flutter --version --machine` (ou do formato texto).
///
/// A saída pode vir misturada com o aviso de telemetria que o Flutter imprime na
/// primeira execução numa máquina nova. Por isso cada `{` é tentado como início do
/// JSON até o `}` que fecha o objeto, e o formato texto só vale com número de versão.
/// Devolve null quando não há versão reconhecível — nunca um pedaço de texto qualquer.
String? versaoDoFlutter(String saida) {
  for (var i = saida.indexOf('{'); i >= 0; i = saida.indexOf('{', i + 1)) {
    final fim = _fimDoObjeto(saida, i);
    if (fim < 0) continue;
    try {
      final json = jsonDecode(saida.substring(i, fim + 1));
      if (json is Map && json['frameworkVersion'] is String) {
        return json['frameworkVersion'] as String;
      }
    } on FormatException {
      // não era JSON; tenta o próximo `{`
    }
  }
  return RegExp(r'Flutter (\d+\.\d+\.\d+\S*)').firstMatch(saida)?.group(1);
}

/// Índice do `}` que fecha o objeto aberto em [inicio], respeitando strings JSON.
int _fimDoObjeto(String s, int inicio) {
  var nivel = 0;
  var emString = false;
  for (var i = inicio; i < s.length; i++) {
    final c = s[i];
    if (emString) {
      if (c == r'\') {
        i++;
      } else if (c == '"') {
        emString = false;
      }
    } else if (c == '"') {
      emString = true;
    } else if (c == '{') {
      nivel++;
    } else if (c == '}') {
      nivel--;
      if (nivel == 0) return i;
    }
  }
  return -1;
}

/// Restrições da seção `sdks:` de um `pubspec.lock`, por SDK (`dart`, `flutter`).
///
/// É o que o `pub get` gravou: o menor SDK que as dependências resolvidas aceitam.
/// Um lock regenerado por um Flutter mais novo que o pin pede um Dart que o pin não
/// tem — foi o que aconteceu no fechamento do EVAPP-9 e originou o EVAPP-75.
Map<String, String> sdksDoLock(String lock) {
  final sdks = <String, String>{};
  var dentro = false;
  for (final linha in const LineSplitter().convert(lock)) {
    if (linha.trimRight() == 'sdks:') {
      dentro = true;
      continue;
    }
    if (!dentro) continue;
    if (linha.isNotEmpty && !linha.startsWith(' ')) break; // próxima seção
    final m = RegExp(r'^\s+(\w+):\s*"?([^"]*)"?\s*$').firstMatch(linha);
    if (m != null) sdks[m.group(1)!] = m.group(2)!.trim();
  }
  return sdks;
}

/// Null se [versao] atende [restricao] (formato do lock: `>=3.14.0 <4.0.0`, `any`);
/// senão, o motivo em uma frase.
String? violacaoDeRestricao(String versao, String restricao) {
  final v = _partes(versao);
  if (v == null) return 'versão "$versao" ilegível';
  final texto = restricao.trim();
  if (texto.isEmpty || texto == 'any') return null;
  for (final termo in texto.split(RegExp(r'\s+'))) {
    final m = RegExp(r'^(>=|<=|>|<|\^)?(.+)$').firstMatch(termo);
    final limite = m == null ? null : _partes(m.group(2)!);
    if (m == null || limite == null) return 'restrição "$restricao" ilegível';
    final cmp = _comparar(v, limite);
    final ok = switch (m.group(1)) {
      '>=' => cmp >= 0,
      '>' => cmp > 0,
      '<=' => cmp <= 0,
      '<' => cmp < 0,
      '^' => cmp >= 0 && v[0] == limite[0] && (limite[0] > 0 || v[1] == limite[1]),
      _ => cmp == 0,
    };
    if (!ok) return '$versao não atende "$restricao"';
  }
  return null;
}

/// [maior, menor, patch, 1 se versão final / 0 se pré-lançamento] — pré-lançamento
/// vem antes da final (3.18.0-18.0.pre < 3.18.0), como no semver.
List<int>? _partes(String versao) {
  final m = _versaoNumerica.firstMatch(versao.trim());
  if (m == null) return null;
  final numeros = m.group(0)!.split('.').map(int.parse).toList();
  final pre = versao.trim().length > m.group(0)!.length && versao.trim()[m.group(0)!.length] == '-';
  return [...numeros, pre ? 0 : 1];
}

int _comparar(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}
