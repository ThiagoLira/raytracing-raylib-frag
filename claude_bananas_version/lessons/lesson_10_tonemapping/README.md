# Lesson 10: Tone Mapping & Color

The path tracer outputs linear HDR values — numbers from 0 to infinity. Your monitor can only show 0 to 1. Tone mapping compresses the range while preserving the visual intent.

## What you'll learn

- **Why clamp is terrible**: without tone mapping, everything above 1.0 is clamped to white. Bright areas lose all detail and color, and the image looks flat.
- **Reinhard** (2002): `color / (1 + color)`. Simple, asymptotically approaches 1.0, preserves dark tones. But bright areas can look dull and desaturated.
- **ACES** (film industry standard): a more aggressive S-curve that boosts contrast and adds subtle warm color shifts. Looks cinematic but can shift hues.
- **AgX** (Blender 3.6+ default): the modern gold standard. Perceptually uniform, graceful highlight rolloff, minimal hue shifts. Best all-around choice.
- **Exposure**: multiplies the linear color by `2^EV` before tone mapping. Like adjusting a camera's exposure — +1 EV doubles the brightness.
- **sRGB gamma**: monitors have a non-linear response. The proper sRGB transfer function (not just `pow(1/2.2)`) has a linear segment near black for stability.

## What to look at

The scene has very bright emissive spheres that stress the tone mapper. Toggle between modes to see the difference:

- **None** (1): bright areas are blown out to flat white
- **Reinhard** (2): highlights are preserved but look washed out
- **ACES** (3): punchy contrast, slight warm shift
- **AgX** (4): natural rolloff, minimal color distortion

Use +/- to adjust exposure. Over-expose to see how each tone mapper handles highlight recovery.

## Controls

| Key | Action |
|-----|--------|
| 1 | No tone mapping (raw clamp) |
| 2 | Reinhard |
| 3 | ACES Filmic |
| 4 | AgX |
| +/- | Adjust exposure (EV stops) |
| R | Reset accumulation |
| Right-click drag | Orbit camera |
| Scroll wheel | Zoom |

## Build & run

```
make run
```
