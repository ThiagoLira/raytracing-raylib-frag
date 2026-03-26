# Lesson 9: Temporal Accumulation

Each frame shoots random rays — the result is noisy. But if you average many noisy frames, the noise melts away. This is the Law of Large Numbers in action.

## What you'll learn

- **Why it's noisy**: each pixel gets only 1 random ray per frame. The ray might hit a bright spot or a dark spot — it's a coin flip. One sample is a terrible estimate.
- **Averaging fixes it**: noise decreases as `1/sqrt(N)`. After 100 frames, noise is 10x lower. After 10,000 frames, 100x lower. The image converges to the true solution.
- **Double-buffered accumulation**: we keep two framebuffers (ping-pong). Read from the previous frame's buffer, blend the new sample in, write to the other buffer. Swap every frame.
- **Camera move = reset**: accumulated samples are only valid for the current viewpoint. When the camera moves, we discard old data and start fresh.
- **The blend formula**: `output = mix(previous, new_sample, 1/frameCount)`. This gives equal weight to every frame — a perfect running average.

## What to look at

When the lesson starts, you'll see heavy noise that gradually clears up. The frame counter and noise percentage (top-right) show the progress. Press R to reset and watch it converge again. Press P to pause and study a specific noise level.

Orbit the camera — notice how moving resets the counter and the image gets noisy again until it re-converges.

## Controls

| Key | Action |
|-----|--------|
| R | Reset accumulation |
| P | Pause / resume |
| Right-click drag | Orbit camera (resets accumulation) |
| Scroll wheel | Zoom |

## Build & run

```
make run
```
