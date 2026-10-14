vim.g.mapleader = " "
vim.g.maplocalleader = " "

local opt = vim.opt
opt.number = true
opt.tabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.cursorline = true
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = false
opt.splitright = true
opt.splitbelow = true
opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldlevel = 99
opt.foldtext = ""
opt.diffopt:remove({ "inline:char", "linematch:40" })
opt.diffopt:append({ "algorithm:histogram", "inline:word", "linematch:200", "iwhiteall" })
opt.fillchars:append({ diff = "╱" })

vim.filetype.add({
  extension = {
    hql = "sql",
    HQL = "sql",
    q = "sql",
    Q = "sql",
    conf = "hocon",
  },
})

local function markdown_highlight(buf)
  local render = require("render-markdown").get()
  if render and not vim.treesitter.highlighter.active[buf] then
    pcall(vim.treesitter.start, buf)
  elseif not render then
    vim.treesitter.stop(buf)
    vim.bo[buf].syntax = "OFF"
  end
end
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "text" },
  callback = function(args)
    vim.opt_local.linebreak = true
    if args.match == "markdown" then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(args.buf) and vim.bo[args.buf].filetype == "markdown" then
          markdown_highlight(args.buf)
        end
      end)
    end
  end,
})

vim.g.autosave = true
vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "FocusLost", "BufLeave" }, {
  callback = function(args)
    if not vim.g.autosave then
      return
    end
    local buf = args.buf
    if vim.bo[buf].modified and vim.bo[buf].buftype == "" and vim.bo[buf].modifiable
      and not vim.bo[buf].readonly and vim.api.nvim_buf_get_name(buf) ~= "" then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("silent! update")
      end)
    end
  end,
})
for key, dir in pairs({ ["*"] = "/", ["#"] = "?" }) do
  vim.keymap.set("n", key, function()
    return dir .. "\\C\\<" .. vim.fn.escape(vim.fn.expand("<cword>"), "\\/.*$^~[") .. "\\>\r"
  end, { expr = true, desc = "Search word (case sensitive)" })
