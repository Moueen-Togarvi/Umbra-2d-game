# Step 1 — Notes: moving to a real physics engine

Reference material for the Umbra codebase. Read this when something in the
physics layer looks surprising.

## Why a physics engine at all

A hand-rolled platformer loop looks like this:

```dart
velocity.y += gravity * dt;      // integrate
position   += velocity * dt;     // move
if (overlapsFloor(position)) {   // resolve, by hand
  position.y = floorTop - height;
  velocity.y = 0;
}
```

This is fine, and it is honestly the right way to build a first prototype. Its
limit is that every interaction has to be invented. It knows about the floor
because you wrote a floor case. Add a crate and you write a crate case; add a
crate resting on another crate and you write a stacking case; add a rope and you
are writing a constraint solver.

Box2D inverts this. You stop describing *what happens* and start describing
*what things are*: this body has this shape, this mass, this friction. Once
described, everything interacts with everything else for free. That is the only
reason Steps 2–4 (crate, rope, buoyancy) are tractable at all — they are the
same solver doing the same job with different descriptions.

The cost is control. A hand-rolled loop does exactly what you typed. A solver
does what the constraints imply, which is occasionally not what you wanted, and
tuning it is a different skill. Most of the comments in `entities/player.dart`
are about that tension.

## The units problem (this trips up everyone)

**Box2D is tuned for metres, kilograms and seconds.** Not pixels.

Several of its internal tolerances are *absolute lengths* rather than fractions
of the objects they apply to:

| Tolerance | Value | What it does |
|---|---|---|
| `linearSlop` | 0.005 m | Allowed overlap, so resting contacts stay stable |
| `speculativeDistance` | 0.02 m | Distance at which a contact is first reported |
| `aabbMargin` | 0.05 m | How much the broadphase fattens shape bounds |

Those numbers are invisible when a person is 1.6 units tall. They are
catastrophic when a person is 160 units tall, because then everything else is
scaled up too and the tolerances are relatively 100× smaller — or, more commonly,
when someone lays a world out in pixels at 1 unit = 1 pixel and makes a player
40×80 units in a world where gravity is 980. The symptoms are strange and hard
to attribute:

- `beginContact` fires while there is still a visible gap
- bodies never bounce
- bodies fall asleep while still visibly moving
- stacks jitter and slowly sink into each other

The guidance is to keep moving bodies roughly **0.1 m to 10 m**. Umbra's player
is 1.6 m tall because a person is. `flame_forge2d` will print a debug warning if
a moving body is small enough for the tolerances to dominate it — if you ever
see that warning, the fix is the layout, not the tolerance.

Pixels enter at exactly one place: `GameConfig.metersToPixels`, which the camera
uses when drawing. Change it and the game looks bigger; the simulation is
bit-for-bit identical.

Note that this is *separate* from the camera's `zoom`. Older versions of
flame_forge2d overloaded `zoom` to mean world scale, which conflated "how big is
a metre" with "how far is the camera zoomed in". `Forge2DViewfinder` splits them:
`metersToPixels` is the world scale, `zoom` is free for camera work.

## Axis direction

Flame's y-axis points **down** the screen. `flame_forge2d` follows that
convention, so:

- gravity is `(0, +28)`, not `(0, -28)`
- jumping sets a **negative** y velocity
- `Forge2DWorld.defaultGravity` is `(0, 10)`

Raw Box2D uses y-up and would write all of these with the opposite sign. If you
are reading a Box2D tutorial, flip every vertical sign you see.

## API: flame_forge2d 0.20 is not the version in the tutorials

Version 0.20.0 replaced the pure-Dart port of Box2D 2.x with bindings to the
native **Box2D v3** library. Essentially every tutorial, Stack Overflow answer,
and blog post you will find online predates this. Translation table:

