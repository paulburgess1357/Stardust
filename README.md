# Stardust

Stars, meteor showers, and tiny ship chases around your text in Neovim.
The sky stays on while you move, type commands, select text, use a terminal,
or open a dashboard. It never edits your files or undo history.

Requires **Neovim 0.10+**. Enable `termguicolors` for smooth brightness changes.
There are no runtime dependencies.

## Setup

For a local checkout:

```lua
vim.opt.runtimepath:prepend(vim.fn.expand('~/Repos/Stardust'))
require('stardust').setup({
  fps = 60,
  floating_windows = false,
  -- Every category is a level from 0 (off) to 10 (constant).
  stars = 3, -- density
  meteors = 7, -- frequency
  showers = 3,
  moons = 6,
  planets = 6,
  comets = 6,
  ships = 6,
  battles = 3, -- share of ship flights that become a chase
})
```

`setup()` starts the animation. Calling it again applies the new settings.
For lazy.nvim, use `dir = '~/Repos/Stardust'` and `opts = {}`.
To try the isolated demo, run `nvim -u examples/minimal.lua` from this repository.

## Options

Omit any option to use its default. Every category takes an integer level
from 0 to 10, where 0 turns it off (including its preview command).

| Option | Default | Meaning |
| --- | --- | --- |
| `fps` | `60` | Target updates per second, 1–120 |
| `floating_windows` | `false` | Also animate floating windows (popups, pickers, hover docs) |
| `stars` | `3` | Star density, 0–10 |
| `meteors` | `7` | Lone shooting stars, 0–10 |
| `showers` | `3` | Meteor showers, 0–10 |
| `moons` | `6` | Crescent moons, 0–10 |
| `planets` | `6` | Ringed planets, 0–10 |
| `comets` | `6` | Comets with fading tails, 0–10 |
| `ships` | `6` | Ship flybys, 0–10 |
| `battles` | `3` | Share of ship flybys that become a chase, 0–10 |
| `colors` | White/yellow stars and muted object colors | Optional foreground color overrides |
| `fleet` | Ten built-in ships | Optional custom ship artwork |

**Frequency levels** (`meteors`, `showers`, `moons`, `planets`, `comets`,
`ships`) set how often something appears in each scene. Level 1 averages about
once an hour and each level doubles that:

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| About every | 60 min | 30 min | 15 min | 7.5 min | 4 min | 2 min | 1 min | 30 s | 15 s | 7 s |

Actual waits vary between half and one-and-a-half times the average. Only one
moon, planet, comet, or ship is on screen at a time, so at high levels the next
one waits for the slot and the longest-waiting kind goes first.

**Star density** puts about one star per 100 empty cells at level 3 and one per
30 at level 10, capped at 200 per scene.

**Battles** is a share: level 3 turns about 30% of automatic ship flights into
a chase when there is room; level 10 turns every one. Pursuers arrive after
varying delays, ease into the enemy's lane over about 1–2 seconds, and fire
short bursts. The first bullet to hit destroys the enemy at the impact point;
enemies can boost away, outrun slower bullets, or reach the edge first. The
pursuer flies on. Both ships use the `fleet` artwork; enemies have a distinct
color. `ships = 0` also turns off battles.

Each shower launches 24–48 meteors over a few seconds across a band roughly
40% of the view's width. Trails keep moving until they leave the viewport.
Showers and lone meteors are independent levels.

For just the stars:

```lua
require('stardust').setup({ meteors = 0, showers = 0, moons = 0, planets = 0, comets = 0, ships = 0 })
```

Colors and artwork can be customized independently:

```lua
require('stardust').setup({
  colors = {
    stars = { '#f4f1de', '#ffe6a3' },
    meteors = '#e9c889',
    ships = '#c5d6ed',
    moons = '#f4f1de',
    planets = '#ffe6a3',
    comets = '#e9c889',
  },
  -- stylua: ignore
  fleet = {
    { right = '╺══◈══►', left = '◄══◈══╸' },
    {
      right = {
        '  ▄▖',
        '╾═◉▐▶',
      },
      left = {
        ' ▗▄',
        '◀▌◉═╼',
      },
      color = '#a9cfff', -- optional per-ship color
    },
  },
})
```

Colors use `#RRGGBB`. Stars accept 1–8 colors. The fleet accepts 1–16 ships;
each direction is a string or 1–4 rows, up to 16 single-cell characters wide.
Spaces are transparent. A custom fleet replaces the built-in one. The
`-- stylua: ignore` comment preserves the artwork's row layout when formatting. Highlights set foreground colors only, preserving
the colorscheme background, selections, and terminal transparency. Shades use
`Normal`'s background and adjust foreground brightness for contrast on light
or dark themes. Colors refresh when the colorscheme or `background` changes.
With a transparent theme, Neovim's `background=dark` or `background=light`
provides the hint; the terminal's actual background color is not available.

Earlier versions used `enabled` booleans, an `objects` list, a star count,
`shower_interval` in seconds, and `ships` for artwork. Those are replaced by the
levels above and `fleet`. There is no `autostart` option: `setup()` starts the
sky.

Object kinds are defined in one registry, `lua/stardust/objects.lua`. Each entry
names the kind, its option and color key, default level, motion, and sprite.
Adding an entry adds its option, color, preview command, and spawn timer.

## Controls

- `:Stardust` toggles the sky; `:Stardust start` and `:Stardust stop` are explicit.
- `:Stardust meteor`, `moon`, `planet`, `comet`, and `ship` preview that object.
- `:Stardust ship` always previews an ordinary flyby.
- `:Stardust shower` previews a burst immediately.
- `:Stardust battle` starts a fresh ship chase, replacing any current object or chase.
- `:Stardust status` reports activity, target FPS, and particle counts.
- `:checkhealth stardust` checks the environment.

The same controls are available as `setup(opts)`, `start()`, `stop()`, `toggle()`,
`meteor()`, `shower()`, `battle()`, `object(kind)`, and `status()` on
`require('stardust')`. Previews respect category switches and return whether
the effect could start. Battle previews replace the current object; other
previews wait for an active effect to finish. A small view can prevent a preview.

## Rendering

One timer drives the sky using elapsed time. Higher FPS smooths brightness
between terminal cells; it does not change travel speed. Meteors and comets
follow a diagonal until their trails leave a viewport edge. Ships fly across;
moons and planets fade in place. Each scene has at most one lone meteor,
one shower, and one other object or ship encounter. Views sharing a canvas
also share their effects and timers.

Placement follows Neovim's displayed text positions, including wrapping,
Unicode, tabs, folds, dashboards, and terminal buffers. Text and stored virtual
text stay readable. Stars hidden by text keep their age and position, so cursor
movement and temporary decorations do not erase the sky. No filetype or mode
switches turn it off. A completely occupied row simply has no room to draw.
Floating windows (popups, pickers, hover documentation) are left alone unless
`floating_windows = true`.

The space below the last line uses virtual lines. Because these are scoped to
a buffer, matching views of that buffer share a canvas sized to fit all views.
If their visible geometry differs, each view keeps its own sky on buffer lines.
Edits and scrolling remove obsolete decorations before repainting. Nothing is
added to files or terminal scrollback. Other plugins' transient decorations
can cover low-priority stars in the cells they draw on.

## Development

```sh
make test       # embedded Neovim: real screen cells, input, lifecycle, and animation
make benchmark  # four splits on a 180×56 screen
make check      # StyLua formatting
```

MIT licensed. See [LICENSE](LICENSE).
