// Tela (f): log com hora de cada pedido/resposta. "Copiar log" já entrega o VIN com só
// os 3 primeiros caracteres visíveis (a máscara roda também no hex da resposta bruta).

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_estado.dart';

class TelaLog extends StatelessWidget {
  const TelaLog(this.estado, {super.key});
  final AppEstado estado;

  @override
  Widget build(BuildContext context) {
    final e = estado;
    final texto = e.registro.exportar(cabecalho: e.cabecalhoDoLog());
    final linhas = texto.split('\n');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copiar log'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: e.registro.exportar(cabecalho: e.cabecalhoDoLog())));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Log copiado (${linhas.length} linhas, VIN mascarado).')),
                  );
                }
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Compartilhar'),
              onPressed: () => e.transporte.compartilhar(e.registro.exportar(cabecalho: e.cabecalhoDoLog())),
            ),
            TextButton(
              onPressed: e.limparLog,
              child: const Text('Limpar'),
            ),
            Text('${e.registro.entradas.length} entradas'),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: linhas.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(linhas[linhas.length - 1 - i], style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
          ),
        ),
      ],
    );
  }
}
