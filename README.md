# Stardust

A quiet night sky for Neovim. White and yellow stars brighten and fade around
your code and terminal output, with occasional meteors, crescent moons, ringed
planets, comets, and tiny starships.

Stardust is an independent Lua implementation with no runtime dependencies,
downloads, shell commands, or file writes. It decorates the editor without
modifying your text, undo history, or colorscheme background.

## Try it locally

Requires **Neovim 0.10+**. Enable `termguicolors` for the brightness ramps.

From this repository:

```sh
nvim -u /home/paul/Repos/Stardust/examples/minimal.lua
```

That starts an isolated demo configuration with a transparent background.
Open a file normally, or watch the sky below the empty buffer. Use
`:Stardust meteor` to preview a shooting star immediately.

To load the local checkout in your own Neovim configuration, after loading your
colorscheme:

```lua
vim.opt.runtimepath:prepend('/home/paul/Repos/Stardust')
require('stardust').setup({ autostart = true })
```

This also works alongside `vim.pack`. For a local lazy.nvim specification:

```lua
{
  dir = '/home/paul/Repos/Stardust',
  name = 'stardust',
  opts = { autostart = true },
}
```

Calling `setup()` without `autostart` registers the commands and leaves the
animation stopped. Calling it again safely applies new options; a running
animation resumes with the new configuration. Invalid options raise an error
before changing the running instance.

## Controls

| Command | Action |
| --- | --- |
| `:Stardust` | Toggle the animation |
| `:Stardust start` | Start, or keep the existing animation running |
| `:Stardust stop` | Stop the timer and remove all decorations |
| `:Stardust meteor` | Start if necessary and attempt a meteor in the current view |
| `:Stardust moon` | Preview a stationary crescent moon |
| `:Stardust planet` | Preview a ringed planet |
| `:Stardust comet` | Preview a slow comet |
| `:Stardust ship` | Preview a randomly selected custom ship |
| `:Stardust status` | Show activity, star counts, and reasons for skipped windows |
| `:checkhealth stardust` | Check requirements and rendering conditions |

The Lua API exposes `setup(opts)`, `start()`, `stop()`, `toggle()`, `meteor()`,
`object(kind)` and `status()`. `meteor()` and `object(kind)` return whether the
object could start in the current view. Pass `'moon'`, `'planet'`, `'comet'`, or `'ship'`
to `object()`, or omit the argument to choose from `objects.types`.

## Appearance and options

```lua
require('stardust').setup({
  autostart = true,
  fps = 30,                     -- animation updates per second, 1–30
  stars = 24,                   -- upper bound per view / shared EOF region
  enabled = {                  -- switches also apply to preview commands
    stars = true,
    meteors = true,
    ships = true,
    moons = true,
    planets = true,
    comets = true,
  },
  margin = 3,                   -- clear cells around text and window edges
  cursor_row = true,             -- reserve each window's cursor row
  blank_lines = false,           -- keep blank buffer lines free for indent guides
  below_eof = true,              -- stars in the unused area below the last line
  terminals = true,              -- decorate empty space in terminal buffers
  pause_on_focus_lost = true,
  background = '#121418',        -- foreground shading reference when Normal has no bg
  colors = {
    stars = { '#f4f1de', '#ffe6a3' }, -- randomly chosen per star
    meteors = '#e9c889',
    ships = '#c5d6ed',
    moons = '#f4f1de',
    planets = '#ffe6a3',
    comets = '#e9c889',
  },
  twinkle = { '·', '∘', '✧', '✦' },
  meteor = {
    enabled = true,             -- automatic spawning (previews still work)
    interval = { 25, 60 },       -- randomized seconds between attempts per region
    speed = 24,                 -- horizontal cells per second
    trail = 6,                  -- maximum trail cells
  },
  objects = {
    enabled = true,             -- automatic spawning (previews still work)
    interval = { 15, 35 },       -- randomized seconds between attempts per region
    speed = 3,                  -- horizontal cells per second; comets move at 2x
    types = { 'moon', 'planet', 'comet', 'ship' },
    ships = {                  -- choose one definition per flight
      { right = '╞═◉═╡', left = '╞═◉═╡' },
      {
        right = { '  ▄  ', '╰─○─╯' },
        left = { '  ▄  ', '╰─○─╯' },
        -- color = '#a9cfff',   -- optional override of colors.ships
      },
    },
  },
  max_lines = 50000,
  max_bytes = 2 * 1024 * 1024,
  excluded_filetypes = {
    'alpha', 'dashboard', 'snacks_dashboard', 'neo-tree', 'NvimTree', 'oil',
  },
})
```

Stars are sparse: the actual count scales with available empty space up to the
configured limit. Meteors and comets follow one fixed diagonal: two columns
across for each row down. Their brightness eases between positions, with a
default of 30 FPS. They enter from the top or a side and finish at the edge they
reach, including the bottom of short splits. The whole trail finishes after
the head exits. They keep moving behind text and reappear in empty space. Mode changes and
edits refresh the below-EOF decorations without restarting a flight, provided
the region still has room to render.

