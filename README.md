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
  stars = 32,
  shower_interval = 600, -- seconds; random showers every 5–15 minutes
  enabled = {
    stars = true,
    meteors = true,
    moons = true,
    planets = true,
    comets = true,
    ships = true,
    ship_enemies = true,
  },
})
```

`setup()` starts the animation. Calling it again applies the new settings.
For lazy.nvim, use `dir = '~/Repos/Stardust'` and `opts = {}`.
To try the isolated demo, run `nvim -u examples/minimal.lua` from this repository.

## Options

Omit any option to use its default.

| Option | Default | Meaning |
| --- | --- | --- |
| `fps` | `60` | Target updates per second, 1–120 |
| `stars` | `32` | Maximum stars per scene, 0–100 |
| `shower_interval` | `600` | Average seconds between showers; `0` disables automatic showers |
| `enabled` | All `true` | Booleans shown above; `ship_enemies` allows occasional ship battles |
| `meteors` | `true` | Enable shooting stars |
| `objects` | `{ 'moon', 'planet', 'comet', 'ship' }` | Which other objects can appear; `{}` disables them |
| `colors` | White/yellow stars and muted object colors | Optional foreground color overrides |
| `ships` | Ten built-in ships | Optional custom artwork |

Use `enabled = { ships = false }` to turn a category off. Omitted switches
remain `true`. These switches also apply to preview commands. `stars` still
sets the star count, and the `ships` array holds the editable artwork.

Showers randomly wait between half and one-and-a-half times `shower_interval`
(an integer from 0–86400 seconds). The default is 5–15 minutes per scene.
Each burst launches 24–48 meteors over a few seconds across a band roughly
40% of the view's width. Trails keep moving until they leave the viewport.
`enabled.meteors = false` disables lone meteors and showers together.

With `enabled.ship_enemies = true`, roughly one in four automatic ship appearances
can be a chase when there is room. Most ships fly solo. Pursuers arrive after
varying delays, ease into the enemy's lane over about 1–2 seconds, and fire short
bursts. Spacing and speeds vary. The first bullet to hit destroys the enemy at
the impact point; enemies can boost away, outrun slower bullets, or reach the
edge before a bullet catches them.
The pursuer flies on. Both ships use the `ships` artwork; enemies have a distinct
color. Turning off `ships` also turns off battles.

For just the stars:

```lua
require('stardust').setup({ meteors = false, objects = {} })
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
  ships = {
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

Colors use `#RRGGBB`. Stars accept 1–8 colors. Ships accept 1–16 definitions;
each direction is a string or 1–4 rows, up to 16 single-cell characters wide.
Spaces are transparent. The `-- stylua: ignore` comment preserves the artwork's
row layout when formatting. Highlights set foreground colors only, preserving
the colorscheme background, selections, and terminal transparency. Shades use
`Normal`'s background and adjust foreground brightness for contrast on light
or dark themes. Colors refresh when the colorscheme or `background` changes.
With a transparent theme, Neovim's `background=dark` or `background=light`
provides the hint; the terminal's actual background color is not available.

The old configuration switches for cursor rows, blank lines, filetypes,
terminals, focus, and modes are removed. There is no `autostart` option:
`setup()` starts the sky. `fps` is now one number. Object selection and artwork
use the `objects` list and `ships` list shown above.

## Controls

- `:Stardust` toggles the sky; `:Stardust start` and `:Stardust stop` are explicit.
- `:Stardust meteor`, `moon`, `planet`, `comet`, and `ship` preview that object.
- `:Stardust ship` always previews an ordinary flyby.
- `:Stardust shower` previews a burst immediately, even with automatic showers off.
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
Floating windows (popups, pickers, hover documentation) are left alone.

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
