# Avi Frame Animation Contract

Tune AV plays Avi motion as PNG frame loops. The runtime looks for production
frames first and falls back to the current static emotion assets when a loop is
missing.

## Runtime Behavior

`NowPlayingView` and the full player Avi header render frame loops with
`TimelineView` at 12 frames per second. The renderer asks for the production
loop mapped to the current `TuneAVAviEmotion`; if fewer than two frames exist,
it renders the existing static full-body asset for that emotion.

Feedback in the player now drives the animated emotion directly:

- `liked` maps to `.celebrate`, which uses `AviTuneHappyReact000...019`.
- `notForMe` maps to `.thinking`, which will use `AviTuneThinking000...019`
  once those frames exist.
- `disliked` maps to `.dislike`, which will use `AviTuneDislike000...019`
  once those frames exist.

The footer tab still uses Avi, but as a cropped head/icon treatment with
`AviV2HeadNeutral`, so it does not duplicate the full-body Avi shown in content.

## Asset Rules

- Canvas: 1024 x 1024 transparent PNG.
- Avi must keep the same body scale, center, and foot baseline in every frame.
- Do not mix emotion poses as frames. Each sequence must be one coherent
  acting beat for a single emotion.
- Export 20 frames per production loop unless a shorter loop is deliberately
  approved.
- Use three-digit frame suffixes.

## Initial Loops

```text
AviTuneListeningIdle000.png ... AviTuneListeningIdle019.png
AviTuneHappyReact000.png ... AviTuneHappyReact019.png
AviTuneThinking000.png ... AviTuneThinking019.png
AviTuneDislike000.png ... AviTuneDislike019.png
AviTuneSurprised000.png ... AviTuneSurprised019.png
AviTuneSleepIdle000.png ... AviTuneSleepIdle019.png
```

`AviTuneHappyReact000...019` currently exists as the first prototype loop. It
is intentionally a clean whole-frame placeholder: every PNG contains the full
Avi on a transparent canvas, avoiding body-part cutouts or duplicated limbs.
These frames can be replaced by hand-drawn or generated production frames
without changing Swift code, as long as the names and canvas contract stay the
same.

## First Production Target

Start with `AviTuneListeningIdle`.

Motion direction:

- subtle breathing;
- tiny head and headphone movement;
- screen eyes listening/scanning;
- optional small side-panel pulse;
- no foot movement;
- no full-body bounce.

Once the 20 PNGs are added to `Assets.xcassets`, the iOS frame-loop renderer
will use them automatically.

## Acting Direction Examples

`AviTuneHappyReact` is one animation, not a sequence of emotion changes:

- Avi keeps a happy face for the whole loop;
- frame 000 starts in a balanced happy/listening pose;
- frames 001-006 lift the head and shoulders slightly;
- frames 007-012 add a small dance sway and arm bounce;
- frames 013-019 return to the starting pose cleanly for looping.

`AviTuneThinking` can be simpler:

- Avi keeps a thinking face;
- eyes/pixels shift once or twice;
- head dips slightly;
- body remains nearly still.

The face expression may change within the same emotion only as part of the
same acting beat, for example happy eyes blinking or thinking pixels scanning.
It must not jump from happy to surprised to focused unless the animation itself
is explicitly a transition.
