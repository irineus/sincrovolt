// Interface Dart do Bluetooth Clássico (SPP) e a implementação pelo canal de plataforma
// próprio em Kotlin (MainActivity.kt). Decisão EVAPP-24: nada de pacote de terceiros.
//
// O método de escrita recebe um [Permitido], não uma String: o único jeito de mandar
// algo ao adaptador é passar pela lista de comandos permitidos.

import 'dart:async';

import 'package:flutter/services.dart';

import '../nucleo/comandos_permitidos.dart';

class AparelhoPareado {
  AparelhoPareado(this.nome, this.endereco, this.tipo);
  final String nome;
  final String endereco;

  /// `classico`, `le`, `duplo` ou `desconhecido` (BluetoothDevice.getType()).
  final String tipo;
}

enum EstadoConexao { desconectado, conectando, conectado }

abstract class TransporteSpp {
  /// Pede BLUETOOTH_CONNECT e BLUETOOTH_SCAN (Android 12+). `null` = concedidas;
  /// senão, o motivo.
  Future<String?> pedirPermissoes();

  Future<List<AparelhoPareado>> listarPareados();

  /// Conecta por RFCOMM ao UUID SPP 00001101-0000-1000-8000-00805F9B34FB.
  /// Devolve o modo que funcionou (seguro/inseguro).
  Future<String> conectar(String endereco);

  Future<void> desconectar();

  /// Texto recebido do adaptador, em pedaços como chegam do socket.
  Stream<String> get recebidos;

  /// Mudanças de estado vindas do lado nativo (ex.: socket caiu).
  Stream<(EstadoConexao, String)> get estados;

  /// Escreve no socket. Só aceita o que a lista permitiu.
  Future<void> escrever(Permitido comando);

  /// Abre o "Compartilhar" do Android com o texto (para salvar o log em arquivo).
  Future<void> compartilhar(String texto);

  /// Mantém a tela ligada enquanto conectado.
  Future<void> manterTelaLigada(bool ligar);
}

class TransporteKotlin implements TransporteSpp {
  static const _metodos = MethodChannel('sincrovolt.spike/spp');
  static const _eventos = EventChannel('sincrovolt.spike/spp/eventos');

  final _recebidos = StreamController<String>.broadcast();
  final _estados = StreamController<(EstadoConexao, String)>.broadcast();
  StreamSubscription<dynamic>? _assinatura;

  TransporteKotlin() {
    _assinatura = _eventos.receiveBroadcastStream().listen((e) {
      final m = Map<String, dynamic>.from(e as Map);
      if (m['tipo'] == 'dados') {
        _recebidos.add(m['texto'] as String);
      } else if (m['tipo'] == 'estado') {
        final s = switch (m['estado']) {
          'conectado' => EstadoConexao.conectado,
          'conectando' => EstadoConexao.conectando,
          _ => EstadoConexao.desconectado,
        };
        _estados.add((s, (m['motivo'] as String?) ?? ''));
      }
    });
  }

  @override
  Future<String?> pedirPermissoes() async => _metodos.invokeMethod<String?>('pedirPermissoes');

  @override
  Future<List<AparelhoPareado>> listarPareados() async {
    final lista = await _metodos.invokeListMethod<dynamic>('listarPareados') ?? [];
    return [
      for (final x in lista)
        AparelhoPareado(
          (x as Map)['nome'] as String? ?? '(sem nome)',
          x['endereco'] as String,
          x['tipo'] as String? ?? 'desconhecido',
        ),
    ];
  }

  @override
  Future<String> conectar(String endereco) async =>
      await _metodos.invokeMethod<String>('conectar', {'endereco': endereco}) ?? '';

  @override
  Future<void> desconectar() => _metodos.invokeMethod<void>('desconectar');

  @override
  Stream<String> get recebidos => _recebidos.stream;

  @override
  Stream<(EstadoConexao, String)> get estados => _estados.stream;

  @override
  Future<void> escrever(Permitido comando) =>
      _metodos.invokeMethod<void>('escrever', {'texto': comando.bytes});

  @override
  Future<void> compartilhar(String texto) =>
      _metodos.invokeMethod<void>('compartilhar', {'texto': texto});

  @override
  Future<void> manterTelaLigada(bool ligar) =>
      _metodos.invokeMethod<void>('manterTelaLigada', {'ligar': ligar});

  void fechar() {
    _assinatura?.cancel();
    _recebidos.close();
    _estados.close();
  }
}
