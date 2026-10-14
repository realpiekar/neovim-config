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
opt.winminwidth = 0
opt.diffopt:remove({ "inline:char", "linematch:40" })
opt.diffopt:append({ "algorithm:histogram", "inline:word", "linematch:200", "followwrap" })
vim.g.diff_ignore_whitespace = true
function _G.diffexpr_ignore_whitespace()
  local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
  end
  local file = assert(io.open(vim.v.fname_out, "wb"))
  file:write(vim.text.diff(read(vim.v.fname_in), read(vim.v.fname_new), {
    algorithm = "histogram",
    indent_heuristic = true,
    ignore_whitespace = vim.g.diff_ignore_whitespace,
    ctxlen = 0,
  }))
  file:close()
end
opt.diffexpr = "v:lua.diffexpr_ignore_whitespace()"
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
local markdown_links_ns = vim.api.nvim_create_namespace("markdown_ref_links")
local function markdown_links(buf)
  vim.api.nvim_buf_clear_namespace(buf, markdown_links_ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local defs = {}
  for _, line in ipairs(lines) do
    local label, url = line:match("^%s*%[([^%]]+)%]:%s*<?([^%s>]+)")
    if label and not defs[label:lower()] then
      defs[label:lower()] = url
    end
  end
  if next(defs) == nil then
    return
  end
  for row, line in ipairs(lines) do
    local init = line:match("^%s*%[[^%]]+%]:") and #line + 1 or 1
    while true do
      local s, e, text = line:find("%[([^%[%]]+)%]", init)
      if not s then
        break
      end
      local stop, label, label_end = e, line:match("^%[([^%[%]]*)%]()", e + 1)
      if label then
        stop = label_end - 1
      end
      local url = line:sub(s - 1, s - 1) ~= "[" and line:sub(e + 1, e + 1) ~= "("
        and defs[(label and label ~= "" and label or text):lower()]
      if url then
        vim.api.nvim_buf_set_extmark(buf, markdown_links_ns, row - 1, s - 1, { end_col = stop, url = url })
      end
      init = stop + 1
    end
  end
end
vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
  callback = function(args)
    if vim.bo[args.buf].filetype == "markdown" then
      markdown_links(args.buf)
    end
  end,
})
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "text" },
  callback = function(args)
    vim.opt_local.linebreak = true
    if args.match == "markdown" then
      markdown_links(args.buf)
      vim.keymap.set("n", "<C-LeftMouse>", "<LeftMouse>gx", { buffer = args.buf, remap = true, desc = "Open Link" })
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
vim.keymap.set({ "n", "x" }, "<leader>cR", function()
  local pattern
  if vim.fn.mode() == "n" then
    pattern = "\\<" .. vim.fn.escape(vim.fn.expand("<cword>"), "\\/") .. "\\>"
  else
    local text = table.concat(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() }), "\n")
    pattern = vim.fn.escape(text, "\\/"):gsub("\t", "\\t"):gsub("\r", "\\r"):gsub("\n", "\\n")
  end
  return vim.keycode("<Esc>") .. ":%s/\\V\\C" .. pattern .. "//g" .. vim.keycode("<Left><Left>")
end, { expr = true, replace_keycodes = false, desc = "Replace in Buffer" })
local function gitsigns_diff_opts()
  return { linematch = 200, ignore_whitespace = vim.g.diff_ignore_whitespace or nil }
