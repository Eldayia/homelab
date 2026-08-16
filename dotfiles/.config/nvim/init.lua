-- ─────────────────────────────────────────────────────────────
-- Configuration générale
-- ─────────────────────────────────────────────────────────────

local opt = vim.opt

-- Numéros de lignes.
opt.number = true
opt.relativenumber = true

-- Curseur et affichage.
opt.cursorline = true
opt.signcolumn = "yes"
opt.colorcolumn = "100"
opt.termguicolors = true
opt.showmode = false

-- Indentation.
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2
opt.smartindent = true
opt.breakindent = true

-- Recherche.
opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
opt.hlsearch = true

-- Fichiers et sauvegardes.
opt.swapfile = false
opt.backup = false
opt.undofile = true

-- Interface.
opt.wrap = false
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.splitright = true
opt.splitbelow = true
opt.mouse = "a"
opt.completeopt = { "menu", "menuone", "noselect" }

-- Presse-papiers.
-- Utilise le presse-papiers système lorsqu'un fournisseur est disponible.
opt.clipboard = "unnamedplus"

-- Délais plus réactifs.
opt.updatetime = 250
opt.timeoutlen = 400

-- Afficher certains caractères invisibles.
opt.list = true
opt.listchars = {
  tab = "» ",
  trail = "·",
  nbsp = "␣",
}

-- Meilleure gestion des caractères UTF-8.
opt.encoding = "utf-8"
opt.fileencoding = "utf-8"

-- ─────────────────────────────────────────────────────────────
-- Leader
-- ─────────────────────────────────────────────────────────────

vim.g.mapleader = " "
vim.g.maplocalleader = " "

local map = vim.keymap.set

-- ─────────────────────────────────────────────────────────────
-- Raccourcis
-- ─────────────────────────────────────────────────────────────

-- Enregistrer et quitter.
map("n", "<leader>w", "<cmd>write<CR>", {
  desc = "Enregistrer",
})

map("n", "<leader>q", "<cmd>quit<CR>", {
  desc = "Quitter",
})

map("n", "<leader>Q", "<cmd>quit!<CR>", {
  desc = "Quitter sans enregistrer",
})

-- Effacer le surlignage de recherche.
map("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Navigation entre les fenêtres.
map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")

-- Redimensionner les fenêtres.
map("n", "<C-Up>", "<cmd>resize +2<CR>")
map("n", "<C-Down>", "<cmd>resize -2<CR>")
map("n", "<C-Left>", "<cmd>vertical resize -2<CR>")
map("n", "<C-Right>", "<cmd>vertical resize +2<CR>")

-- Déplacer une sélection.
map("v", "J", ":move '>+1<CR>gv=gv")
map("v", "K", ":move '<-2<CR>gv=gv")

-- Conserver la sélection après indentation.
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Coller sans remplacer le registre par la sélection supprimée.
map("x", "<leader>p", [["_dP]])

-- Copier dans le presse-papiers système.
map({ "n", "v" }, "<leader>y", [["+y]])
map("n", "<leader>Y", [["+Y]])

-- Supprimer sans écraser le contenu copié.
map({ "n", "v" }, "<leader>d", [["_d]])

-- Ouvrir l'explorateur de fichiers intégré.
map("n", "<leader>e", "<cmd>Explore<CR>", {
  desc = "Explorateur de fichiers",
})

-- Ouvrir le fichier de configuration.
map("n", "<leader>vc", "<cmd>edit $MYVIMRC<CR>", {
  desc = "Configuration Neovim",
})

-- Recharger la configuration.
map("n", "<leader>vr", "<cmd>source $MYVIMRC<CR>", {
  desc = "Recharger Neovim",
})

-- Fenêtres.
map("n", "<leader>sv", "<cmd>vsplit<CR>", {
  desc = "Séparation verticale",
})

map("n", "<leader>sh", "<cmd>split<CR>", {
  desc = "Séparation horizontale",
})

-- Terminal.
map("n", "<leader>t", "<cmd>terminal<CR>", {
  desc = "Terminal",
})

map("t", "<Esc><Esc>", "<C-\\><C-n>", {
  desc = "Quitter le mode terminal",
})

-- ─────────────────────────────────────────────────────────────
-- Types de fichiers
-- ─────────────────────────────────────────────────────────────

local group = vim.api.nvim_create_augroup("UserConfig", {
  clear = true,
})

-- Retour à la dernière position dans le fichier.
vim.api.nvim_create_autocmd("BufReadPost", {
  group = group,
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local line_count = vim.api.nvim_buf_line_count(0)

    if mark[1] > 0 and mark[1] <= line_count then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Indentation à quatre espaces pour certains langages.
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = {
    "python",
    "c",
    "cpp",
  },
  callback = function()
    vim.opt_local.shiftwidth = 4
    vim.opt_local.tabstop = 4
    vim.opt_local.softtabstop = 4
  end,
})

-- Deux espaces pour les fichiers de configuration.
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = {
    "yaml",
    "json",
    "javascript",
    "typescript",
    "html",
    "css",
    "lua",
  },
  callback = function()
    vim.opt_local.shiftwidth = 2
    vim.opt_local.tabstop = 2
    vim.opt_local.softtabstop = 2
  end,
})

-- Mise en évidence lors d'une copie.
vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function()
    vim.highlight.on_yank({
      timeout = 150,
    })
  end,
})

-- Thème intégré.
vim.cmd.colorscheme("habamax")
