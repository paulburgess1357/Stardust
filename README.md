# Stardust

Twinkling stars, meteor showers, drifting planets, and tiny ship chases in the
empty space around your text in Neovim.

The sky stays on while you edit, run commands, select text, use a terminal, or
sit on a dashboard. It only draws on empty cells, never touches your files or
undo history, and leaves nothing behind when you turn it off.

<!-- TODO: demo video -->

Stardust was created 100% by Astra and Fable. Every line of code, test, and
documentation was written by them. The human involved asked for things and
watched the stars.

## Requirements

- Neovim 0.10 or newer
- `termguicolors` enabled for smooth brightness changes
- No dependencies

## Install

With Neovim's built-in package manager (0.12+):

```lua
vim.pack.add({ 'https://github.com/USER/Stardust' })
require('stardust').setup()
```

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ 'USER/Stardust', opts = {} }
```

Any other plugin manager works the same way: install the repository and call
`require('stardust').setup()`. For a local checkout, add it to the runtime
path first:

```lua
vim.opt.runtimepath:prepend(vim.fn.expand('~/Repos/Stardust'))
require('stardust').setup()
```

`setup()` starts the sky. To try it without installing anything, run
`nvim -u examples/minimal.lua` from the repository root.

## Settings

Everything is optional. Every category is a level from 0 (off) to 10
(constant). These are the defaults:

```lua
require('stardust').setup({
  fps = 60,
  floating_windows = false, -- also animate popups, pickers, and hover docs
  stars = 3, -- density
  meteors = 7, -- everything below is frequency
  showers = 3,
  moons = 5,
  planets = 5,
  orbits = 4,
  pulsars = 4,
  nebulas = 3,
  supernovas = 2,
  comets = 6,
  satellites = 4,
  ufos = 3,
  ships = 6,
  battles = 3, -- share of ship flybys that turn into a chase
})
```

Calling `setup()` again applies new settings. Set a category to `0` to turn it
off, including its preview command. `ships = 0` also turns off battles.

**Frequency** doubles with each level. Level 1 is about once an hour, level 7
about once a minute, level 10 about every seven seconds. Waits vary between
half and one and a half times that average. Each kind keeps its own timer, so
objects can share the screen.

**Star density** is about one star per 100 empty cells at level 3 and one per
30 at level 10.

**Battles** is a share: level 3 turns about 30% of automatic ship flybys into
a chase, level 10 turns every one.

Colors and ship artwork can be customized too:

```lua
require('stardust').setup({
  colors = {
    stars = { '#f4f1de', '#ffe6a3' }, -- 1 to 8 colors
    meteors = '#e9c889', -- one color per category
    ships = '#c5d6ed',
  },
  -- stylua: ignore
  fleet = {
    { right = '╺══◈══►', left = '◄══◈══╸' },
    {
      right = { '  ▄▖', '╾═◉▐▶' },
      left = { ' ▗▄', '◀▌◉═╼' },
      color = '#a9cfff', -- optional per-ship color
    },
  },
})
```

Ships are one to four rows of single-width characters, up to 16 wide, with
spaces transparent. A custom `fleet` replaces the ten built-in ships. Colors
set only the foreground, so your colorscheme background, selections, and
terminal transparency stay as they are. See `:help stardust` for every option.

## Commands

| Command | What it does |
| --- | --- |
| `:Stardust` | Toggle the sky |
| `:Stardust start` / `stop` | Turn it on or off explicitly |
| `:Stardust meteor` | Preview a shooting star |
| `:Stardust shower` | Preview a meteor shower |
| `:Stardust battle` | Start a ship chase right now |
| `:Stardust moon` | Preview a moon; the same works for `planet`, `orbit`, `pulsar`, `nebula`, `supernova`, `comet`, `satellite`, `ufo`, and `ship` |
| `:Stardust status` | Show what is on screen and the target FPS |
| `:checkhealth stardust` | Check the environment |

Previews add to whatever is already on screen. A preview does nothing when its
category is set to `0` or the window has no room. The same controls exist in
Lua on `require('stardust')`: `start()`, `stop()`, `toggle()`, `meteor()`,
`shower()`, `battle()`, `object(kind)`, and `status()`.

## Good to know

- Only empty space is drawn on. Text, virtual text, and diagnostics stay
  readable, and stars hidden by text come back when it moves.
- Floating windows such as pickers and hover docs are left alone unless
  `floating_windows = true`.
- The sky keeps running in every mode and buffer type, including terminals and
  startup dashboards.
- Files, undo history, and terminal scrollback are never modified.

## Development

```sh
make test       # embedded Neovim: real screen cells, input, lifecycle, and animation
make benchmark  # four splits on a 180×56 screen
make check      # StyLua formatting
```

Object kinds live in one registry, `lua/stardust/objects.lua`. Adding an entry
there adds its option, color, preview command, and spawn timer.

## License

MIT. See [LICENSE](LICENSE).
