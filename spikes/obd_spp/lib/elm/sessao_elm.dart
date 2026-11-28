// Sessão com o ELM327: um pedido por vez, espera o prompt `>` com limite de tempo,
// interpreta, decodifica, passa pelo filtro de plausibilidade e grava no log.
//
// Todo pedido passa por `avaliar()` (lista de comandos permitidos) antes de chegar ao
// transporte; o transporte só aceita um `Permitido`.

import 'dart:async';

import '../nucleo/comandos_permitidos.dart';
import '../nucleo/decodificadores.dart';
import '../nucleo/plausibilidade.dart';
import '../nucleo/registro.dart';
import '../nucleo/resposta_elm.dart';
import '../plataforma/transporte_spp.dart';

/// Um pedido e o que voltou.
class Troca {
  Troca(this.veredito, this.inicio);
  final Veredito veredito;
  final DateTime inicio;
  RespostaElm? resposta;
  int latenciaMs = 0;
  List<Leitura> leituras = const [];

  /// Recusa da lista, timeout, ou erro do transporte.
  String? falha;

  bool get recusada => veredito is Recusado;

  /// Veio pelo menos uma resposta positiva decodificável.
  bool get sucesso =>
      falha == null &&
      resposta != null &&
      resposta!.mensagens.any((m) => !m.negativa) &&
      resposta!.erro == null;

  /// Algum valor marcado pelo filtro.
  bool get suspeita => leituras.any((l) => l.suspeita != null);
}

class SessaoElm {
  SessaoElm(this.transporte, this.registro, {DateTime Function()? relogio})
      : _agora = relogio ?? DateTime.now {
    _assinatura = transporte.recebidos.listen(_aoReceber);
  }

  final TransporteSpp transporte;
  final Registro registro;
  final DateTime Function() _agora;
  final filtro = FiltroPlausibilidade();

  late final StreamSubscription<String> _assinatura;
  final _buffer = StringBuffer();
  Completer<String>? _aguardando;
  Completer<void>? _promptAtrasado;
  Future<void> _fila = Future.value();

  /// Cabeçalho ativo (o que o último ATSH pôs; o ATZ volta ao 7DF).
  String cabecalho = '7DF';

  /// Monitor (ATMA) ligado.
  bool monitorando = false;

  /// Linhas recebidas durante o ATMA.
  void Function(String linha)? aoLinhaMonitor;

  /// Chamado a cada mudança (para a tela redesenhar).
  void Function()? aoMudar;

  void fechar() => _assinatura.cancel();

  /// Envia [texto] e espera a resposta. Nunca lança: falhas voltam em [Troca.falha].
  Future<Troca> enviar(String texto, {Duration limite = const Duration(seconds: 5)}) {
    final r = _fila.then((_) => _enviar(texto, limite));
    _fila = r.then((_) {}, onError: (_) {});
    return r;
  }

