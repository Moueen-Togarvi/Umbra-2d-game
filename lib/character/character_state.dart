/// One authoritative state selects the animation and permitted controller.
/// Interaction constraints and ragdoll always take precedence over locomotion.
///
/// Like LIMBO's boy there is one gait, a run, and no crouch: "starting" and
/// "stopping" cover the moments of picking up and shedding speed.
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
  pushing,
  pulling,
  grabbing,
  hanging,
  swinging,
  climbing,
  ragdoll,
  recovering,
}
