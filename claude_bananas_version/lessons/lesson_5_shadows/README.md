# Lesson 5: Shadow Rays

To check if a point is in shadow, shoot a ray from the surface toward the light. If something is in the way, the point is shadowed. Simple idea, dramatic visual impact.

## What you'll learn

- **Shadow rays**: a second ray cast from the hit point toward the light source. Uses "any-hit" testing (we only need to know *if* something blocks the path, not *what*).
- **Hard shadows**: one ray to the light center. Binary result — fully lit or fully shadowed. Creates sharp, unrealistic shadow edges.
- **Soft shadows**: multiple rays jittered across the light's surface area. Average the results for a smooth penumbra. Larger light = softer shadow edge.

## What to look at

Toggle between no shadows (1), hard (2), and soft (3). With soft shadows, use +/- to change the light radius — larger radius creates wider, softer penumbras.

A yellow line shows the shadow ray from the center sphere to the light. The light position is marked with a bright dot. In soft shadow mode, small dots show the light's extent.

## Controls

| Key | Action |
|-----|--------|
| 1 | No shadows |
| 2 | Hard shadows |
| 3 | Soft shadows |
| +/- | Adjust light radius |
| Right-click drag | Orbit camera |
| Scroll wheel | Zoom |

## Build & run

```
make run
```