Moons and planets stay in place for 16–28 seconds, fading in and out over two
seconds. Ships handle horizontal flybys; comets move diagonally with a small
tail. At most one additional object and one meteor are active in each region. They all respect
text occupancy. A busy or narrow view may have no suitable starting point.
Use `enabled` to turn each category on or off. For example,
`enabled = { ships = false, moons = false }` leaves the other categories at
their defaults. Disabled categories stay off in automatic spawning and preview
commands. With all six switches off, no animation timer runs or canvas is drawn.
The `stars` number controls the count independently of `enabled.stars`.

Set `objects.enabled = false` or `meteor.enabled = false` for manual previews
only. These automatic-spawning switches are separate from the category switches.
`objects.types` restricts which enabled object kinds are chosen automatically.

`objects.ships` accepts 1–16 definitions. Each has `right` and `left` artwork:
either a string or a list of 1–4 rows, each up to 16 single-cell glyphs wide.
Spaces are transparent. Each flight selects one definition uniformly and keeps
it for the entire trip. Its appropriate direction is drawn exactly as supplied;
Stardust adds no exhaust or automatic mirroring. An optional `color` overrides
`colors.ships` for that definition. Other object types retain their built-in
artwork and animation.

Every color is a `#RRGGBB` value. `colors.stars` accepts 1–8 colors; each other
category accepts one color. Foreground colors are shaded for twinkling and
fading, using the background as a reference.
The old `palette` option has been replaced by `colors`: for example, change
`palette = { '#ffffff', '#ffe6a3' }` to
`colors = { stars = { '#ffffff', '#ffe6a3' } }`. Named presets are removed.
Replace old ship names such as `'scout'` with artwork definitions as shown above.

For a font that renders the default symbols as double-width, use single-cell
ASCII glyphs such as `twinkle = { '.', '+', '*' }`. Meteor and object glyphs
that are not single-cell under your display settings are skipped.

### Transparent terminals

All Stardust highlights set only foreground colors. Background opacity remains
under your terminal and colorscheme's control. With Kitty, keep the theme's
background transparent and set `background_opacity` in `kitty.conf` as usual.

`background` above is **only a color used to calculate dimmer foreground shades**;
it does not paint a background or change Kitty settings. Match it to Kitty's
background when using a transparent colorscheme. The default matches `#121418`.
Highlights refresh on colorscheme changes.

## Placement and compatibility

- On real buffer lines, stars occupy the margin after the complete displayed
  text. Indentation is reserved. Blank buffer lines are also reserved by default
  because plugins such as Snacks can draw indentation guides there.
- Terminal buffers also use the empty rows and space after output, including
  when their `wrap` option is set. The cursor row remains reserved. Stardust
  adds no virtual lines to terminals and does not modify terminal contents or
  scrollback. Set `terminals = false` to opt out.
- Text occupancy is checked on each redraw, not just on animation ticks. Typing,
  scrolling, and resizing can remove a star immediately.
- Width calculations account for tabs, per-buffer tab settings, Unicode, and
  horizontal scrolling. Rows with stored virtual text, such as diagnostics or
  inlay hints, are reserved in full.
- Real-line decorations are temporary and window-local. Opening one buffer in
  two splits does not combine their twinkles.
- Below EOF, Neovim's virtual lines are buffer-scoped. Stardust creates **one**
  shared canvas, sized to the smallest free area across all views of that buffer,
  including other tabs. If any view has no free area or is unsupported, the EOF
  canvas is omitted. Edits clear it synchronously, before the next redraw.
- Wrapped file views, diff, concealed, and visibly folded views are skipped, as
  are views containing other virtual lines. Floating windows, other special buffers,
  large buffers, and excessively decorated views are skipped. `status` explains
  these decisions.
- Visual/select, command-line, and replace modes pause the effect.
  Focus loss also pauses it by default. Normal, insert, and terminal input modes
  remain animated across all eligible windows.

Other plugins can draw temporary decorations during redraw that are not exposed
by the stored-extmark API. Stardust uses low priority and conservative placement,
but cannot inspect every such provider. For unusual custom renderers, exclude
their filetype or set `vim.b.stardust_disable = true` / `vim.w.stardust_disable = true`.
Set `blank_lines = true` only when those lines are available for decoration.

## Implementation and validation

One timer drives all regions. Only visible scenes advance; a single pending-frame
slot prevents callback backlogs when Neovim is busy. Line widths are cached until
text, viewport, or relevant display settings change. Particle counts, trail
lengths, file sizes, and decoration scans have explicit limits. Animation uses
monotonic time and its own random generator, leaving Lua's global random state
alone. No floating windows are created.

The redraw uses Neovim's public APIs. Terminal rendering still has a cost; this
is a small ambient animation, not a zero-overhead feature. Focus pause stops its
timer completely.

```sh
make test       # real embedded Neovim UI tests; no additional dependencies
make benchmark  # four splits, 180×56 grid; baseline and animated frame timings
make check     # formatting check; requires StyLua
```

Tests check actual screen cells as well as lifecycle, configuration validation,
transparency, buffer contents, undo history, splits, scrolling, decorations,
terminal input/output, full meteor flights, and celestial objects.
The benchmark measures Neovim frame work, not Kitty's GPU
rendering or desktop compositing.

MIT licensed. See [LICENSE](LICENSE).
