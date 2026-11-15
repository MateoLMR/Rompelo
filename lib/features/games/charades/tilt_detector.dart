import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Detecta el gesto de Charadas con el móvil en la frente (pantalla hacia
/// el grupo) usando el acelerómetro:
///
/// - **Hacia abajo** (la pantalla mira al piso, `z` muy negativo) → [onDown]
///   (Acierto).
/// - **Hacia arriba** (la pantalla mira al techo, `z` muy positivo) →
///   [onUp] (Pasar).
///
/// Tras un gesto hay que volver a la posición neutra (frente, `z` cerca de
/// 0) para que cuente el siguiente: así un solo movimiento no dispara dos
/// cartas. Funciona igual en vertical u horizontal porque solo mira el eje
/// que sale de la pantalla.
class TiltDetector extends StatefulWidget {
  const TiltDetector({
    super.key,
    required this.enabled,
    required this.onDown,
    required this.onUp,
    required this.child,
  });

  /// Solo escucha el sensor mientras es `true` (fase de juego, sin pausa).
  final bool enabled;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final Widget child;

  /// Umbral del gesto y de "volver a neutro", en m/s² (gravedad ≈ 9,8).
  static const double triggerZ = 7;
  static const double neutralZ = 4;

  /// Tiempo mínimo entre dos gestos.
  static const Duration cooldown = Duration(milliseconds: 700);

  @override
  State<TiltDetector> createState() => _TiltDetectorState();
}

class _TiltDetectorState extends State<TiltDetector> {
  StreamSubscription<AccelerometerEvent>? _subscription;

  /// `false` hasta que el móvil vuelve a la frente tras un gesto. Empieza en
  /// `false`: el turno arranca con el móvil en la mano, no en la frente.
  bool _armed = false;
  DateTime _lastGesture = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TiltDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  void _sync() {
    if (widget.enabled && _subscription == null) {
      _armed = false;
      _subscription = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(
        _onEvent,
        // Sin acelerómetro (emulador, algunos equipos): quedan los botones.
        onError: (Object _) => _stop(),
        cancelOnError: true,
      );
    } else if (!widget.enabled) {
      _stop();
    }
  }

  void _stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _onEvent(AccelerometerEvent event) {
    final z = event.z;
    if (z.abs() < TiltDetector.neutralZ) {
      _armed = true;
      return;
    }
    if (!_armed) return;
    final now = DateTime.now();
    if (now.difference(_lastGesture) < TiltDetector.cooldown) return;

    if (z <= -TiltDetector.triggerZ) {
      _fire(now, widget.onDown);
    } else if (z >= TiltDetector.triggerZ) {
      _fire(now, widget.onUp);
    }
  }

  void _fire(DateTime now, VoidCallback callback) {
    _armed = false;
    _lastGesture = now;
    callback();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
