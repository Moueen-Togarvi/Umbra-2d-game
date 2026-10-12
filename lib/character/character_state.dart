/// One authoritative state selects the animation and permitted controller.
/// Interaction constraints and ragdoll always take precedence over locomotion.
enum CharacterState {
  idle,
  walking,
  running,
  starting,
  stopping,
  turning,
  jumpAnticipation,
  jumpAscending,
  jumpApex,
  falling,
  landing,
  crouching,
  pushing,
  pulling,
  grabbing,
  hanging,
  swinging,
  climbing,
  ragdoll,
  recovering,
}
