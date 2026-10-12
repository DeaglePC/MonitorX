"""Synthesize a 30s backing track for the promo (stdlib only).

96 BPM, one bar = 2.5s, scenes start on bar lines (see video.html).
Chords (2 bars each): Am  F  C  G  F  C  -> resolves on C under the end card.
Layers: pad throughout, riser into the 3.75s drop, kick + bass 3.75-25s,
8th-note pluck arp 8.75-25s, offbeat hats 13.75-25s, bell hit on the logo at 25.1s.
"""
import math, random, struct, sys, wave

SR = 44100
DUR = 30.0
N = int(SR * DUR)
BEAT = 60 / 96
BAR = BEAT * 4
random.seed(7)

def midi(n): return 440 * 2 ** ((n - 69) / 12)

CHORDS = [  # (root midi for bass, pad/arp notes)
    (45, [57, 60, 64, 69]),  # Am
    (41, [57, 60, 65, 69]),  # F
    (48, [55, 60, 64, 67]),  # C
    (43, [55, 59, 62, 67]),  # G
    (41, [57, 60, 65, 72]),  # F
    (48, [55, 60, 64, 72]),  # C
]
CHORD_LEN = 2 * BAR

L = [0.0] * N
R = [0.0] * N

def add(i, v, pan=0.0):
    if 0 <= i < N:
        L[i] += v * (1 - pan) ; R[i] += v * (1 + pan)

# ---- pad: detuned band-limited saws per chord tone, crossfaded between chords ----
for ci, (_, notes) in enumerate(CHORDS):
    t0 = ci * CHORD_LEN
    t1 = t0 + CHORD_LEN + (5.0 if ci == len(CHORDS) - 1 else 0.35)
    i0, i1 = int(t0 * SR), min(N, int(t1 * SR))
    for n in notes:
        for det in (-0.0025, 0.0025):
            f = midi(n) * (1 + det)
            harms = [h for h in range(1, 7) if f * h < 5000]
            ph = random.random() * 6.28
            w = 2 * math.pi * f / SR
            for i in range(i0, i1):
                t = (i - i0) / SR
                a = min(1, t / 0.35) * min(1, (i1 - i) / SR / 0.35)
                x = 0.0
                p = ph + w * (i - i0)
                for h in harms:
                    x += math.sin(p * h) / (h * 1.3)
                add(i, x * a * 0.011, det * 40)

# ---- riser into the drop (noise swell 2.2 -> 3.75) ----
lp = 0.0
for i in range(int(2.2 * SR), int(3.75 * SR)):
    t = i / SR
    k = (t - 2.2) / 1.55
    lp += (0.05 + 0.4 * k) * (random.uniform(-1, 1) - lp)
    add(i, lp * k * k * 0.22)

# ---- kick + bass 3.75 .. 25 ----
beat = 6
while beat * BEAT < 25 - 1e-6:
    t0 = beat * BEAT
    i0 = int(t0 * SR)
    ph = 0.0
    for j in range(int(0.35 * SR)):
        t = j / SR
        f = 45 + 95 * math.exp(-t * 28)
        ph += 2 * math.pi * f / SR
        add(i0 + j, math.sin(ph) * math.exp(-t * 9) * 0.34)
    if beat % 2 == 0:
        root = CHORDS[min(len(CHORDS) - 1, int(t0 // CHORD_LEN))][0]
        f = midi(root)
        for j in range(int(BEAT * 1.9 * SR)):
            t = j / SR
            env = min(1, t / 0.01) * math.exp(-t * 2.2)
            x = math.sin(2 * math.pi * f * t) + 0.35 * math.sin(4 * math.pi * f * t)
            add(i0 + j, x * env * 0.12)
    beat += 1

# ---- pluck arp: 8ths, 8.75 .. 25 ----
step = BEAT / 2
k = int(8.75 / step)
pattern = [0, 1, 2, 3, 2, 1, 3, 2]
while k * step < 25 - 1e-6:
    t0 = k * step
    notes = CHORDS[min(len(CHORDS) - 1, int(t0 // CHORD_LEN))][1]
    f = midi(notes[pattern[k % 8]] + 12)
    i0 = int(t0 * SR)
    pan = 0.35 if k % 2 else -0.35
    for j in range(int(0.4 * SR)):
        t = j / SR
        x = math.sin(2 * math.pi * f * t) + 0.3 * math.sin(6 * math.pi * f * t) * math.exp(-t * 20)
        add(i0 + j, x * math.exp(-t * 11) * 0.05, pan)
    k += 1

# ---- offbeat hats 13.75 .. 25 ----
k = int(13.75 / step)
while k * step < 25 - 1e-6:
    if k % 2:
        i0 = int(k * step * SR)
        prev = 0.0
        for j in range(int(0.06 * SR)):
            n = random.uniform(-1, 1)
            hp = n - prev; prev = n
            add(i0 + j, hp * math.exp(-j / SR * 70) * 0.05, 0.25)
    k += 1

# ---- bell on the logo reveal ----
i0 = int(25.1 * SR)
for f, amp in ((midi(84), 0.09), (midi(91), 0.05), (midi(84) * 2.76, 0.025)):
    for j in range(int(4.5 * SR)):
        t = j / SR
        add(i0 + j, math.sin(2 * math.pi * f * t) * math.exp(-t * 1.3) * amp)

# ---- master: fades, soft clip, normalize ----
fi, fo = int(0.3 * SR), int(28.0 * SR)
peak = 0.0
for i in range(N):
    g = min(1, i / fi) * (1 if i < fo else max(0.0, 1 - (i - fo) / (2.0 * SR)))
    L[i] = math.tanh(L[i] * 1.4 * g); R[i] = math.tanh(R[i] * 1.4 * g)
    peak = max(peak, abs(L[i]), abs(R[i]))
norm = 0.89 / peak

out = sys.argv[1] if len(sys.argv) > 1 else 'music.wav'
with wave.open(out, 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<hh', int(L[i] * norm * 32767), int(R[i] * norm * 32767)) for i in range(N)))
print('wrote', out)