end
vim.keymap.set("n", "<leader>gw", function()
  if vim.tbl_contains(vim.opt.diffopt:get(), "iwhiteall") then
    vim.opt.diffopt:remove("iwhiteall")
  else
    vim.opt.diffopt:append("iwhiteall")
  end
  vim.notify("Diff ignore whitespace: " .. (vim.o.diffopt:find("iwhiteall") and "ON" or "OFF"))
end, { desc = "Diff Ignore Whitespace" })
vim.api.nvim_create_autocmd("WinScrolled", {
  callback = function()
    local win = vim.fn.getmousepos().winid
    if win ~= vim.api.nvim_get_current_win() and vim.v.event[tostring(win)]
      and vim.wo[win].diff and vim.wo[win].scrollbind then
      vim.api.nvim_win_call(win, function()
        vim.cmd("normal! \x1b")
      end)
      vim.cmd("normal! \x1b")
    end
  end,
})
vim.keymap.set("n", "<leader>cr", function()
  local before, after = vim.bo.commentstring:match("^(.-)%%s(.*)$")
  before = (before or "# ") .. "REVIEW: "
  after = after or ""
  local indent = string.rep(" ", vim.fn.indent("."))
  local row = vim.fn.line(".")
  vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, { indent .. before .. after })
  vim.api.nvim_win_set_cursor(0, { row, #indent + #before })
  local indentkeys = vim.bo.indentkeys
  vim.bo.indentkeys = ""
  vim.api.nvim_create_autocmd("InsertLeave", {
    buffer = 0,
    once = true,
    callback = function()
      vim.bo.indentkeys = indentkeys
    end,
  })
  vim.cmd(after == "" and "startinsert!" or "startinsert")
end, { desc = "Review Comment" })
vim.keymap.set({ "n", "x" }, "<leader>cy", function()
  local name = vim.api.nvim_buf_get_name(0)
  local path = name:match("^diffview://.-/%.git/worktrees/[^/]+/[^/]+/(.+)$")
    or name:match("^diffview://.-/%.git/[^/]+/(.+)$")
  if path then
    local view = require("diffview.lib").get_current_view()
    path = view and vim.fs.joinpath(view.adapter.ctx.toplevel, path) or path
  else
    if name == "" or vim.bo.buftype ~= "" then
      vim.notify("No file to reference", vim.log.levels.WARN)
      return
    end
    path = vim.fn.fnamemodify(name, ":p")
  end
  local first, last = vim.fn.line("v"), vim.fn.line(".")
  if first > last then
    first, last = last, first
  end
  if vim.fn.mode():find("^[vV\22]") then
    vim.cmd("normal! \27")
  end
  local ref = path .. ":" .. first .. (last > first and "-" .. last or "")
  vim.fn.setreg("+", ref)
  vim.notify("Copied " .. ref)
end, { desc = "Copy Code Reference" })
vim.api.nvim_create_user_command("AutoSaveToggle", function()
  vim.g.autosave = not vim.g.autosave
  vim.notify("Auto-save: " .. (vim.g.autosave and "ON" or "OFF"))
end, {})

local disk_timer, disk_watchers, disk_root, disk_gitdir = vim.uv.new_timer(), {}, nil, nil
local disk_recursive, disk_created = vim.fn.has("linux") == 0, {}
local watch_dirs
local function refresh_from_disk()
  local created = disk_created
  disk_created = {}
  for path in pairs(created) do
    if not disk_watchers[path] and vim.fn.isdirectory(path) == 1 then
      watch_dirs()
      break
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local file = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" and not vim.bo[buf].modified
      and file ~= "" and vim.uv.fs_stat(file) then
      vim.cmd.checktime(buf)
    end
  end
  if package.loaded["snacks.explorer.watch"] then
    for _, picker in ipairs(Snacks.picker.get({ source = "explorer", tab = false })) do
      require("snacks.explorer.tree"):refresh(picker:cwd())
    end
    require("snacks.explorer.watch").refresh()
  end
  local view = package.loaded.diffview and require("diffview.lib").get_current_view()
  if view and view.update_files then
    view:update_files()
  end
end
local refresh_soon = vim.schedule_wrap(refresh_from_disk)
local function set_watchers(dirs)
  for dir, watcher in pairs(disk_watchers) do
    if dirs[dir] == nil then
      watcher:close()
      disk_watchers[dir] = nil
    end
  end
  for dir, recursive in pairs(dirs) do
    if not disk_watchers[dir] then
      local track = not recursive and dir ~= disk_gitdir
      local watcher = vim.uv.new_fs_event()
      watcher:start(dir, { recursive = recursive }, function(_, name, events)
        if track and name and events.rename then
          disk_created[dir .. "/" .. name] = true
        end
        if not disk_timer:is_active() then
          disk_timer:start(200, 0, refresh_soon)
        end
      end)
      disk_watchers[dir] = watcher
    end
  end
end
watch_dirs = function()
  local root, gitdir = disk_root, disk_gitdir
  if not root then
    return set_watchers({})
  end
  if disk_recursive then
    return set_watchers({ [root] = true, [gitdir] = false })
  end
  local cmd = { "git", "ls-files", "-z", "--cached", "--others", "--exclude-standard" }
  vim.system(cmd, { cwd = root }, vim.schedule_wrap(function(out)
    if root ~= disk_root or out.code ~= 0 then
      return
    end
    local dirs = { [root] = false, [gitdir] = false }
    for _, file in ipairs(vim.split(out.stdout or "", "\0", { plain = true, trimempty = true })) do
      local dir = vim.fs.dirname(file)
      while dir ~= "." and dirs[root .. "/" .. dir] == nil do
        dirs[root .. "/" .. dir] = false
        dir = vim.fs.dirname(dir)
      end
    end
    set_watchers(dirs)
  end))
end
local function watch_disk()
  local cwd = vim.fn.getcwd(-1, -1)
  local cmd = { "git", "rev-parse", "--show-toplevel", "--absolute-git-dir" }
  vim.system(cmd, { cwd = cwd, text = true }, vim.schedule_wrap(function(out)
    local root, gitdir = unpack(out.code == 0 and vim.split(vim.trim(out.stdout), "\n") or {})
    if cwd ~= vim.fn.getcwd(-1, -1) or root == disk_root then
      return
    end
    disk_root, disk_gitdir = root, gitdir
    watch_dirs()
  end))
end
vim.api.nvim_create_autocmd("VimEnter", { callback = watch_disk })
vim.api.nvim_create_autocmd("DirChanged", { pattern = "global", callback = watch_disk })

if vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 then
  local dir_buf = vim.fn.bufnr(vim.fn.argv(0))
  vim.cmd.cd(vim.fn.fnameescape(vim.fn.argv(0)))
  vim.cmd("%argdelete")
  if dir_buf > 0 then
    vim.cmd("silent! bwipeout " .. dir_buf)
  end
end

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  {
    "miikanissi/modus-themes.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.o.background = "light"
      vim.cmd.colorscheme("modus_operandi")
      vim.env.DELTA_FEATURES = "+theme-light"
      vim.env.BAT_THEME = "GitHub"
      vim.env.GLAMOUR_STYLE = "light"
      vim.env.DFT_BACKGROUND = "light"
    end,
  },
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      picker = {
        ui_select = false,
        sources = {
          explorer = {
            win = {
              list = {
                keys = {
                  ["<leader>/"] = { "fzf_grep", desc = "Grep in Selected Dir" },
                  ["<leader>gf"] = { "diffview_history", desc = "Git History of Selected Path" },
                  ["<leader>gh"] = { "diffview_history", desc = "Git History of Selected Path" },
                },
              },
            },
            actions = {
              fzf_grep = function(_, item)
                if item then
                  require("fzf-lua").live_grep({ cwd = Snacks.picker.util.dir(item) })
                end
              end,
              diffview_history = function(_, item)
                if item then
                  vim.cmd("DiffviewFileHistory " .. vim.fn.fnameescape(item.file))
                end
              end,
            },
            on_show = function(picker)
              local pending = false
              local function fit()
                pending = false
                if picker.closed or not picker.layout.root:valid() then
                  return
                end
                local width = 0
                for _, item in ipairs(picker.list.items) do
                  local depth, parent = 0, item.parent
                  while parent do
                    depth, parent = depth + 1, parent.parent
                  end
                  width = math.max(width, 2 * depth + 3 + vim.fn.strdisplaywidth(vim.fn.fnamemodify(item.file, ":t")))
                end
                width = math.min(math.max(width + 3, 40), math.floor(vim.o.columns * 0.4))
                local root = picker.layout.root.win
                if width ~= vim.api.nvim_win_get_width(root) then
                  picker.layout.opts.layout.width = width
                  vim.api.nvim_win_set_width(root, width)
                  vim.api.nvim_win_call(root, function()
                    vim.cmd("wincmd =")
                  end)
                end
              end
              vim.api.nvim_buf_attach(picker.list.win.buf, false, {
                on_lines = function()
                  if picker.closed then
                    return true
                  end
                  if not pending then
                    pending = true
                    vim.schedule(fit)
                  end
                end,
              })
              fit()
            end,
          },
        },
      },
      explorer = {},
      lazygit = {
        win = { width = 0, height = 0, border = "none" },
        config = {
          os = {
            edit = [[[ -z "$NVIM" ] && (nvim -- {{filename}}) || nvim --clean --headless --cmd "lua vim.rpcrequest(vim.fn.sockconnect('pipe', vim.env.NVIM, { rpc = true }), 'nvim_exec_autocmds', 'User', { pattern = 'LazygitEdit', data = { file = vim.fn.fnamemodify(vim.fn.argv(0), ':p') } }) vim.cmd.qall()" -- {{filename}}]],
            editAtLine = [[[ -z "$NVIM" ] && (nvim +{{line}} -- {{filename}}) || nvim --clean --headless --cmd "lua vim.rpcrequest(vim.fn.sockconnect('pipe', vim.env.NVIM, { rpc = true }), 'nvim_exec_autocmds', 'User', { pattern = 'LazygitEdit', data = { file = vim.fn.fnamemodify(vim.fn.argv(0), ':p'), line = {{line}} } }) vim.cmd.qall()" -- {{filename}}]],
          },
        },
      },
    },
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "LazygitEdit",
        callback = function(args)
          local buf, origin = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_tabpage()
          local term = vim.tbl_filter(function(t)
            return t.buf == buf
          end, Snacks.terminal.list())[1]
          if term then
            term:hide()
          end
          vim.cmd.tabedit(vim.fn.fnameescape(args.data.file))
          if args.data.line then
            pcall(vim.api.nvim_win_set_cursor, 0, { args.data.line, 0 })
          end
          local tab = vim.api.nvim_get_current_tabpage()
          vim.api.nvim_create_autocmd("TabClosed", {
            callback = function()
              if vim.api.nvim_tabpage_is_valid(tab) then
                return
              end
              vim.schedule(function()
                if term and term:buf_valid() and not term:win_valid() then
                  if vim.api.nvim_tabpage_is_valid(origin) then
                    vim.api.nvim_set_current_tabpage(origin)
                  end
                  term:show()
                end
              end)
              return true
            end,
          })
        end,
      })
      vim.api.nvim_create_autocmd("BufEnter", {
        callback = function(args)
          local file = vim.api.nvim_buf_get_name(args.buf)
          if file == "" or vim.bo[args.buf].buftype ~= "" or vim.api.nvim_win_get_config(0).relative ~= "" then
            return
          end
          vim.schedule(function()
            local picker = Snacks.picker.get({ source = "explorer" })[1]
            if not picker or picker.closed or not picker:on_current_tab() then
              return
            end
            local item = picker:current()
            if not (item and item.file == vim.fs.normalize(file)) then
              require("snacks.explorer.actions").update(picker, { target = file })
            end
          end)
        end,
      })
    end,
    keys = {
      { "<c-/>", function() Snacks.terminal(nil, { win = { position = "right", width = 0.4 } }) end, desc = "Toggle Terminal", mode = { "n", "t" } },
      { "<c-_>", function() Snacks.terminal(nil, { win = { position = "right", width = 0.4 } }) end, desc = "which_key_ignore", mode = { "n", "t" } },
      { "<leader>e", function() Snacks.explorer() end, desc = "File Explorer" },
      {
        "<leader>gg",
        function()
          local function is_main(win)
            return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ""
              and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ""
          end
          if not is_main(vim.api.nvim_get_current_win()) then
            local wins = vim.tbl_filter(is_main, vim.api.nvim_tabpage_list_wins(0))
            local prev = vim.fn.win_getid(vim.fn.winnr("#"))
            local target = is_main(prev) and prev or wins[1]
            if target then
              vim.api.nvim_set_current_win(target)
            end
          end
          Snacks.lazygit()
        end,
        desc = "Lazygit",
      },
    },
  },
  {
    "ibhagwan/fzf-lua",
    cmd = "FzfLua",
    opts = {
      fzf_colors = true,
      winopts = { fullscreen = true },
      previewers = {
        git_diff = { pager = "delta --width=$FZF_PREVIEW_COLUMNS" },
      },
    },
    init = function()
      vim.ui.select = function(...)
        require("fzf-lua").register_ui_select()
        return vim.ui.select(...)
      end
    end,
    keys = {
      { "<leader><space>", function() require("fzf-lua").global() end, desc = "Smart Find Files" },
      { "<leader>ff", function() require("fzf-lua").files() end, desc = "Find Files" },
      { "<leader>fg", function() require("fzf-lua").git_files() end, desc = "Find Git Files" },
      { "<leader>fr", function() require("fzf-lua").oldfiles() end, desc = "Recent Files" },
      { "<leader>fc", function() require("fzf-lua").files({ cwd = vim.fn.stdpath("config") }) end, desc = "Find Config File" },
      { "<leader>,", function() require("fzf-lua").buffers() end, desc = "Buffers" },
      { "<leader>:", function() require("fzf-lua").command_history() end, desc = "Command History" },
      { "<leader>/", function() require("fzf-lua").live_grep() end, desc = "Grep" },
      { "<leader>sw", function() require("fzf-lua").grep_cword() end, desc = "Grep Word" },
      { "<leader>sw", function() require("fzf-lua").grep_visual() end, desc = "Grep Selection", mode = "x" },
      { "<leader>sb", function() require("fzf-lua").blines() end, desc = "Buffer Lines" },
      { "<leader>sB", function() require("fzf-lua").lines() end, desc = "Grep Open Buffers" },
      { "<leader>sp", function() require("fzf-lua").builtin() end, desc = "FzfLua Pickers" },
      { "<leader>sR", function() require("fzf-lua").resume() end, desc = "Resume Picker" },
      { "<leader>gd", function() require("fzf-lua").git_diff() end, desc = "Git Changed Files" },
      { "<leader>gs", function() require("fzf-lua").git_status() end, desc = "Git Status" },
      { "<leader>gb", function() require("fzf-lua").git_branches() end, desc = "Git Branches" },
      { "<leader>gl", function() require("fzf-lua").git_commits() end, desc = "Git Log" },
      { "<leader>gL", function() require("fzf-lua").git_blame() end, desc = "Git Blame" },
      { "<leader>gf", function() require("fzf-lua").git_bcommits() end, desc = "Git Log Current File" },
      { "<leader>gS", function() require("fzf-lua").git_stash() end, desc = "Git Stash" },
      { "<leader>gW", function() require("fzf-lua").git_worktrees() end, desc = "Git Worktrees" },
      { "<leader>sh", function() require("fzf-lua").helptags() end, desc = "Help Pages" },
      { "<leader>sk", function() require("fzf-lua").keymaps() end, desc = "Keymaps" },
    },
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      delay = 200,
      spec = {
        { "<leader>f", group = "file / find" },
        { "<leader>s", group = "search" },
        { "<leader>g", group = "git" },
        { "<leader>c", group = "code / format" },
      },
    },
    keys = {
      { "<leader>?", function() require("which-key").show({ global = false }) end, desc = "Buffer Local Keymaps" },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").setup({ install_dir = vim.fn.stdpath("data") .. "/site" })
      require("nvim-treesitter").install({ "python", "rust", "scala", "sql", "swift", "typescript" })
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
        end,
      })
    end,
  },
  {
    "stevearc/conform.nvim",
    cmd = { "ConformInfo" },
    keys = {
      { "<leader>cf", function() require("conform").format({ async = true }) end, mode = { "n", "x" }, desc = "Format" },
    },
    config = function()
      require("conform").setup({
        formatters_by_ft = { markdown = { "prettier" } },
      })
    end,
    init = function()
      vim.api.nvim_create_user_command("Format", function(args)
        local range = nil
        if args.count ~= -1 then
          local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
          range = { start = { args.line1, 0 }, ["end"] = { args.line2, end_line:len() } }
        end
        require("conform").format({ async = true, range = range })
      end, { range = true })
    end,
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    opts = {
      enabled = false,
      pipe_table = { preset = "round", wrap = true },
    },
    keys = {
      {
        "<leader>cm",
        function()
          require("render-markdown").toggle()
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "markdown" then
              markdown_highlight(buf)
            end
          end
        end,
        desc = "Render Markdown Toggle",
      },
    },
  },
  {
    "RRethy/vim-illuminate",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("illuminate").configure({
        delay = 120,
        large_file_cutoff = 2000,
      })
      for _, group in ipairs({ "IlluminatedWordText", "IlluminatedWordRead", "IlluminatedWordWrite" }) do
        vim.api.nvim_set_hl(0, group, { link = "Visual" })
      end
      vim.keymap.set("n", "]]", function() require("illuminate").goto_next_reference(false) end, { desc = "Next Reference" })
      vim.keymap.set("n", "[[", function() require("illuminate").goto_prev_reference(false) end, { desc = "Prev Reference" })
    end,
  },
  {
    "echasnovski/mini.icons",
    lazy = true,
    opts = {},
    init = function()
      package.preload["nvim-web-devicons"] = function()
        require("mini.icons").mock_nvim_web_devicons()
        return package.loaded["nvim-web-devicons"]
      end
    end,
  },
  { "jvirtanen/vim-hocon", ft = { "hocon" } },
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {},
  },
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles", "DiffviewFocusFiles", "DiffviewRefresh" },
    keys = {
      {
        "<leader>gm",
        function()
          local refs = { "main", "master", "origin/main", "origin/master" }
          local branch = vim.trim(vim.fn.system({ "git", "branch", "--show-current" }))
          local reflog = branch ~= "" and vim.fn.systemlist({ "git", "reflog", "show", "--format=%gs", "refs/heads/" .. branch }) or {}
          local parent = (reflog[#reflog] or ""):match("^branch: Created from (.+)$")
          if parent and parent ~= "HEAD" then
            table.insert(refs, 1, parent)
          end
          for _, ref in ipairs(refs) do
            vim.fn.system({ "git", "rev-parse", "--verify", "--quiet", ref .. "^{commit}" })
            if vim.v.shell_error == 0 then
              vim.cmd("DiffviewOpen -C" .. vim.fn.fnameescape(vim.fn.getcwd()) .. " " .. ref .. "...HEAD --imply-local")
              return
            end
          end
          vim.notify("No main/master branch found", vim.log.levels.ERROR)
        end,
        desc = "Diffview vs parent branch",
      },
      {
        "<leader>gp",
        function()
          vim.fn.system({ "git", "rev-parse", "--verify", "--quiet", "HEAD~1^{commit}" })
          if vim.v.shell_error ~= 0 then
            vim.notify("No previous commit", vim.log.levels.ERROR)
            return
          end
          vim.cmd("DiffviewOpen -C" .. vim.fn.fnameescape(vim.fn.getcwd()) .. " HEAD~1")
        end,
        desc = "Diffview vs previous commit",
      },
      {
        "<leader>gv",
        function()
          if require("diffview.lib").get_current_view() then
            vim.cmd("DiffviewClose")
          else
            vim.cmd("DiffviewOpen")
          end
        end,
        desc = "Diffview Toggle",
      },
      { "<leader>gV", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview Repo History" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview Current File History" },
    },
    config = function()
      local function set_hl()
        local light = vim.o.background == "light"
        vim.api.nvim_set_hl(0, "DiffviewMinus", { bg = light and "#ffe0e0" or "#3f0001" })
        vim.api.nvim_set_hl(0, "DiffviewMinusEmph", { bg = light and "#ffc0c0" or "#901011" })
        vim.api.nvim_set_hl(0, "DiffviewPlus", { bg = light and "#d0ffd0" or "#002800" })
        vim.api.nvim_set_hl(0, "DiffviewPlusEmph", { bg = light and "#a0efa0" or "#006000" })
      end
      set_hl()
      vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })
      vim.api.nvim_create_autocmd("OptionSet", { pattern = "background", callback = set_hl })
      local lib = require("diffview.lib")
      local function fit_panel()
        local view = lib.get_current_view()
        local panel = view and view.panel
        if not (panel and panel:is_open() and panel:buf_loaded()) then
          return
        end
        local width = 0
        for _, line in ipairs(vim.api.nvim_buf_get_lines(panel.bufid, 0, -1, false)) do
          width = math.max(width, vim.fn.strdisplaywidth(line))
        end
        width = math.min(math.max(width + 2, 35), math.floor(vim.o.columns * 0.4))
        if width ~= vim.api.nvim_win_get_width(panel.winid) then
          vim.api.nvim_win_set_width(panel.winid, width)
          vim.api.nvim_win_call(panel.winid, function()
            vim.cmd("wincmd =")
          end)
        end
      end
      local follow_tick = 0
      local follow_group = vim.api.nvim_create_augroup("DiffviewFollowCursor", { clear = true })
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "DiffviewFiles",
        group = follow_group,
        callback = function(args)
          vim.api.nvim_clear_autocmds({ event = "CursorMoved", buffer = args.buf, group = follow_group })
          vim.api.nvim_create_autocmd("CursorMoved", {
            buffer = args.buf,
            group = follow_group,
            callback = function()
              follow_tick = follow_tick + 1
              local tick = follow_tick
              vim.defer_fn(function()
                if tick ~= follow_tick then
                  return
                end
                local view = lib.get_current_view()
                if not (view and view.panel and view.panel.get_item_at_cursor and view.panel:is_focused()) then
                  return
                end
                local item = view.panel:get_item_at_cursor()
                if item and type(item.collapsed) ~= "boolean" and item ~= view.panel.cur_file then
                  view:set_file(item, false)
                end
              end, 60)
            end,
          })
        end,
      })
      local actions = require("diffview.actions")
      local open_keys = {}
      for _, lhs in ipairs({ "<cr>", "o", "l", "<2-LeftMouse>" }) do
        table.insert(open_keys, { "n", lhs, actions.focus_entry, { desc = "Open the diff and focus it" } })
      end
      local focus_pending, hunk_jumped = false, {}
      local function jump_to_first_hunk(bufnr, winid)
        if hunk_jumped[bufnr] then
          return
        end
        hunk_jumped[bufnr] = true
        vim.schedule(function()
          if not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= bufnr then
            return
          end
          vim.api.nvim_win_call(winid, function()
            vim.api.nvim_win_set_cursor(winid, { 1, 0 })
            if vim.fn.diff_hlID(1, 1) == 0 and vim.fn.diff_filler(1) == 0 then
              vim.cmd("silent! normal! ]c")
            end
          end)
        end)
      end
      require("diffview").setup({
        keymaps = {
          file_panel = open_keys,
          file_history_panel = open_keys,
        },
        hooks = {
          view_opened = function()
            focus_pending, hunk_jumped = true, {}
          end,
          view_post_layout = fit_panel,
          diff_buf_win_enter = function(bufnr, winid, ctx)
            fit_panel()
            if ctx.symbol == "b" then
              jump_to_first_hunk(bufnr, winid)
            end
            if focus_pending and ctx.symbol == "b" then
              focus_pending = false
              vim.schedule(function()
                if vim.api.nvim_win_is_valid(winid) then
                  vim.api.nvim_set_current_win(winid)
                end
              end)
            end
            if not ctx.layout_name:match("^diff2") then
              return
            end
            local side = ctx.symbol == "a" and "Minus" or "Plus"
            vim.wo[winid].winhighlight = table.concat({
              "DiffAdd:Diffview" .. side,
              "DiffChange:Diffview" .. side,
              "DiffText:Diffview" .. side .. "Emph",
              "DiffDelete:DiffviewDiffDeleteDim",
            }, ",")
          end,
        },
      })
    end,
  },
}, {
  checker = { enabled = false },
})

for _, key in ipairs({ "h", "j", "k", "l" }) do
  vim.keymap.set("n", "<C-" .. key .. ">", "<C-w>" .. key, { desc = "Window " .. key })
  vim.keymap.set("t", "<C-" .. key .. ">", function()
    if vim.bo.filetype == "fzf" or vim.api.nvim_win_get_config(0).relative ~= "" then
      return "<C-" .. key .. ">"
    end
    return "<C-\\><C-n><C-w>" .. key
  end, { expr = true, desc = "Window " .. key })
end
