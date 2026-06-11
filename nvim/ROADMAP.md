# Neovim Configuration Roadmap

Used primarily for editing config files. Goal: minimal plugin footprint, good syntax highlighting, and quality-of-life options — no LSP bloat.

## Options (no plugins needed)

- [ ] `vim.opt.relativenumber = true` — relative line numbers for faster motion
- [ ] `vim.opt.number = true` — absolute number on current line
- [ ] `vim.opt.undofile = true` — persistent undo across sessions
- [ ] `vim.opt.clipboard = 'unnamedplus'` — sync with system clipboard (requires `wl-clipboard` package on Wayland)
- [ ] `vim.opt.scrolloff = 8` — keep 8 lines visible above/below cursor
- [ ] `vim.opt.wrap = false` — no line wrapping for wide configs
- [ ] `vim.opt.ignorecase = true` + `vim.opt.smartcase = true` — smart case search
- [ ] `vim.opt.splitright = true` + `vim.opt.splitbelow = true` — sane split directions

## Plugin manager

- [ ] Add [lazy.nvim](https://github.com/folke/lazy.nvim) bootstrap to `init.lua`

## Plugins

- [ ] **Colorscheme** — [`catppuccin/nvim`](https://github.com/catppuccin/nvim) (Mocha variant matches the dark aesthetic)
- [ ] **Syntax highlighting** — [`nvim-treesitter`](https://github.com/nvim-treesitter/nvim-treesitter) with parsers for: `lua`, `bash`, `json`, `jsonc`, `toml`, `yaml`, `ini`, `css`
- [ ] **Auto-pairs** — [`echasnovski/mini.pairs`](https://github.com/echasnovski/mini.nvim) (lightweight, no config needed)
- [ ] **Statusline** — [`echasnovski/mini.statusline`](https://github.com/echasnovski/mini.nvim) (replaces default statusline, zero config)
- [ ] **File picker** — [`ibhagwan/fzf-lua`](https://github.com/ibhagwan/fzf-lua) for jumping between config files quickly (requires `fzf` package)

## Nice-to-have (still minimal)

- [ ] **Which-key** — [`folke/which-key.nvim`](https://github.com/folke/which-key.nvim) — shows available keybinds after a delay; useful when you don't use nvim daily
- [ ] **Highlight current word** — [`echasnovski/mini.cursorword`](https://github.com/echasnovski/mini.nvim) — underlines all occurrences of word under cursor
