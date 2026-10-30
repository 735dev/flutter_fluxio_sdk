import 'package:flutter/widgets.dart';

import 'join.dart';
import 'snapshot.dart';

/// Room transport. Tests supply a fake. The LiveKit implementation is the
/// production one and is the only place that imports `livekit_client`.
abstract class FluxioEngine {
  Future<void> open(FluxioJoin join);

  Future<void> setMicrophone(bool enabled);

  Future<void> setCamera(bool enabled);

  /// User hang-up. Reports [FluxioDisconnect.clientLeave], not a drop.
  Future<void> close();

  Stream<FluxioSnapshot> get changes;

  /// Camera view for [identity], or null when that person has no picture.
  Widget? cameraView(String identity);
}