  Future<Troca> _enviar(String texto, Duration limite) async {
    final v = avaliar(texto);
    final troca = Troca(v, _agora());
    if (v is Recusado) {
      troca.falha = 'RECUSADO: ${v.motivo}';
      registro.adicionar(Entrada(troca.inicio, Sentido.recusa, '"${v.digitado}" — ${v.motivo}'));
      aoMudar?.call();
      return troca;
    }
    final p = v as Permitido;
    if (monitorando) {
      troca.falha = 'monitor (ATMA) ligado: pare o monitor antes';
      registro.adicionar(Entrada(troca.inicio, Sentido.recusa, '"${p.comando}" — ${troca.falha}'));
      aoMudar?.call();
      return troca;
    }

    // Resposta atrasada de um pedido que deu timeout: espera o `>` dela antes de seguir,
    // para não confundir com a resposta deste pedido.
    final atrasado = _promptAtrasado;
    if (atrasado != null) {
      await atrasado.future.timeout(const Duration(seconds: 1), onTimeout: () {});
      _promptAtrasado = null;
    }
    _buffer.clear();

    registro.adicionar(Entrada(troca.inicio, Sentido.pedido, '${p.comando}   [${p.categoria}]'));
    if (p.abreMonitor) {
      monitorando = true;
      _linhaMonitor.clear();
      try {
        await transporte.escrever(p);
      } catch (e) {
        monitorando = false;
        troca.falha = 'erro ao escrever: $e';
      }
      aoMudar?.call();
      return troca;
    }

    final aguardando = Completer<String>();
    _aguardando = aguardando;
    try {
      await transporte.escrever(p);
    } catch (e) {
      _aguardando = null;
      troca.falha = 'erro ao escrever: $e';
      registro.adicionar(Entrada(_agora(), Sentido.nota, troca.falha!));
      aoMudar?.call();
      return troca;
    }

    String bruta;
    try {
      bruta = await aguardando.future.timeout(limite);
    } on TimeoutException {
      _aguardando = null;
      _promptAtrasado = Completer<void>();
      troca.latenciaMs = _agora().difference(troca.inicio).inMilliseconds;
      troca.falha = 'TIMEOUT após ${limite.inMilliseconds} ms (parcial: "${_buffer.toString().trim()}")';
      registro.adicionar(Entrada(_agora(), Sentido.resposta, troca.falha!, latenciaMs: troca.latenciaMs));
      aoMudar?.call();
      return troca;
    }
    troca.latenciaMs = _agora().difference(troca.inicio).inMilliseconds;

    final resposta = interpretar(bruta, comando: p.comando);
    troca.resposta = resposta;
    registro.adicionar(Entrada(_agora(), Sentido.resposta, bruta.trim(), latenciaMs: troca.latenciaMs));

    if (p.comando == 'ATZ') cabecalho = '7DF';
    if (p.comando.startsWith('ATSH')) cabecalho = p.comando.substring(4);

    final leituras = decodificar(p.comando, resposta);
    final quando = _agora();
    for (final l in leituras) {
      for (final MapEntry(key: sinal, value: valor) in l.valores.entries) {
        l.suspeita ??= filtro.avaliar(sinal, valor, quando);
      }
      registro.adicionar(Entrada(quando, Sentido.decodificado, l.toString()));
    }
    troca.leituras = leituras;
    aoMudar?.call();
    return troca;
  }

  /// Encerra o ATMA (um espaço, sem CR) e espera o prompt.
  Future<Troca> pararMonitor() {
    final r = _fila.then((_) async {
      final p = encerrarMonitor();
      final troca = Troca(p, _agora());
      if (!monitorando) {
        troca.falha = 'monitor não está ligado';
        return troca;
      }
      _buffer.clear();
      final aguardando = Completer<String>();
      _aguardando = aguardando;
      registro.adicionar(Entrada(troca.inicio, Sentido.pedido, '${p.comando}   [${p.categoria}]'));
      try {
        await transporte.escrever(p);
        final bruta = await aguardando.future.timeout(const Duration(seconds: 3));
        troca.latenciaMs = _agora().difference(troca.inicio).inMilliseconds;
        registro.adicionar(Entrada(_agora(), Sentido.resposta, bruta.trim(), latenciaMs: troca.latenciaMs));
      } on TimeoutException {
        _aguardando = null;
        troca.falha = 'o adaptador não devolveu o prompt depois de parar o monitor';
        registro.adicionar(Entrada(_agora(), Sentido.nota, troca.falha!));
      } catch (e) {
        troca.falha = 'erro ao escrever: $e';
      }
      monitorando = false;
      aoMudar?.call();
      return troca;
    });
    _fila = r.then((_) {}, onError: (_) {});
    return r;
  }

  final _linhaMonitor = StringBuffer();

  void _aoReceber(String pedaco) {
    if (monitorando && _aguardando == null) {
      for (final c in pedaco.split('')) {
        if (c == '\r' || c == '\n') {
          final l = _linhaMonitor.toString().trim();
          _linhaMonitor.clear();
          if (l.isNotEmpty) {
            registro.adicionar(Entrada(_agora(), Sentido.resposta, l));
            aoLinhaMonitor?.call(l);
          }
        } else if (c != '>') {
          _linhaMonitor.write(c);
        }
      }
      aoMudar?.call();
      return;
    }
    _buffer.write(pedaco);
    final s = _buffer.toString();
    final fim = s.indexOf('>');
    if (fim < 0) return;
    final a = _aguardando;
    if (a != null) {
      _aguardando = null;
      _buffer.clear();
      a.complete(s.substring(0, fim));
    } else {
      // prompt sem ninguém esperando: era a resposta atrasada de um timeout
      registro.adicionar(Entrada(_agora(), Sentido.nota, 'resposta atrasada descartada: ${s.substring(0, fim).trim()}'));
      _buffer.clear();
      _promptAtrasado?.complete();
      _promptAtrasado = null;
    }
  }
}
