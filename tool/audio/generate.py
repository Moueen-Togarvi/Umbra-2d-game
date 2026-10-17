"""Generate original restrained, mono PCM game sounds; no external recordings."""
from pathlib import Path
import math
import random
import struct
import wave

OUT = Path(__file__).resolve().parents[2] / 'assets/audio'
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
rng = random.Random(716)

def write(name, duration, sampler):
    count = int(duration * RATE)
    values = [sampler(i / RATE, i / count) for i in range(count)]
    # Short endpoint fades prevent clicks; wind uses a long crossfade-like hush.
    fade = 0.3 if name == 'wind' else 0.008
    samples = []
    for i, v in enumerate(values):
        gain = min(1, i / (fade * RATE), (count - 1 - i) / (fade * RATE))
        samples.append(int(max(-1, min(1, v * gain)) * 32760))
    with wave.open(str(OUT / (name + '.wav')), 'wb') as f:
        f.setparams((1, 2, RATE, count, 'NONE', 'not compressed'))
        f.writeframes(struct.pack('<' + 'h' * count, *samples))

low = 0
def wind(t, p):
    global low
    low = low * .975 + rng.uniform(-1, 1) * .025
    return low * (0.6 + .25 * math.sin(2 * math.pi * p * 3))

write('wind', 16, wind)
write('step', .22, lambda t, p: (rng.uniform(-1, 1) * .24 + .25 * math.sin(2 * math.pi * 95 * t)) * math.exp(-22 * t))
write('land', .42, lambda t, p: (.5 * math.sin(2 * math.pi * (68 - 28*p) * t) + rng.uniform(-1,1) * .20) * math.exp(-12 * t))
write('rope', .60, lambda t, p: (.13 * math.sin(2 * math.pi * (210 + 35 * math.sin(t*9)) * t) + .035*rng.uniform(-1,1)) * math.sin(math.pi*p)**2)
write('drag', .45, lambda t, p: (.13*rng.uniform(-1,1) + .07*math.sin(t*510)) * math.sin(math.pi*p)**.5)
write('water', .35, lambda t, p: .2*rng.uniform(-1,1)*math.exp(-8*t) + .09*math.sin(2*math.pi*(440-180*p)*t)*math.exp(-12*t))
