# Stardust

A quiet night sky for Neovim. Small stars brighten and fade around your code,
with an occasional gold meteor and a short, fading trail.

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
| `:Stardust status` | Show activity, star counts, and reasons for skipped windows |
| `:checkhealth stardust` | Check requirements and rendering conditions |

The Lua API exposes `setup(opts)`, `start()`, `stop()`, `toggle()`, `meteor()` and
`status()`. `meteor()` returns whether a clear path was found.

## Appearance and options

```lua
require('stardust').setup({
  autostart = true,
  fps = 15,                     -- animation updates per second, 1–30
  stars = 24,                   -- upper bound per view / shared EOF region
  margin = 3,                   -- clear cells around text and window edges
  cursor_row = true,             -- reserve each window's cursor row
  blank_lines = false,           -- keep blank buffer lines free for indent guides
  below_eof = true,              -- stars in the unused area below the last line
  pause_on_focus_lost = true,
  background = '#121418',        -- foreground shading reference when Normal has no bg
  palette = {},                 -- derive from Normal, Identifier, and Special
  twinkle = { '·', '∘', '✧', '✦' },
  meteor = {
    enabled = true,
    interval = { 25, 60 },       -- randomized seconds between attempts per region
    speed = 18,                 -- horizontal cells per second
    trail = 6,                  -- maximum trail cells
  },
  max_lines = 50000,
  max_bytes = 2 * 1024 * 1024,
  excluded_filetypes = {
    'alpha', 'dashboard', 'snacks_dashboard', 'neo-tree', 'NvimTree', 'oil',
  },
})
```

Stars are sparse: the actual count scales with available empty space up to the
configured limit. Meteors attempt a clear path; a busy window may see fewer.
Heads and every trail cell obey the same text-avoidance rules as twinkles.

For a fixed palette, set `palette = { '#bcc9df', '#94bcd1', '#cfb9d7' }`. For a
font that renders the default symbols as double-width, use single-cell ASCII
glyphs such as `twinkle = { '.', '+', '*' }`. Meteor glyphs that are not
single-cell under your display settings are skipped.

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
- Wrapped, diff, concealed, and visibly folded views are skipped, as are views
  containing other virtual lines. Terminals, floating windows, special buffers,
  large buffers, and excessively decorated views are skipped. `status` explains
  these decisions.
- Visual/select, command-line, terminal, and replace modes pause the effect.
  Focus loss also pauses it by default. Normal and insert modes remain animated.

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
transparency, buffer contents, undo history, splits, scrolling, decorations, and
meteor collisions. The benchmark measures Neovim frame work, not Kitty's GPU
rendering or desktop compositing.

MIT licensed. See [LICENSE](LICENSE).
