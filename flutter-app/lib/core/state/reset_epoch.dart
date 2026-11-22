/// Lets a long-lived object ignore answers to requests it made before a reset.
/// Capture [resetEpoch] before an await and drop the result if [isStale]
/// afterwards: a sign-out or account switch bumps it, so a slow response for
/// the previous learner never lands in the next learner's state.
mixin ResetEpoch {
  int _resetEpoch = 0;

  int get resetEpoch => _resetEpoch;

  bool isStale(int epoch) => epoch != _resetEpoch;

  /// Call from `reset()` before clearing state.
  void bumpResetEpoch() => _resetEpoch++;
}