end
vim.keymap.set("n", "<leader>gw", function()
  vim.g.diff_ignore_whitespace = not vim.g.diff_ignore_whitespace
  vim.cmd("diffupdate")
  if package.loaded.gitsigns then
    require("gitsigns.config").config.diff_opts = gitsigns_diff_opts()
    require("gitsigns").refresh()
    local unified = require("gitsigns.unified")
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local view = unified.get_view(win)
      if view then
        require("gitsigns.async").run(unified.show, win, view.base)
      end
    end
  end
  vim.notify("Diff ignore whitespace: " .. (vim.g.diff_ignore_whitespace and "ON" or "OFF"))
end, { desc = "Diff Ignore Whitespace" })
vim.keymap.set("n", "<leader>ga", function()
  local aligned = vim.tbl_contains(vim.opt.diffopt:get(), "filler")
  if aligned then
    vim.opt.diffopt:remove({ "filler", "linematch:200" })
  else
    vim.opt.diffopt:append({ "filler", "linematch:200" })
  end
  vim.cmd("diffupdate")
  vim.notify("Diff aligned sides: " .. (aligned and "OFF" or "ON"))
end, { desc = "Diff Align Sides" })
for _, key in ipairs({ "<ScrollWheelUp>", "<ScrollWheelDown>" }) do
  vim.keymap.set("n", key, function()
    local win = vim.fn.getmousepos().winid
    if win ~= 0 and win ~= vim.api.nvim_get_current_win() and vim.wo[win].diff and vim.wo.diff then
      vim.api.nvim_set_current_win(win)
    end
    vim.api.nvim_feedkeys(vim.keycode(key), "n", false)
  end, { desc = "Scroll, focusing the diff side under the mouse" })
end
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
local function buffer_file(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local relpath = name:match("^gitsigns://.-//:?[^:]*:(.+)$")
  if relpath then
    local status = vim.b[buf].gitsigns_status_dict
    local root = status and status.root or vim.fs.root(vim.fn.getcwd(), ".git")
    return root and vim.fs.joinpath(root, relpath) or relpath
  end
  if name ~= "" and vim.bo[buf].buftype == "" then
    return vim.fn.fnamemodify(name, ":p")
  end
end
vim.keymap.set({ "n", "x" }, "<leader>cy", function()
  local path = buffer_file(0)
  if not path then
    vim.notify("No file to reference", vim.log.levels.WARN)
    return
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
  if disk_root and package.loaded.gitsigns then
    vim.api.nvim_exec_autocmds("User", {
      pattern = "GitSignsChanged",
      modeline = false,
      data = { file = disk_root .. "/" },
    })
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

local function parent_branch()
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
      return ref
    end
  end
  vim.notify("No main/master branch found", vim.log.levels.ERROR)
end

local function set_review_hl()
  local light = vim.o.background == "light"
  local backgrounds = {
    ReviewMinus = light and "#ffe0e0" or "#3f0001",
    ReviewMinusEmph = light and "#ffc0c0" or "#901011",
    ReviewPlus = light and "#d0ffd0" or "#002800",
    ReviewPlusEmph = light and "#a0efa0" or "#006000",
    ReviewChange = light and "#e0eafc" or "#1b2a40",
    ReviewChangeEmph = light and "#bdd1f7" or "#2e4a78",
  }
  for group, bg in pairs(backgrounds) do
    vim.api.nvim_set_hl(0, group, { bg = bg })
  end
  local links = {
    GitSignsAddPreview = "ReviewPlus",
    GitSignsAddInline = "ReviewPlusEmph",
    GitSignsChangeInline = "ReviewPlusEmph",
    GitSignsDeletePreview = "ReviewMinus",
    GitSignsDeleteInline = "ReviewMinusEmph",
    GitSignsDeleteVirtLn = "ReviewMinus",
    GitSignsDeleteVirtLnInLine = "ReviewMinusEmph",
    ReviewFiller = "Comment",
  }
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = target })
  end
end
set_review_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_review_hl })
vim.api.nvim_create_autocmd("OptionSet", { pattern = "background", callback = set_review_hl })

