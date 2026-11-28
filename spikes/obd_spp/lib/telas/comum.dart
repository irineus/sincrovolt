import 'package:material_ui/material_ui.dart';

import '../elm/sessao_elm.dart';
import '../nucleo/comandos_permitidos.dart';
import '../nucleo/mascara_vin.dart';

const _mono = TextStyle(fontFamily: 'monospace', fontSize: 12);

/// Cartão de um pedido: resposta bruta + decodificada, falha e suspeita bem visíveis.
class CartaoTroca extends StatelessWidget {
  const CartaoTroca(this.troca, {super.key, required this.mostrarVin});

  final Troca troca;
  final bool mostrarVin;

  String _m(String s) => mostrarVin ? s : mascararTudo(s);

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final v = troca.veredito;
    final comando = v is Permitido ? v.comando : v.digitado;
    final bruta = troca.resposta?.bruta.trim().replaceAll(RegExp(r'[\r\n]+'), '\n');
    return Card(
      color: troca.falha != null ? cores.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(comando, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                const Spacer(),
                if (!troca.recusada) Text('${troca.latenciaMs} ms', style: _mono),
              ],
            ),
            if (troca.falha != null)
              Text(troca.falha!, style: TextStyle(color: cores.onErrorContainer, fontWeight: FontWeight.bold)),
            if (bruta != null && bruta.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText(_m(bruta), style: _mono),
            ],
            for (final l in troca.leituras)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${l.ecu} ${l.sinal}: ${_m(l.texto)}${l.suspeita == null ? '' : '\n⚠ SUSPEITA: ${l.suspeita}'}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: l.suspeita == null ? null : Colors.deepOrange,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Faixa vermelha de "pare": usada pela varredura e pelo aviso dos 30 minutos.
class Alerta extends StatelessWidget {
  const Alerta(this.texto, {super.key, this.cor = Colors.red});
  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: cor,
        padding: const EdgeInsets.all(12),
        child: Text(texto, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      );
}

String mmss(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
