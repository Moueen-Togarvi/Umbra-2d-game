/// One authoritative state selects the animation and permitted controller.
/// Interaction constraints and ragdoll always take precedence over locomotion.
///
/// Like LIMBO's boy there is one gait, a run: "starting" and "stopping"
/// cover the moments of picking up and shedding speed. Held down, he
/// crouches and creeps, or sits on the ground.
enum CharacterState {
  idle,
  running,
  starting,
  stopping,
  turning,
  jumpAnticipation,
  jumpAscending,
  jumpApex,
  falling,
  landing,

  /// Sliding down a steep slope on his feet.
  sliding,

  /// Low, creeping along (sit held while moving).
  crouching,

  /// Sitting on the ground (sit held, still).
  sitting,
  pushing,
  pulling,
  grabbing,
  hanging,
  swinging,
  climbing,
  ragdoll,
  recovering,
}