local function color_diff_sides(tab)
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return
  end
  local sides = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.wo[win].diff then
      table.insert(sides, win)
    elseif vim.w[win].review_side then
      vim.wo[win][0].winhighlight = ""
      vim.w[win].review_side = nil
    end
  end
  if #sides ~= 2 then
    return
  end
  table.sort(sides, function(a, b)
    return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
  end)
  for index, win in ipairs(sides) do
    local side = index == 1 and "Minus" or "Plus"
    vim.wo[win][0].winhighlight = table.concat({
      "DiffAdd:Review" .. side,
      "DiffChange:ReviewChange",
      "DiffText:ReviewChangeEmph",
      "DiffTextAdd:Review" .. side .. "Emph",
      "DiffDelete:ReviewFiller",
    }, ",")
    vim.w[win].review_side = side
  end
end
vim.api.nvim_create_autocmd("OptionSet", {
  pattern = "diff",
  callback = function()
    local tab = vim.api.nvim_get_current_tabpage()
    vim.schedule(function()
      color_diff_sides(tab)
    end)
  end,
})

local function review_panel()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "gitsigns-diff" then
      return buf
    end
  end
end
local function review_shown_row(panel)
  local ns = vim.api.nvim_get_namespaces().gitsigns_diff_selection
  return ns and vim.api.nvim_buf_get_extmark_by_id(panel, ns, 1, {})[1]
end
local function review_panel_action(panel, key)
  local action
  vim.api.nvim_buf_call(panel, function()
    action = vim.fn.maparg(key, "n", false, true).callback
  end)
  return action
end
local function fit_review_panel(panel)
  local win = vim.fn.bufwinid(panel)
  local ns = vim.api.nvim_get_namespaces().gitsigns_diff
  if win == -1 or not ns or vim.w[win].review_hidden then
    return
  end
  local decorations = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(panel, ns, 0, -1, { details = true })) do
    for _, chunk in ipairs(mark[4].virt_text or {}) do
      decorations[mark[2]] = (decorations[mark[2]] or 0) + vim.fn.strdisplaywidth(chunk[1])
    end
  end
  local width = 0
  for row, cells in pairs(decorations) do
    local line = vim.api.nvim_buf_get_lines(panel, row, row + 1, false)[1] or ""
    width = math.max(width, vim.fn.strdisplaywidth(line) + cells)
  end
  width = math.min(math.max(width + 2, 36), math.floor(vim.o.columns * 0.4))
  if width ~= vim.api.nvim_win_get_width(win) then
    vim.api.nvim_win_set_width(win, width)
    vim.api.nvim_win_call(win, function()
      vim.cmd("wincmd =")
    end)
  end
end
local function hide_review_panel(panel)
  local win = vim.fn.bufwinid(panel)
  if win == -1 then
    return
  end
  if win == vim.api.nvim_get_current_win() then
    vim.cmd("99wincmd l")
  end
  vim.w[win].review_hidden = true
  vim.api.nvim_win_set_width(win, 0)
  vim.cmd("wincmd =")
end
local function show_review_panel(panel)
  local win = vim.fn.bufwinid(panel)
  if win ~= -1 and vim.w[win].review_hidden then
    vim.w[win].review_hidden = nil
    fit_review_panel(panel)
  end
end
local function toggle_review_panel()
  local panel = review_panel()
  local win = panel and vim.fn.bufwinid(panel)
  if not panel then
    vim.notify("No diff panel in this tab", vim.log.levels.WARN)
  elseif vim.w[win].review_hidden then
    show_review_panel(panel)
  else
    hide_review_panel(panel)
  end
