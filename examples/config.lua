-- A complete Stardust setup with every option spelled out.
-- Copy this into your config and adjust the levels to taste.
-- Every value shown here is the default, so you can delete any line you
-- do not care about and nothing changes.
--
-- Install Stardust first with your plugin manager (see the README).
-- For a local checkout instead, uncomment the next line:
-- vim.opt.runtimepath:prepend(vim.fn.expand('~/Repos/Stardust'))

vim.opt.termguicolors = true -- 24-bit color, needed for smooth fades

require('stardust').setup({
  fps = 60, -- target updates per second, 1-120
  floating_windows = false, -- also animate popups, pickers, and hover docs

  -- Star density from 0 (none) to 10 (dense).
  -- Level 3 is about one star per 100 empty cells, level 10 one per 30.
  stars = 3,

  -- Everything below is how often that thing appears, from 0 (never) to 10
  -- (about every 7 seconds). Level 1 is about once an hour and each level
  -- doubles that: 7 is about once a minute, 8 every 30 seconds, 9 every 15.
  meteors = 7, -- lone shooting stars
  showers = 3, -- bursts of 24-48 meteors
  moons = 5, -- wax and wane in place
  planets = 5, -- spinning edge-on ring
  orbits = 4, -- planet with a circling moon
  pulsars = 4, -- flashing stars
  nebulas = 3, -- faint shimmering clouds
  supernovas = 2, -- brief expanding bursts
  comets = 6, -- diagonal crossings with a tail
  satellites = 4, -- slow crossings with a blinking beacon
  ufos = 3, -- bobbing saucers with alternating lights
  ships = 6, -- ship flybys

  -- Share of ship flybys that turn into a chase: 3 is about 30%, 10 is all.
  battles = 3,

  -- Optional #RRGGBB foreground colors. Stars take 1-8 colors; every other
  -- category takes one. Omit any key to keep its default.
  colors = {
    stars = { '#f4f1de', '#ffe6a3' },
    meteors = '#e9c889',
    moons = '#f4f1de',
    planets = '#ffe6a3',
    orbits = '#9fd8cf',
    pulsars = '#bfe3ff',
    nebulas = '#c9a7e8',
    supernovas = '#ffd2a8',
    comets = '#e9c889',
    satellites = '#b8c4d0',
    ufos = '#9be07a',
    ships = '#c5d6ed',
  },

  -- Ship artwork. Each ship has right and left facing art: a string or 1-4
  -- rows of single-width characters, up to 16 wide. Spaces are transparent.
  -- A `color` field gives one ship its own color. A custom fleet replaces
  -- the built-in one, so keep any of these you still want.
  -- stylua: ignore
  fleet = {
    -- Dart
    { right = '╺══◈══►', left = '◄══◈══╸' },
    -- Comet Runner
    { right = '·∘○╡═◉═╞▶', left = '◀╡═◉═╞○∘·' },
    -- Needle
    { right = '─═◆═▶', left = '◀═◆═─' },
    -- Lancer
    { right = '╾──◈──╼▶', left = '◀╾──◈──╼' },
    -- Wedge
    { right = '◖◉▶', left = '◀◉◗' },
    -- Pin
    { right = '·─◆▶', left = '◀◆─·' },
    -- Bolt
    { right = '∘═◉═▶', left = '◀═◉═∘' },
    -- Scout
    {
      right = {
        '  ▄▖',
        '╾═◉▐▶',
      },
      left = {
        ' ▗▄',
        '◀▌◉═╼',
      },
    },
    -- Sprite
    {
      right = {
        '▗▖',
        '▐◉▶',
      },
      left = {
        ' ▗▖',
        '◀◉▌',
      },
    },
    -- Beetle
    {
      right = {
        ' ▄▄',
        '╾◉◉▶',
      },
      left = {
        ' ▄▄',
        '◀◉◉╼',
      },
    },
  },
})
