// Estado do app do spike: conexão, sessão ELM, log e o relógio dos 30 minutos no carro.

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'elm/sessao_elm.dart';
import 'nucleo/registro.dart';
import 'plataforma/transporte_spp.dart';

class AppEstado extends ChangeNotifier {
  AppEstado(this.transporte) {
    sessao = SessaoElm(transporte, registro)..aoMudar = notifyListeners;
    _assinatura = transporte.estados.listen((e) {
      final (estado, motivo) = e;
      if (estado == EstadoConexao.desconectado && conexao != EstadoConexao.desconectado) {
        registro.adicionar(Entrada(DateTime.now(), Sentido.nota, 'desconectado: $motivo'));
        _pararRelogio();
      }
      conexao = estado;
      motivoConexao = motivo;
      notifyListeners();
    });
  }

  final TransporteSpp transporte;
  final registro = Registro();
  late final SessaoElm sessao;
  late final StreamSubscription<(EstadoConexao, String)> _assinatura;

  EstadoConexao conexao = EstadoConexao.desconectado;
  String motivoConexao = '';
  List<AparelhoPareado> pareados = [];
  AparelhoPareado? aparelho;
  String? erro;
  DateTime? conectadoDesde;
  Timer? _relogio;

  /// Mostrar o VIN completo NA TELA (o log exportado é sempre mascarado).
  bool mostrarVin = false;

  /// Algum laço (sequência, taxa, varredura) em execução.
  bool ocupado = false;

  Duration get tempoConectado =>
      conectadoDesde == null ? Duration.zero : DateTime.now().difference(conectadoDesde!);

  Future<void> buscarPareados() async {
    erro = null;
    notifyListeners();
    try {
      final negado = await transporte.pedirPermissoes();
      if (negado != null) {
        erro = 'Permissão: $negado. Abra Configurações → Apps → spike OBD → Permissões → '
            'Dispositivos próximos → Permitir.';
      } else {
        pareados = await transporte.listarPareados();
        if (pareados.isEmpty) erro = 'Nenhum aparelho pareado. Pareie o KONNWEI nas configurações de Bluetooth.';
      }
    } catch (e) {
      erro = '$e';
    }
    notifyListeners();
  }

  Future<void> conectar(AparelhoPareado a) async {
    aparelho = a;
    erro = null;
    conexao = EstadoConexao.conectando;
    notifyListeners();
    final t0 = DateTime.now();
    registro.adicionar(Entrada(t0, Sentido.nota, 'conectando a ${a.nome} (${a.tipo})'));
    try {
      final modo = await transporte.conectar(a.endereco);
      final ms = DateTime.now().difference(t0).inMilliseconds;
      registro.adicionar(Entrada(DateTime.now(), Sentido.nota, 'conectado ($modo) em $ms ms'));
      conexao = EstadoConexao.conectado;
      conectadoDesde = DateTime.now();
      _relogio?.cancel();
      _relogio = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
      await transporte.manterTelaLigada(true);
    } catch (e) {
      erro = '$e';
      conexao = EstadoConexao.desconectado;
      registro.adicionar(Entrada(DateTime.now(), Sentido.nota, 'falha ao conectar: $e'));
    }
    notifyListeners();
  }

  Future<void> desconectar() async {
    if (sessao.monitorando) await sessao.pararMonitor();
    await transporte.desconectar();
    _pararRelogio();
    conexao = EstadoConexao.desconectado;
    notifyListeners();
  }

  void _pararRelogio() {
    _relogio?.cancel();
    _relogio = null;
    conectadoDesde = null;
    transporte.manterTelaLigada(false);
  }

  void alternarVin() {
    mostrarVin = !mostrarVin;
    notifyListeners();
  }

  void limparLog() {
    registro.limpar();
    notifyListeners();
  }

  void definirOcupado(bool v) {
    ocupado = v;
    notifyListeners();
  }

  String cabecalhoDoLog() =>
      'aparelho: ${aparelho?.nome ?? '-'} (${aparelho?.tipo ?? '-'}); exportado ${DateTime.now().toIso8601String()}';

  @override
  void dispose() {
    _assinatura.cancel();
    _relogio?.cancel();
    sessao.fechar();
    super.dispose();
  }
}