| Old (≤ 0.19, what you'll find online) | New (0.20, what this code uses) |
|---|---|
| `FixtureDef` | `ShapeDef` |
| `PolygonShape()..setAsBox(hw, hh)` | `Polygon.box(hw, hh)` |
| `body.createFixture(fixtureDef)` | `body.createShape(geometry, shapeDef)` |
| `fixtureDef.friction = 0.3` | `ShapeDef(material: SurfaceMaterial(friction: 0.3))` |
| `Forge2DGame(zoom: 10)` | `Forge2DGame(metersToPixels: 100)` |
| `beginContact(Object other, Contact c)` on the body | same, but contacts are *polled after* each step |
| `preSolve` / `postSolve` callbacks | `Forge2DWorld.preSolveCallback`, hit events |
| (synchronous startup) | `await initializeForge2D()` — mandatory |

Two consequences worth internalising:

1. **`await super.onLoad()` must come first** in any `Forge2DGame` subclass.
   On the web that call fetches and instantiates the Box2D WebAssembly module,
   and creating a body before it finishes throws. Native builds are synchronous,
   so forgetting it produces code that works on desktop and dies on web.

2. **Box dimensions are half-extents.** A 0.8 × 1.6 m player is
   `Polygon.box(0.4, 0.8)`. Getting this wrong gives you a body exactly twice
   the size it should be, which looks almost plausible and wastes an afternoon.

## Sensors, and the one line everybody forgets

A *sensor* is a shape that takes part in collision detection but not collision
response: things pass through it and the engine tells you about it. Umbra uses
sensors twice already, and will use them again for water in Step 4:

- the player's **foot sensor**, to answer "am I standing on something?"
- the **hazard**, as a trigger volume

The trap: **Box2D v3 only reports events for shapes that opted in, on both
sides of the contact.** A sensor with `enableSensorEvents: true` will still see
nothing if the shape walking into it did not also set it. This is why
`Ground` sets `enableSensorEvents: true` even though ground is not a sensor,
and why the player's body shape sets it too.

`BodyComponent` sets those flags for you *only* when the userData is a
`ContactCallbacks`, which is why `Hazard` gets them automatically and `Ground`
has to ask.

### Why the foot sensor counts instead of using a boolean

The feet can touch two things at once — the seam between two floor slabs, or a
crate and the floor. With a boolean, stepping off one of the two would wrongly
report the player as airborne. A counter handles it.

### Why the foot sensor filters out its own player

`ContactEventsDispatcher` gathers the userData of **both bodies and both
shapes** involved in a contact, then notifies each `ContactCallbacks` once per
*other* participant. The foot sensor lives on the player's own body, so every
ground contact notifies it twice: once about the ground, once about the player
who owns it. Without the `identical(other, owner)` filter, every increment is
doubled.

## Why moving the player on a contact callback is safe

`Forge2DWorld.update` steps the physics world **and then** dispatches the events
that step produced. By the time `Hazard.beginContact` runs, the solver has
finished and the world is safe to mutate. This is not true of every physics
engine — many require you to defer such changes to the end of the frame — so it
is worth knowing why it is fine here rather than assuming it always is.

## Tuning the jump

Don't guess a "jump force". Pick the apex height you want in metres
(`GameConfig.jumpApexMeters`) and let kinematics give you the take-off speed:

```
h = v² / (2g)   →   v = √(2gh)
```

That is `GameConfig.jumpTakeoffSpeed`. Deriving it means the apex stays correct
when you change gravity, and it means nobody has to wonder later what `600`
meant.

Gravity is 28 m/s², roughly 2.9× Earth. Real gravity at this scale feels
floaty; platformers almost always run heavy.

## Known trade-off, to be revisited in Step 2

`Player.update` **sets** horizontal velocity rather than applying a force. This
gives crisp, responsive control, which is what a platformer needs — but it means
the player currently wins every horizontal argument with the physics world. A
heavy crate would get shoved as if it were weightless, because the player's
velocity is simply overwritten each frame regardless of what is in the way.

Step 2 addresses this when the crate arrives.