end
vim.keymap.set("n", "<leader>b", toggle_review_panel, { desc = "Diff File List Toggle" })
vim.api.nvim_create_autocmd("FileType", {
  pattern = "gitsigns-diff",
  callback = function(args)
    local panel, fit_pending, follow_tick = args.buf, false, 0
    vim.schedule(function()
      pcall(vim.keymap.del, "n", "<Space>", { buffer = panel })
    end)
    vim.api.nvim_create_autocmd("WinEnter", {
      buffer = panel,
      callback = function()
        vim.schedule(function()
          local win = vim.fn.bufwinid(panel)
          if win == -1 or not vim.w[win].review_hidden then
            return
          end
          if win == vim.api.nvim_get_current_win() then
            show_review_panel(panel)
          elseif vim.api.nvim_win_get_width(win) ~= 0 then
            vim.api.nvim_win_set_width(win, 0)
            vim.cmd("wincmd =")
          end
        end)
      end,
    })
    local function fit()
      fit_pending = false
      if vim.api.nvim_buf_is_valid(panel) then
        fit_review_panel(panel)
      end
    end
    vim.keymap.set("n", "l", "<CR>", { buffer = panel, remap = true, desc = "Open file" })
    vim.api.nvim_buf_attach(panel, false, {
      on_lines = function()
        if not fit_pending then
          fit_pending = true
          vim.schedule(fit)
        end
      end,
    })
    vim.schedule(fit)
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = panel,
      callback = function()
        follow_tick = follow_tick + 1
        local tick = follow_tick
        vim.defer_fn(function()
          if tick ~= follow_tick or vim.api.nvim_get_current_buf() ~= panel then
            return
          end
          if review_shown_row(panel) == vim.api.nvim_win_get_cursor(0)[1] - 1 then
            return
          end
          local preview = review_panel_action(panel, "<S-CR>")
          if preview then
            preview()
          end
        end, 60)
      end,
    })
  end,
})

local function focus_review()
  vim.schedule(function()
    local panel = review_panel()
    if panel and review_shown_row(panel) then
      vim.cmd("99wincmd l")
    end
  end)
end
local function open_review(revision, paths)
  require("gitsigns").diff(revision, paths, nil, focus_review)
end
local function toggle_review()
  if not review_panel() then
    return open_review()
  end
  if #vim.api.nvim_list_tabpages() == 1 then
    vim.cmd("tabnew | tabprevious")
  end
  vim.cmd.tabclose()
end
local function toggle_unified()
  local panel = review_panel()
  local toggle = panel and review_panel_action(panel, "gu")
  if toggle then
    toggle()
  else
    vim.notify("No diff panel in this tab", vim.log.levels.WARN)
  end
end
local function review_view(win)
  return package.loaded["gitsigns.unified"] and require("gitsigns.unified").get_view(win)
end
local function wait_until(ready, action, deadline)
  deadline = deadline or vim.uv.now() + 3000
  if ready() then
    return action()
  end
  if vim.uv.now() < deadline then
    vim.defer_fn(function()
      wait_until(ready, action, deadline)
    end, 15)
  end
end
local function land_on_split_change(forward)
  vim.cmd("normal! gg")
  if vim.fn.diff_hlID(1, 1) == 0 and vim.fn.diff_filler(1) == 0 then
    vim.cmd("silent! normal! ]c")
  end
  if not forward then
    local line
    repeat
      line = vim.fn.line(".")
      vim.cmd("silent! normal! ]c")
    until vim.fn.line(".") == line
  end
end
local function review_change(forward, nav_hunk)
  local panel, win = review_panel(), vim.api.nvim_get_current_win()
  local view = review_view(win)
  if view then
    local direction = forward and "next" or "prev"
    local line, line_count = vim.api.nvim_win_get_cursor(win)[1], vim.api.nvim_buf_line_count(0)
    if not view.hunks then
      return
    end
    if require("gitsigns.hunks").find_nearest_hunk(line, view.hunks, direction, false, line_count) then
      return nav_hunk(direction, { wrap = false })
    end
  else
    local before = vim.api.nvim_win_get_cursor(win)
    vim.cmd("silent! normal! " .. vim.v.count1 .. (forward and "]c" or "[c"))
    if not vim.deep_equal(before, vim.api.nvim_win_get_cursor(win)) then
      return
    end
  end
  local switch = vim.fn.maparg(forward and "]f" or "[f", "n", false, true).callback
  local panel_win = vim.fn.bufwinid(panel)
  if not switch or panel_win == -1 then
    return
  end
  local shown = review_shown_row(panel)
  switch()
  local target = vim.api.nvim_win_get_cursor(panel_win)[1] - 1
  if target == shown then
    return vim.api.nvim_echo({ { "No more changes", "WarningMsg" } }, false, {})
  end
  wait_until(function()
    return review_shown_row(panel) == target
  end, function()
    if vim.wo.diff then
      return land_on_split_change(forward)
    end
    wait_until(function()
      return (review_view() or {}).hunks ~= nil
    end, function()
      require("gitsigns").nav_hunk(forward and "first" or "last", { count = 1 })
    end)
  end)
