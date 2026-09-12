# Stardust

Twinkling stars, meteor showers, drifting planets, and tiny ship chases in the
empty space around your text in Neovim.

The sky stays on while you edit, run commands, select text, use a terminal, or
sit on a dashboard. It only draws on empty cells, never touches your files or
undo history, and leaves nothing behind when you turn it off.

https://github.com/user-attachments/assets/00e662a3-1332-4e11-99b9-4d8abbf1a751

The demo triggers effects by hand with the preview commands so they show up
quickly. In normal use everything appears on its own, as often as your settings
say.

Stardust was created 100% by Astra and Fable. Every line of code, test, and
documentation was written by them. The human involved asked for things and
watched the stars.

## Requirements

- Neovim 0.10 or newer
- No dependencies
- True color for smooth fades. It is a Neovim option, and most setups already
  turn it on:

```lua
vim.opt.termguicolors = true
```

## Install

With Neovim's built-in package manager (0.12+):

```lua
vim.pack.add({ 'https://github.com/paulburgess1357/Stardust' })
require('stardust').setup()
```

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ 'paulburgess1357/Stardust', opts = {} }
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

Everything is optional, and `setup()` with no arguments gives you the defaults
below. Every category is a level from 0 to 10, and 0 turns that category off
along with its preview command.

- **`stars`** is density. Level 3 is about one star per 100 empty cells,
  level 10 about one per 30.
- **`meteors`, `showers`, and every object kind** are frequency: how often one
  appears. Level 1 is about once an hour and each level doubles that. Waits
  vary between half and one and a half times the average, and every kind runs
  on its own timer, so several things can be on screen at once.

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| About every | 60 min | 30 min | 15 min | 7.5 min | 4 min | 2 min | 1 min | 30 s | 15 s | 7 s |

- **`battles`** is a share of ship flybys that turn into a chase. Level 3 is
  about 30%, level 10 is every one. `ships = 0` also turns off battles.
- **`floating_windows`** also animates popups, pickers, and hover docs.

```lua
require('stardust').setup({
  fps = 60,
  floating_windows = false,
  stars = 3,
  meteors = 7,
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
  battles = 3,
})
```

Calling `setup()` again applies new settings. For a fully commented setup with
every option, colors, and the built-in ship artwork, see
[examples/config.lua](examples/config.lua).

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
