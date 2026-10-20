# website

The public page for Kessai, written for someone meeting the project for the first time. It is one long page built
around one payment followed end to end: as the visitor scrolls, a pinned scene (the books, what crosses the wire, what
happens inside the database) moves through six steps, request, transaction, acknowledgement, retry, webhook and
reconciliation. Then why the project exists, the money rules (with a race you can run), the architecture, how drills
are scored, the 12 drills, what is built, how to run it, Japan, the roadmap, a glossary and the FAQ. Plain HTML, CSS
and JavaScript with no build step and no dependencies, so any static host can serve this folder as it is.

| File | What it is |
|---|---|
| `index.html` | The page. Every section and the architecture diagram are inline SVG or plain HTML (the hero ledger is drawn by `main.js`) |
| `styles.css` | Light and dark themes (follows the visitor's system setting); code blocks stay dark in both |
| `main.js` | The journey scene (a pure function of scroll position), the hero ledger, the R3 race, the architecture traces, the lost-payment diff, the drill picker, reveals, counters, copy buttons, syntax colouring, and the sound. The page reads fine without it |
| `favicon.svg` | The mark: a teal ledger page with a vermilion seal |

## Sound

Every step has a sound, synthesised with the Web Audio API from one pentatonic scale (no audio files): a rising note
per step inside the transaction, a soft thud and two bright notes when the 済 stamp lands at COMMIT, a repeated note
for the idempotent replay, a low tone for the merchant's 503 and a chime for the delivery, and a melody as a packet
crosses the architecture diagram, with accents per node (a commit click at the Aurora writer, a bass note at SQS, a
glide to Osaka, a lock at the backup vault). The race ticks as payments land and sounds an alarm on an overdraft. Sound
is on by default with a mute button in the corner, and the choice is remembered. Browsers refuse to play audio until
the visitor clicks, taps or presses a key (scrolling does not count), so until that first gesture the button pulses
and a note says so; the first click on the button starts the sound rather than muting it. Everything moving respects
`prefers-reduced-motion`.

## Preview

```bash
python3 -m http.server 8000 --directory website   # then open http://localhost:8000
```

`make up` also uses port 8000 for the API; pick another port if both run.

## Deploy

Point any static host at this folder. There is nothing to build.

| Host | Settings |
|---|---|
| Vercel | Root directory `website`, framework preset "Other", no build command, no output directory |
| Netlify | Base directory `website`, publish directory `website`, no build command |
| Cloudflare Pages | Build output directory `website`, no build command |
| GitHub Pages | A workflow that uploads `website/` with `actions/upload-pages-artifact` and deploys it |

Then put the URL on the repository so it shows in the About box:

```bash
gh repo edit codewithmuh/kessai-payments --homepage https://<your-url>
```

## Keeping it honest

The page marks every feature as **Works today**, **Written, not applied**, **Next** or **Planned**, and each drill
as **FIS template written**, **Runs locally next** or **Planned**. When a state changes, change its pill (and the
drill's `status` in `main.js`) in the same pull request. The journey shows the target design from
[docs/scope.md](../docs/scope.md) and says so; when the payments API ships, replace the sketched request shapes with
the real ones from the OpenAPI spec. The hero scoreboard and the race are labelled as illustrations: keep them that
way. When a drill runs, put its measured lost count and RTO in the drill panel's "Measured" row, and replace the
recovery targets with results only once they are measured. Documentation links point at `main` on GitHub.