end
for _, key in ipairs({ "]c", "[c" }) do
  vim.keymap.set("n", key, function()
    if review_panel() and vim.wo.diff then
      return review_change(key == "]c")
    end
    vim.cmd("silent! normal! " .. vim.v.count1 .. key)
  end, { desc = key == "]c" and "Next Change" or "Previous Change" })
end
local git_log = [[git log --color --pretty=format:"%C(yellow)%h%Creset ]]
  .. [[%Cgreen(%><(12)%cr%><|(12))%Creset %s %C(blue)<%an>%Creset"]]
local function git_history(range, path)
  local scope = path and " -- " .. vim.fn.shellescape(path) or ""
  require("fzf-lua").git_commits({
    cmd = git_log .. (range and " " .. range or "") .. scope,
    preview = "git show --color {1}" .. scope,
    actions = {
      enter = function(selected)
        local hash = selected[1] and selected[1]:match("^%x+")
        if not hash then
          return
        end
        if path then
          open_review(hash .. "~.." .. hash, { path })
        else
          require("gitsigns").show_commit(hash, "diff", focus_review)
        end
      end,
    },
  })
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
      vim.env.DELTA_EXPERIMENTAL_MAX_LINE_DISTANCE_FOR_NAIVELY_PAIRED_LINES = "1.0"
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
                  ["<leader>gf"] = { "git_history", desc = "Git History of Selected Path" },
                  ["<leader>gh"] = { "git_history", desc = "Git History of Selected Path" },
                },
              },
            },
            actions = {
              fzf_grep = function(_, item)
                if item then
                  require("fzf-lua").live_grep({ cwd = Snacks.picker.util.dir(item) })
                end
              end,
              git_history = function(_, item)
                if item then
                  git_history(nil, item.file)
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
      indent = {
        indent = {
          hl = { "SnacksIndent1", "SnacksIndent2", "SnacksIndent3", "SnacksIndent4", "SnacksIndent5", "SnacksIndent6", "SnacksIndent7", "SnacksIndent8" },
        },
      },
      lazygit = {
        win = { width = 0, height = 0, border = "none" },
        env = {
          GIT_CONFIG_PARAMETERS = table.concat({
            "'delta.minus-style'='normal #ffe0e0'",
            "'delta.minus-emph-style'='normal #ff9c9c'",
            "'delta.plus-style'='syntax #d6f5d6'",
            "'delta.plus-emph-style'='syntax #8cdc8c'",
          }, " "),
        },
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
      {
        "<leader>e",
        function()
          local panel = review_panel()
          if panel then
            vim.api.nvim_set_current_win(vim.fn.bufwinid(panel))
          else
            Snacks.explorer()
          end
        end,
        desc = "File Explorer / Diff File List",
      },
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
    event = { "BufReadPost", "BufNewFile", "FileType gitsigns-diff" },
    config = function()
      require("illuminate").configure({
        delay = 120,
        large_file_cutoff = 2000,
      })
      for _, group in ipairs({ "IlluminatedWordText", "IlluminatedWordRead", "IlluminatedWordWrite" }) do
        vim.api.nvim_set_hl(0, group, { link = "Visual" })
      end
      local hl = require("illuminate.highlight")
      local range, clear = hl.range, hl.buf_clear_references
      hl.range = function(bufnr, start, finish, kind)
        range(bufnr, start, finish, kind)
        if start[1] ~= finish[1] then
          return
        end
        for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
          if vim.wo[win].diff then
            local ids = vim.w[win].illuminate_matches or {}
            table.insert(ids, vim.fn.matchaddpos("IlluminatedWordText", { { start[1] + 1, start[2] + 1, finish[2] - start[2] } }, 10, -1, { window = win }))
            vim.w[win].illuminate_matches = ids
            vim.w[win].illuminate_buf = bufnr
          end
        end
      end
      hl.buf_clear_references = function(bufnr)
        clear(bufnr)
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local stored = vim.w[win].illuminate_buf
          if stored and (stored == bufnr or stored ~= vim.api.nvim_win_get_buf(win)) then
            for _, id in ipairs(vim.w[win].illuminate_matches or {}) do
              pcall(vim.fn.matchdelete, id, win)
            end
            vim.w[win].illuminate_matches = nil
            vim.w[win].illuminate_buf = nil
          end
        end
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
  { "HiPhish/rainbow-delimiters.nvim" },
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    cmd = "Gitsigns",
    config = function()
      local gitsigns = require("gitsigns")
      gitsigns.setup({ diff_opts = gitsigns_diff_opts() })
      local nav_hunk = gitsigns.nav_hunk
      gitsigns.nav_hunk = function(direction, opts, callback)
        if (direction == "next" or direction == "prev") and review_panel() and review_view() then
          return review_change(direction == "next", nav_hunk)
        end
        return nav_hunk(direction, opts, callback)
      end
      local preview = require("gitsigns.hunk_preview")
      local capture = preview.capture_removed_hunks_from_source
      preview.capture_removed_hunks_from_source = function(bufnr, source, hunks, opts)
        local whole_line = vim.tbl_extend("force", opts, { line_hl = "ReviewMinusEmph" })
        local lines = {}
        for index, hunk in ipairs(hunks) do
          lines[index] = capture(bufnr, source, { hunk }, hunk.added.count == 0 and whole_line or opts)[1]
        end
        return lines
      end
    end,
    keys = {
      {
        "<leader>gm",
        function()
          local ref = parent_branch()
          if not ref then
            return
          end
          local base = vim.trim(vim.fn.system({ "git", "merge-base", ref, "HEAD" }))
          if vim.v.shell_error ~= 0 then
            vim.notify("No merge base with " .. ref, vim.log.levels.ERROR)
            return
          end
          open_review(base)
        end,
        desc = "Diff vs parent branch",
      },
      {
        "<leader>gM",
        function()
          local ref = parent_branch()
          if not ref then
            return
          end
          if vim.trim(vim.fn.system({ "git", "rev-list", "--count", ref .. "..HEAD" })) == "0" then
            vim.notify("No commits on top of " .. ref, vim.log.levels.WARN)
            return
          end
          git_history(ref .. "..HEAD")
        end,
        desc = "Branch commits",
      },
      {
        "<leader>gp",
        function()
          vim.fn.system({ "git", "rev-parse", "--verify", "--quiet", "HEAD~1^{commit}" })
          if vim.v.shell_error ~= 0 then
            vim.notify("No previous commit", vim.log.levels.ERROR)
            return
          end
          open_review("HEAD~1")
        end,
        desc = "Diff vs previous commit",
      },
      { "<leader>gv", toggle_review, desc = "Diff Toggle" },
      { "<leader>gu", toggle_unified, desc = "Diff Unified Toggle" },
      { "<leader>gV", function() git_history() end, desc = "Repo History" },
      {
        "<leader>gh",
        function()
          local path = buffer_file(0)
          if path then
            git_history(nil, path)
          else
            vim.notify("No file to show history for", vim.log.levels.WARN)
          end
        end,
        desc = "Current File History",
      },
    },
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
