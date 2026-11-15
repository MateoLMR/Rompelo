import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rompelo_app/features/games/providers/match_result_provider.dart';
import 'package:rompelo_app/features/setup/providers/match_setup_provider.dart';

import 'game_test_utils.dart';

const _peek = ValueKey('impostor-role-peek');

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

/// Pasa el celular por toda la mesa: cada jugador mantiene presionado, mira
/// su rol y lo oculta. Devuelve quiénes vieron "Eres el impostor".
Future<Set<int>> dealAll(WidgetTester tester, int players) async {
  final impostors = <int>{};
  for (var i = 0; i < players; i++) {
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(_peek)));
    await tester.pump();
    if (find.text('Eres el impostor').evaluate().isNotEmpty) {
      impostors.add(i);
    }
    await gesture.up();
    await tester.pump();
    await tapKey(tester, 'impostor-deal-next');
  }
  return impostors;
}

/// Puntaje acumulado de [player] en el marcador del veredicto.
String? scoreText(WidgetTester tester, int player) => tester
    .widget<Text>(find.byKey(ValueKey('impostor-score-$player')))
    .data;

void main() {
  testWidgets('el reparto empieza por el primer jugador con el rol oculto',
      (tester) async {
    await pumpGame(tester, 'impostor');

    expect(find.text('Ronda 1 · Reparto secreto'), findsOneWidget);
    expect(find.text('Jugador 1 de 6'), findsOneWidget);
    expect(find.text('Mateo'), findsOneWidget);
    expect(find.byKey(const ValueKey('impostor-role')), findsNothing);
  });

  testWidgets('el rol solo se ve mientras se mantiene presionado',
      (tester) async {
    await pumpGame(tester, 'impostor');
    final role = find.byKey(const ValueKey('impostor-role'));

    final gesture =
        await tester.startGesture(tester.getCenter(find.byKey(_peek)));
    await tester.pump();
    expect(role, findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(role, findsNothing);
  });

  testWidgets('no se puede pasar el celular sin haber mirado el rol',
      (tester) async {
    await pumpGame(tester, 'impostor');

    await tapKey(tester, 'impostor-deal-next');
    expect(find.text('Jugador 1 de 6'), findsOneWidget);
  });

  testWidgets('hay exactamente un impostor y todos ven su rol',
      (tester) async {
    await pumpGame(tester, 'impostor');
    final impostors = await dealAll(tester, 6);

    expect(impostors, hasLength(1));
    expect(find.text('Ronda 1 · Debate en vivo'), findsOneWidget);
    expect(find.text('03:00'), findsOneWidget); // 3 min por defecto
    expect(find.text('Fase secreta completada'), findsOneWidget);
  });

  testWidgets('con 2 impostores el reparto asigna dos', (tester) async {
    await pumpGame(
      tester,
      'impostor',
      prepare: (c) => c.read(impostorSetupProvider.notifier).setImpostors(2),
    );
    expect(await dealAll(tester, 6), hasLength(2));
  });

  testWidgets('"Siguiente turno" rota quién pregunta', (tester) async {
    await pumpGame(tester, 'impostor');
    await dealAll(tester, 6);

    final before = tester
        .widget<Text>(find.byKey(const ValueKey('impostor-turn')))
        .data;
    await tester.tap(find.text('Siguiente turno'));
    await tester.pumpAndSettle();
    final after = tester
        .widget<Text>(find.byKey(const ValueKey('impostor-turn')))
        .data;
    expect(after, isNot(before));
  });

  testWidgets('"¿Olvidaste tu palabra?" abre un visor privado',
      (tester) async {
    await pumpGame(tester, 'impostor');
    await dealAll(tester, 6);

    await tapKey(tester, 'impostor-forgot');
    await tapKey(tester, 'forgot-0');
    final role = find.byKey(const ValueKey('impostor-private-role'));
    expect(role, findsNothing);

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('impostor-private-peek'))));
    await tester.pump();
    expect(role, findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(role, findsNothing);
  });

  testWidgets('revelar sin acusados muestra un aviso', (tester) async {
    await pumpGame(tester, 'impostor');
    await dealAll(tester, 6);
    await tapKey(tester, 'impostor-go-vote');

    await tapKey(tester, 'impostor-reveal');
    expect(find.text('Elijan a una persona para acusar'), findsOneWidget);
  });

  testWidgets('con 1 impostor tocar a otro cambia la acusación',
      (tester) async {
    await pumpGame(tester, 'impostor');
    await dealAll(tester, 6);
    await tapKey(tester, 'impostor-go-vote');

    await tapKey(tester, 'suspect-0');
    await tapKey(tester, 'suspect-1');
    expect(find.text('Acusado'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
  });

  testWidgets('atrapan al impostor y no adivina: ganan los ciudadanos',
      (tester) async {
    final container = await pumpGame(tester, 'impostor');
    final impostor = (await dealAll(tester, 6)).single;
    await tapKey(tester, 'impostor-go-vote');
    await tapKey(tester, 'suspect-$impostor');
    await tapKey(tester, 'impostor-reveal');

    expect(find.text('¡Atraparon al impostor!'), findsOneWidget);
    await tapKey(tester, 'impostor-guess-no');
    expect(find.text('¡Ganan los ciudadanos!'), findsOneWidget);

    await tapKey(tester, 'impostor-finish');
    expect(currentPath(container), '/resultados');
    final result = container.read(lastMatchResultProvider)!;
    expect(result.summary, '¡Atraparon al impostor!');
    expect(result.plays, 1);
    final impostorName = container.read(impostorSetupProvider).playerNames[impostor];
    expect(result.scores.firstWhere((s) => s.name == impostorName).points, 0);
    expect(result.scores.first.points, 1);
  });

  testWidgets('atrapado pero adivina la palabra: el impostor gana 3',
      (tester) async {
    await pumpGame(tester, 'impostor');
    final impostor = (await dealAll(tester, 6)).single;
    await tapKey(tester, 'impostor-go-vote');
    await tapKey(tester, 'suspect-$impostor');
    await tapKey(tester, 'impostor-reveal');
    await tapKey(tester, 'impostor-guess-yes');

    expect(find.text('¡Lo atraparon, pero adivinó!'), findsOneWidget);
    expect(scoreText(tester, impostor), '3');
  });

  testWidgets('acusar a un inocente: el impostor escapa con 2 puntos',
      (tester) async {
    await pumpGame(tester, 'impostor');
    final impostor = (await dealAll(tester, 6)).single;
    final innocent = (impostor + 1) % 6;
    await tapKey(tester, 'impostor-go-vote');
    await tapKey(tester, 'suspect-$innocent');
    await tapKey(tester, 'impostor-reveal');

    expect(find.text('¡El impostor escapó!'), findsOneWidget);
    expect(scoreText(tester, impostor), '2');
  });

  testWidgets('"Otra ronda" reparte de nuevo y acumula el marcador',
      (tester) async {
    final container = await pumpGame(tester, 'impostor');

    for (var round = 1; round <= 2; round++) {
      expect(find.text('Ronda $round · Reparto secreto'), findsOneWidget);
      final impostor = (await dealAll(tester, 6)).single;
      await tapKey(tester, 'impostor-go-vote');
      await tapKey(tester, 'suspect-${(impostor + 1) % 6}'); // inocente
      await tapKey(tester, 'impostor-reveal');
      if (round == 1) await tapKey(tester, 'impostor-next-round');
    }

    await tapKey(tester, 'impostor-finish');
    final result = container.read(lastMatchResultProvider)!;
    expect(result.plays, 2);
    expect(result.detail, '2 rondas');
    expect(result.totalPoints, 4); // 2 rondas × 2 puntos del impostor
    expect(result.awards.first.title, 'El mejor farsante');
  });

  testWidgets('"Salir" pide confirmación y vuelve al home', (tester) async {
    final container = await pumpGame(tester, 'impostor');
    await expectExitWithConfirmation(tester, container);
  });
}
