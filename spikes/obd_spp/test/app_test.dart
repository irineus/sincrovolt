import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obd_spp/app_estado.dart';
import 'package:obd_spp/main.dart';

import 'apoio.dart';

void main() {
  testWidgets('abre nas seis abas, desconectado', (tester) async {
    await tester.pumpWidget(SpikeApp(AppEstado(TransporteFalso({}))));
    for (final aba in ['a. Conectar', 'b. Sequência', 'c. Console', 'd. Taxa', 'e. Varredura', 'f. Log']) {
      expect(find.text(aba), findsOneWidget);
    }
    expect(find.text('spike OBD · desconectado'), findsOneWidget);
    expect(find.text('Permissões e pareados'), findsOneWidget);
    await tester.ensureVisible(find.text('e. Varredura'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('e. Varredura'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Só modo 22'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Iniciar')).onPressed, isNull);
  });
}
