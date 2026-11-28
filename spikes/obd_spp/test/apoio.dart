// Apoio dos testes: VIN FALSO montado em tempo de execução (o literal de 17 caracteres
// nunca aparece no código, para a varredura de segredos não confundir com VIN real) e
// um transporte falso que imita o ELM327.
import 'dart:async';

import 'package:obd_spp/nucleo/comandos_permitidos.dart';
import 'package:obd_spp/plataforma/transporte_spp.dart';

final String vinFalso = ['LGW', 'TST0ABC', '1234567'].join();

String hexDe(String s) => s.codeUnits.map((c) => c.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');

/// Resposta ATH1 (com espaços) do 0902 com o VIN falso, em 3 quadros ISO-TP.
String respostaVinAth1() {
  final v = vinFalso;
  return '7E8 10 14 49 02 01 ${hexDe(v.substring(0, 3))}\r'
      '7E8 21 ${hexDe(v.substring(3, 10))}\r'
      '7E8 22 ${hexDe(v.substring(10))}\r\r';
}

/// Mesma resposta com ATS0 (sem espaços).
String respostaVinCompacta() => respostaVinAth1().replaceAll(' ', '');

/// Mesma resposta com ATH0 (o adaptador tira o PCI e numera as linhas).
String respostaVinAth0() {
  final v = vinFalso;
  return '014\r0: 49 02 01 ${hexDe(v.substring(0, 3))}\r'
      '1: ${hexDe(v.substring(3, 10))}\r2: ${hexDe(v.substring(10))}\r\r';
}

class TransporteFalso implements TransporteSpp {
  TransporteFalso(this.respostas);

  /// comando normalizado → texto devolvido (sem o `>`; `null` = não responde).
  final Map<String, String?> respostas;
  final escritos = <String>[];
  final _recebidos = StreamController<String>.broadcast();
  final _estados = StreamController<(EstadoConexao, String)>.broadcast();
  Duration atraso = Duration.zero;

  void injetar(String texto) => _recebidos.add(texto);

  @override
  Future<void> escrever(Permitido comando) async {
    escritos.add(comando.bytes);
    final r = respostas[comando.comando];
    if (r == null && respostas.containsKey(comando.comando)) return;
    Timer(atraso, () => _recebidos.add('${r ?? '?'}\r\r>'));
  }

  @override
  Stream<String> get recebidos => _recebidos.stream;
  @override
  Stream<(EstadoConexao, String)> get estados => _estados.stream;
  @override
  Future<String?> pedirPermissoes() async => null;
  @override
  Future<List<AparelhoPareado>> listarPareados() async => [];
  @override
  Future<String> conectar(String endereco) async => 'falso';
  @override
  Future<void> desconectar() async {}
  @override
  Future<void> compartilhar(String texto) async {}
  @override
  Future<void> manterTelaLigada(bool ligar) async {}
}
