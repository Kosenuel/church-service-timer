/// A simulator must never be presented as a connected physical display.
enum DisplayConnection {
  simulator('Simulator'),
  connected('Display connected'),
  stageConnected('Stage screen · Connected'),
  stageWaiting('Waiting for a screen'),
  stageDisconnected('Stage screen · Disconnected'),
  disconnected('Disconnected');

  final String label;
  const DisplayConnection(this.label);

  static DisplayConnection fromAdapter({
    required bool simulated,
    required bool connected,
  }) => !connected
      ? disconnected
      : simulated
      ? simulator
      : DisplayConnection.connected;
}
