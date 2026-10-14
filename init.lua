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
opt.fillchars:append({ diff = "╱", foldopen = "▾", foldclose = "▸", foldsep = " ", foldinner = " " })
opt.foldcolumn = "auto:1"
opt.mouse = "a"
opt.smoothscroll = true

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
local function clicked_git_sign(pos)
  if pos.winid == 0 or pos.line == 0 or not package.loaded.gitsigns then
    return false
  end
  if pos.wincol > vim.fn.getwininfo(pos.winid)[1].textoff then
    return false
  end
  local text = vim.trim(vim.fn.screenstring(pos.screenrow, pos.screencol))
  if text == "" then
    return false
  end
  local config = require("gitsigns.config").config
  for _, signs in ipairs({ config.signs or {}, config.signs_staged or {} }) do
    for _, sign in pairs(signs) do
      if vim.trim(sign.text or "") == text then
        return true
      end
    end
  end
  return false
end
local function clicked_closed_fold(pos)
  if pos.winid == 0 or pos.line == 0 or pos.wincol <= vim.fn.getwininfo(pos.winid)[1].textoff then
    return false
  end
  return vim.api.nvim_win_call(pos.winid, function()
    return vim.fn.foldclosed(pos.line) ~= -1
  end)
end
local sign_clicked = false
vim.keymap.set("n", "<LeftMouse>", function()
  local pos = vim.fn.getmousepos()
  local on_sign, on_fold = clicked_git_sign(pos), clicked_closed_fold(pos)
  sign_clicked = on_sign or on_fold
  if not sign_clicked then
    return vim.api.nvim_feedkeys(vim.keycode("<LeftMouse>"), "n", false)
  end
  vim.api.nvim_set_current_win(pos.winid)
  vim.api.nvim_win_set_cursor(pos.winid, { pos.line, 0 })
  if on_sign then
    require("gitsigns").preview_hunk_inline()
  else
    vim.cmd("normal! zo")
  end
end, { desc = "Click, previewing a hunk from its sign or opening a closed fold" })
vim.keymap.set("n", "<LeftRelease>", function()
  if sign_clicked then
    sign_clicked = false
    return
  end
  vim.api.nvim_feedkeys(vim.keycode("<LeftRelease>"), "n", false)
end, { desc = "Release, ignored after a git sign click" })
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

local syntax_scopes = {
  { "variable, variable.other", "@variable" },
  { "comment, punctuation.definition.comment", "@comment", "Comment" },
  { "string, punctuation.definition.string", "@string", "String" },
  { "string.regexp", "@string.regexp", "@string" },
  { "constant.character.escape", "@string.escape", "Special" },
  { "constant.character", "@character", "Character" },
  { "constant.numeric", "@number", "Number" },
  { "constant.language", "@boolean", "Boolean" },
  { "constant, support.constant, variable.other.constant", "@constant", "Constant" },
  { "keyword, storage, storage.modifier", "@keyword", "Keyword" },
  { "keyword.control.conditional, keyword.control.flow", "@keyword.conditional", "Conditional" },
  { "keyword.control.loop", "@keyword.repeat", "Repeat" },
  { "keyword.control.import, keyword.control.export, keyword.other.import, keyword.other.package", "@keyword.import", "Include" },
  { "keyword.control.exception, keyword.control.trycatch", "@keyword.exception", "Exception" },
  { "storage.type.function, keyword.declaration.function, keyword.other.def", "@keyword.function", "Keyword" },
  { "keyword.operator", "@operator", "Operator" },
  { "keyword.operator.word, keyword.operator.logical.python, keyword.operator.new", "@keyword.operator", "@keyword" },
  { "entity.name.function, support.function, variable.function, meta.function-call.generic", "@function", "Function" },
  { "support.function.builtin, support.function.builtin.python", "@function.builtin", "@function" },
  { "entity.name.type, entity.name.class, entity.name.struct, entity.name.enum, entity.name.trait, entity.name.interface, entity.other.inherited-class, support.type, support.class", "@type", "Type" },
  { "storage.type.primitive, storage.type.built-in, storage.type.builtin, support.type.builtin, support.type.primitive", "@type.builtin", "@type" },
  { "variable.parameter", "@variable.parameter", "@variable" },
  { "variable.language", "@variable.builtin", "@variable" },
  { "variable.other.member, variable.other.property, variable.other.object.property, meta.object-literal.key, support.type.property-name, entity.name.tag.yaml, meta.mapping.key string", "@property", "@variable" },
  { "entity.name.namespace, entity.name.module, entity.name.package, meta.path, support.other.namespace", "@module", "Include" },
  { "entity.name.tag", "@tag", "Tag" },
  { "entity.other.attribute-name", "@tag.attribute", "@attribute" },
  { "meta.annotation, storage.type.annotation, meta.decorator, punctuation.decorator, entity.name.function.decorator", "@attribute", "PreProc" },
  { "entity.name.label", "@label", "Label" },
  { "markup.heading, entity.name.section", "@markup.heading", "Title" },
  { "markup.bold", "@markup.strong" },
  { "markup.italic", "@markup.italic" },
  { "markup.raw, markup.inline.raw", "@markup.raw", "String" },
  { "markup.underline.link, markup.link", "@markup.link.url", "Underlined" },
  { "markup.quote", "@markup.quote", "Comment" },
  { "markup.list, punctuation.definition.list", "@markup.list", "Special" },
  { "invalid", "Error" },
}

local function nvim_syntax_theme_xml()
  local function hex(color)
    return color and ("#%06x"):format(color)
  end
  local function entry(scope, settings)
    local lines = { "<dict>" }
    if scope then
      vim.list_extend(lines, { "<key>scope</key>", "<string>" .. scope .. "</string>" })
    end
    table.insert(lines, "<key>settings</key><dict>")
    for _, key in ipairs({ "foreground", "background", "fontStyle" }) do
      if settings[key] then
        vim.list_extend(lines, { "<key>" .. key .. "</key>", "<string>" .. settings[key] .. "</string>" })
      end
    end
    vim.list_extend(lines, { "</dict>", "</dict>" })
    return table.concat(lines, "\n")
  end
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local entries = { entry(nil, { foreground = hex(normal.fg), background = hex(normal.bg) }) }
  for _, item in ipairs(syntax_scopes) do
    for i = 2, #item do
      local hl = vim.api.nvim_get_hl(0, { name = item[i], link = false })
      if hl.fg or hl.bold or hl.italic or hl.underline then
        local styles = vim.tbl_filter(function(style)
          return hl[style]
        end, { "bold", "italic", "underline" })
        table.insert(entries, entry(item[1], {
          foreground = hex(hl.fg),
          fontStyle = table.concat(styles, " "),
        }))
        break
      end
    end
  end
  return table.concat({
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0"><dict>',
    "<key>name</key><string>nvim</string>",
    "<key>settings</key><array>",
    table.concat(entries, "\n"),
    "</array></dict></plist>",
    "",
  }, "\n")
end

local function set_delta_env(theme)
  local function bg(group)
    return ("#%06x"):format(vim.api.nvim_get_hl(0, { name = group, link = false }).bg)
  end
  local params = {
    "'delta.minus-style'='normal " .. bg("ReviewMinus") .. "'",
    "'delta.minus-emph-style'='normal " .. bg("ReviewMinusEmph") .. "'",
    "'delta.plus-style'='syntax " .. bg("ReviewPlus") .. "'",
    "'delta.plus-emph-style'='syntax " .. bg("ReviewPlusEmph") .. "'",
  }
  if theme then
    table.insert(params, "'delta.syntax-theme'='" .. theme .. "'")
    vim.env.BAT_THEME = theme
  end
  vim.env.GIT_CONFIG_PARAMETERS = table.concat(params, " ")
end

local function sync_syntax_theme()
  set_delta_env(vim.g.nvim_syntax_theme)
  if vim.fn.executable("bat") == 0 then
    return
  end
  local xml = nvim_syntax_theme_xml()
  local source = vim.fn.stdpath("cache") .. "/bat"
  local file = source .. "/themes/nvim.tmTheme"
  local target = (vim.env.XDG_CACHE_HOME or vim.env.HOME .. "/.cache") .. "/bat"
  local built, written = vim.uv.fs_stat(target .. "/themes.bin"), vim.uv.fs_stat(file)
  if built and written and built.mtime.sec >= written.mtime.sec then
    local current = io.open(file, "rb")
    if current and current:read("*a") == xml then
      current:close()
      vim.g.nvim_syntax_theme = "nvim"
      set_delta_env("nvim")
      return
    end
    if current then
      current:close()
    end
  end
  vim.fn.mkdir(source .. "/themes", "p")
  local out = assert(io.open(file, "wb"))
  out:write(xml)
  out:close()
  vim.system({ "bat", "cache", "--build", "--source", source, "--target", target }, {}, function(result)
    if result.code == 0 then
      vim.schedule(function()
        vim.g.nvim_syntax_theme = "nvim"
        set_delta_env("nvim")
      end)
    end
  end)
end
vim.api.nvim_create_autocmd("ColorScheme", { callback = sync_syntax_theme })

local function color_diff_sides(tab)
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return
  end
  local sides = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.wo[win].diff and vim.w[win].review_folded ~= buf then
      vim.wo[win].foldlevel = 0
      vim.w[win].review_folded = buf
    elseif not vim.wo[win].diff and vim.w[win].review_folded then
      vim.wo[win].foldlevel = vim.go.foldlevel
      vim.w[win].review_folded = nil
    end
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
local function compact_review_tree(open_diff)
  local DiffPanel
  for i = 1, math.huge do
    local name, value = debug.getupvalue(open_diff, i)
    if not name then
      return
    end
    if name == "DiffPanel" then
      DiffPanel = value
      break
    end
  end
  local build_tree, highlight_tree, mark_current_file =
    DiffPanel.build_tree, DiffPanel.highlight_tree, DiffPanel.mark_current_file
  local function with_display_paths(self, action, ...)
    local saved = {}
    for i, entry in ipairs(self.entries) do
      saved[i] = entry.path
      entry.path = string.rep("/", (self.review_depths or {})[i] or 0) .. entry.path:match("[^/]*$")
    end
    local ok, err = pcall(action, self, ...)
    for i, entry in ipairs(self.entries) do
      entry.path = saved[i]
    end
    if not ok then
      error(err, 0)
    end
  end
  DiffPanel.highlight_tree = function(self, ...)
    with_display_paths(self, highlight_tree, ...)
  end
  DiffPanel.mark_current_file = function(self, ...)
    with_display_paths(self, mark_current_file, ...)
  end
  DiffPanel.build_tree = function(self)
    local lines = vim.list_slice(build_tree(self), 1, self.header_lines)
    local folds = {}
    for i = 1, self.header_lines do
      folds[i] = "0"
    end
    self.dirs, self.file_lnums, self.rows, self.nodes, self.review_depths = {}, {}, {}, {}, {}
    local children = {}
    for _, entry in ipairs(self.entries) do
      local parts = vim.split(entry.path, "/", { plain = true })
      local dir = ""
      for depth = 1, #parts do
        local child = depth < #parts and dir .. parts[depth] .. "/" or entry.path
        children[dir] = children[dir] or {}
        children[dir][child] = true
        dir = child
      end
    end
    local function single_child(path)
      local only = next(children[path])
      return next(children[path], only) == nil and only
    end
    for i, entry in ipairs(self.entries) do
      local parts = vim.split(entry.path, "/", { plain = true })
      local dir, depth, index = "", 0, 1
      while index < #parts do
        local first, path = index, dir .. parts[index] .. "/"
        while index + 1 < #parts and single_child(path) == path .. parts[index + 1] .. "/" do
          index = index + 1
          path = path .. parts[index] .. "/"
        end
        index, depth, dir = index + 1, depth + 1, path
        if not self.dirs[dir] then
          local names = {}
          for j = first, index - 1 do
            names[#names + 1] = (vim.fn.strtrans(parts[j]):gsub("^ ", "\\ "))
          end
          lines[#lines + 1] = string.rep("  ", depth - 1) .. " " .. table.concat(names, "/") .. "/"
          local node = {
            path = dir,
            lnum = #lines,
            first = i,
            last = i,
            directory = true,
            name = lines[#lines],
            added = 0,
            removed = 0,
            binary = false,
          }
          self.dirs[dir], self.rows[#lines], self.nodes[dir] = node, node, node
          folds[#lines] = ">" .. depth
        end
        local stats = self.dirs[dir]
        stats.last = i
        stats.added = stats.added + (entry.added or 0)
        stats.removed = stats.removed + (entry.removed or 0)
        stats.binary = stats.binary or not entry.added
      end
      local label = vim.fn.strtrans(parts[#parts])
      if entry.oldpath then
        label = vim.fn.strtrans(entry.oldpath) .. " -> " .. label
      end
      lines[#lines + 1] = string.rep("  ", depth) .. " " .. entry.status .. " " .. label
      self.file_lnums[#self.file_lnums + 1] = #lines
      self.review_depths[i] = depth
      local node = { path = entry.path, lnum = #lines, first = i, last = i }
      self.rows[#lines], self.nodes[entry.path] = node, node
      folds[#lines] = tostring(depth)
    end
    if #self.entries == 0 then
      lines[#lines + 1] = "No changes"
    end
    vim.list_extend(lines, { "", "g? help  <CR> open/fold  q close" })
    for i = #folds + 1, #lines do
      folds[i] = "0"
    end
    return lines, folds
  end
end
local unified_folds = {}
function _G.review_unified_foldexpr()
  local state = unified_folds[vim.api.nvim_get_current_win()]
  return state and not state.keep[vim.v.lnum] and 1 or 0
end
local function fold_unified(win)
  local view = review_view(win)
  if not view or not view.hunks then
    return
  end
  local keep, ranges = {}, {}
  for _, hunk in ipairs(view.hunks) do
    local first = math.max(hunk.added.start, 1)
    local last = first + math.max(hunk.added.count, 1) - 1
    table.insert(ranges, first .. "-" .. last)
    for lnum = first - 6, last + 6 do
      keep[lnum] = true
    end
  end
  local signature = table.concat(ranges, ",")
  local state = unified_folds[win]
  if not state then
    state = { saved = { vim.wo[win].foldmethod, vim.wo[win].foldexpr, vim.wo[win].foldlevel } }
    unified_folds[win] = state
    vim.wo[win].foldmethod = "expr"
    vim.wo[win].foldexpr = "v:lua.review_unified_foldexpr()"
  elseif state.signature == signature then
    return
  end
  state.keep, state.signature = keep, signature
  vim.wo[win].foldlevel = 0
  vim.api.nvim_win_call(win, function()
    vim.cmd("normal! zX")
  end)
end
local function unfold_unified(win)
  local state = unified_folds[win]
  unified_folds[win] = nil
  if state and vim.api.nvim_win_is_valid(win) then
    vim.wo[win].foldmethod, vim.wo[win].foldexpr, vim.wo[win].foldlevel = unpack(state.saved)
  end
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
local popup_items = {
  { "Preview Hunk", "<Cmd>Gitsigns preview_hunk_inline<CR>", "hunk" },
  { "Stage Hunk", "<Cmd>Gitsigns stage_hunk<CR>", "hunk" },
  { "Reset Hunk", "<Cmd>Gitsigns reset_hunk<CR>", "hunk" },
  { "Blame Line", "<Cmd>Gitsigns blame_line<CR>", "git" },
  { "Grep Word", "<Cmd>lua require('fzf-lua').grep_cword()<CR>" },
  { "Copy Path", "<Cmd>let @+ = expand('%:p')<CR>", "file" },
  { "Unified View", "<Space>gu", "review" },
  { "File List", "<Space>b", "review" },
  { "Next Change", "]c", "review" },
  { "Previous Change", "[c", "review" },
}
local function popup_name(label)
  return "PopUp." .. label:gsub(" ", "\\ ")
end
for index, item in ipairs(popup_items) do
  vim.cmd(("nmenu .%d %s %s"):format(index, popup_name(item[1]), item[2]))
end
vim.cmd("nnoremenu .99 PopUp.-mouse- <Nop>")
local function cursor_in_hunk()
  if not package.loaded.gitsigns then
    return false
  end
  local view = review_view(vim.api.nvim_get_current_win())
  local hunks = view and view.hunks or require("gitsigns").get_hunks() or {}
  local line = vim.fn.line(".")
  for _, hunk in ipairs(hunks) do
    local first = math.max(hunk.added.start, 1)
    if line >= first and line <= first + math.max(hunk.added.count, 1) - 1 then
      return true
    end
  end
  return false
end
vim.api.nvim_create_autocmd("MenuPopup", {
  callback = function()
    local enabled = {
      hunk = cursor_in_hunk(),
      git = vim.b.gitsigns_status_dict ~= nil,
      file = vim.bo.buftype == "" and vim.fn.expand("%") ~= "",
      review = review_panel() ~= nil,
    }
    for _, item in ipairs(popup_items) do
      local on = item[3] == nil or enabled[item[3]]
      vim.cmd(("nmenu %s %s"):format(on and "enable" or "disable", popup_name(item[1])))
    end
  end,
})
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

local function current_terminal()
  local buf = vim.api.nvim_get_current_buf()
  for _, term in ipairs(Snacks.terminal.list()) do
    if term.buf == buf then
      return term
    end
  end
end

local hidden_floats = {}

local function toggle_terminal()
  local term = vim.v.count == 0 and current_terminal()
  if term and term:is_floating() then
    hidden_floats = { focus = term }
    for _, t in ipairs(Snacks.terminal.list()) do
      if t:on_current_tab() and t:is_floating() then
        hidden_floats[#hidden_floats + 1] = t
        t:hide()
      end
    end
  elseif term then
    term:hide()
  else
    local restore = vim.v.count == 0 and vim.tbl_filter(function(t)
      return t:buf_valid() and not t:win_valid()
    end, hidden_floats) or {}
    local focus = hidden_floats.focus
    hidden_floats = {}
    if #restore == 0 then
      Snacks.terminal.toggle(nil, { count = vim.v.count1 })
      return
    end
    for _, t in ipairs(restore) do
      t:show()
    end
    if focus and focus:win_valid() then
      focus:focus()
    end
    vim.cmd.startinsert()
  end
end

local function new_terminal(position, win)
  local used = {}
  for _, term in ipairs(Snacks.terminal.list()) do
    used[vim.b[term.buf].snacks_terminal.id] = true
  end
  local count = 1
  while used[count] do
    count = count + 1
  end
  return Snacks.terminal.open(nil, { count = count, win = vim.tbl_extend("force", { position = position }, win or {}) })
end

local function split_terminal()
  local term = current_terminal()
  if not term or not term:is_floating() then
    new_terminal("right")
    return
  end
  local cfg = vim.api.nvim_win_get_config(term.win)
  local border = term:has_border() and 2 or 0
  local outer = cfg.width + border
  local left = math.floor(outer / 2)
  local gap = border == 0 and 1 or 0
  term.opts.width, term.opts.height = left - border - gap, cfg.height
  term.opts.col, term.opts.row = cfg.col, cfg.row
  term:update()
  new_terminal("float", {
    width = outer - left - border,
    height = cfg.height,
    col = cfg.col + left,
    row = cfg.row,
    backdrop = false,
  })
  vim.cmd.startinsert()
end

local function float_neighbor(key)
  local cur = vim.api.nvim_win_get_config(0)
  if cur.relative == "" or (key ~= "h" and key ~= "l") then
    return
  end
  local best, dist
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(win)
    if win ~= vim.api.nvim_get_current_win() and cfg.relative ~= "" and cfg.focusable ~= false
      and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "snacks_terminal" then
      local d = key == "h" and cur.col - cfg.col or cfg.col - cur.col
      if d > 0 and (not dist or d < dist) then
        best, dist = win, d
      end
    end
  end
  return best
end

local function pick_terminal()
  local items = {}
  for _, term in ipairs(Snacks.terminal.list()) do
    local id = vim.b[term.buf].snacks_terminal.id
    local title = vim.b[term.buf].term_title or ""
    if title == "" or title:find("^term://") then
      local pid = vim.fn.jobpid(vim.bo[term.buf].channel)
      local child = vim.fn.systemlist({ "pgrep", "-P", tostring(pid) })[1]
      title = vim.fn.system({ "ps", "-o", "comm=", "-p", child or tostring(pid) }):gsub("%s+$", ""):gsub("^.*/", "")
    end
    items[#items + 1] = { id = id, buf = term.buf, text = id .. ": " .. title }
  end
  if #items == 0 then
    vim.notify("No terminals", vim.log.levels.WARN)
    return
  end
  table.sort(items, function(a, b)
    return a.id < b.id
  end)
  Snacks.picker.pick({
    title = "Terminals",
    items = items,
    format = "text",
    layout = { preset = "select" },
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          for _, term in ipairs(Snacks.terminal.list()) do
            if term.buf == item.buf then
              term:show()
              term:focus()
              vim.cmd.startinsert()
              return
            end
          end
        end)
      end
    end,
  })
end

local function terminal_link(line, col)
  local start, finish = col, col
  local stop = "[%s\"'`()%[%]<>{}|,;]"
  while start > 1 and not line:sub(start - 1, start - 1):find(stop) do
    start = start - 1
  end
  while finish < #line and not line:sub(finish + 1, finish + 1):find(stop) do
    finish = finish + 1
  end
  local token = line:sub(start, finish):gsub("[.:]+$", "")
  if token == "" or token:find(stop) then
    return
  end
  local path, lnum, cnum = token:match("^(.-):(%d+):(%d+)$")
  if not path then
    path, lnum = token:match("^(.-):(%d+)$")
  end
  if not path then
    path, lnum = token:match("^(.-)#L(%d+)$")
  end
  path = path or token
  return path, tonumber(lnum), tonumber(cnum)
end

local function project_files(cwd, path)
  local root = vim.fn.systemlist({ "git", "-C", cwd, "rev-parse", "--show-toplevel" })[1]
  local files
  if vim.v.shell_error == 0 and root then
    files = vim.tbl_map(function(f)
      return vim.fs.joinpath(root, f)
    end, vim.fn.systemlist({ "git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard" }))
  else
    files = vim.fs.find(vim.fs.basename(path), { path = cwd, type = "file", limit = 50 })
  end
  local suffix = "/" .. path:gsub("^%./", "")
  return vim.tbl_filter(function(f)
    return f:sub(-#suffix) == suffix and vim.fn.filereadable(f) == 1
  end, files), root or cwd
end

local function open_terminal_link(win, lnum, col)
  local buf = vim.api.nvim_win_get_buf(win)
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
  local path, target_line, target_col = terminal_link(line, col)
  if not path then
    return
  end
  local info = vim.b[buf].snacks_terminal
  local cwd = info and info.cwd or vim.fn.getcwd(win)
  local function is_main(w)
    return vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_config(w).relative == ""
      and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == ""
  end
  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  local target = is_main(prev) and prev or vim.tbl_filter(is_main, vim.api.nvim_tabpage_list_wins(0))[1]
  local function open(file)
    if target and vim.api.nvim_win_is_valid(target) then
      vim.api.nvim_set_current_win(target)
    else
      vim.api.nvim_set_current_win(win)
      vim.cmd("aboveleft new")
    end
    vim.cmd.edit(vim.fn.fnameescape(file))
    if target_line then
      pcall(vim.api.nvim_win_set_cursor, 0, { target_line, math.max((target_col or 1) - 1, 0) })
      vim.cmd("normal! zz")
    end
  end
  local file = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  if vim.fn.filereadable(file) == 0 then
    file = vim.fs.joinpath(cwd, path)
  end
  local matches, root = {}, cwd
  if vim.fn.filereadable(file) == 0 then
    matches, root = project_files(cwd, path)
    if #matches == 0 then
      vim.notify("No file: " .. path, vim.log.levels.WARN)
      return
    end
    file = matches[1]
  end
  vim.cmd.stopinsert()
  if #matches <= 1 then
    vim.schedule(function()
      open(file)
    end)
    return
  end
  vim.schedule(function()
    Snacks.picker.pick({
      title = path,
      items = vim.tbl_map(function(f)
        return { file = f, text = vim.fs.relpath(root, f) or f }
      end, matches),
      format = "file",
      layout = { preset = "select" },
      confirm = function(picker, item)
        picker:close()
        if item then
          vim.schedule(function()
            open(item.file)
          end)
        end
      end,
    })
  end)
end

vim.api.nvim_create_autocmd("TermOpen", {
  callback = function(args)
    vim.keymap.set("n", "gf", function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      open_terminal_link(vim.api.nvim_get_current_win(), cursor[1], cursor[2] + 1)
    end, { buffer = args.buf, desc = "Open File Under Cursor" })
  end,
})

vim.keymap.set({ "n", "t" }, "<C-LeftMouse>", function()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 or vim.bo[vim.api.nvim_win_get_buf(pos.winid)].buftype ~= "terminal" then
    vim.api.nvim_feedkeys(vim.keycode("<C-LeftMouse>"), "n", false)
    return
  end
  open_terminal_link(pos.winid, pos.line, vim.fn.virtcol2col(pos.winid, pos.line, pos.column))
end, { desc = "Open File Under Mouse" })

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
                  ["<LeftRelease>"] = "click_confirm",
                  ["<leader>/"] = { "fzf_grep", desc = "Grep in Selected Dir" },
                  ["<leader>gf"] = { "git_history", desc = "Git History of Selected Path" },
                  ["<leader>gh"] = { "git_history", desc = "Git History of Selected Path" },
                },
              },
            },
            actions = {
              click_confirm = function(picker)
                local pos, list = vim.fn.getmousepos(), picker.list
                if pos.winid ~= list.win.win or pos.line == 0 then
                  return
                end
                local topline = vim.api.nvim_win_call(pos.winid, vim.fn.winsaveview).topline
                local idx = list:row2idx(pos.line - topline + 1)
                if idx < 1 or idx > list:count() then
                  return
                end
                list:_move(idx, true, true)
                picker:action("confirm")
              end,
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
      terminal = {
        win = {
          keys = {
            term_normal = false,
          },
        },
      },
      indent = {
        indent = {
          hl = { "SnacksIndent1", "SnacksIndent2", "SnacksIndent3", "SnacksIndent4", "SnacksIndent5", "SnacksIndent6", "SnacksIndent7", "SnacksIndent8" },
        },
      },
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
        nested = true,
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
      { "<C-/>", toggle_terminal, mode = { "n", "t" }, desc = "Terminal Toggle" },
      { "<C-_>", toggle_terminal, mode = { "n", "t" }, desc = "Terminal Toggle" },
      { "<leader>tv", split_terminal, desc = "Terminal Vertical Split" },
      { "<leader>ts", function() new_terminal("bottom") end, desc = "Terminal Horizontal Split" },
      { "<leader>tf", function() new_terminal("float") split_terminal() end, desc = "Terminal Float" },
      { "<leader>tt", pick_terminal, desc = "Terminal List" },
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
          if vim.wo[win].diff or review_view(win) then
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
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
      { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
      { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
      { "<c-s>", mode = "c", function() require("flash").toggle() end, desc = "Toggle Flash Search" },
    },
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
      local open_diff = require("gitsigns.actions.diff")
      compact_review_tree(open_diff)
      package.loaded["gitsigns.actions.diff"] = function(revision, paths, show_commit, opts)
        return open_diff(revision, paths, show_commit, vim.tbl_extend("keep", opts or {}, { diff = "unified" }))
      end
      local unified = require("gitsigns.unified")
      local reveal, close = unified.reveal, unified.close
      unified.reveal = function(win)
        reveal(win)
        fold_unified(win or vim.api.nvim_get_current_win())
      end
      unified.close = function(win, keep_base)
        close(win, keep_base)
        unfold_unified(win)
      end
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
  vim.keymap.set("n", "<C-" .. key .. ">", function()
    local neighbor = vim.bo.filetype == "snacks_terminal" and float_neighbor(key)
    if neighbor then
      vim.api.nvim_set_current_win(neighbor)
    else
      vim.cmd.wincmd(key)
    end
  end, { desc = "Window " .. key })
  vim.keymap.set("t", "<C-" .. key .. ">", function()
    local neighbor = vim.bo.filetype == "snacks_terminal" and float_neighbor(key)
    if neighbor then
      vim.schedule(function()
        vim.api.nvim_set_current_win(neighbor)
        vim.cmd.startinsert()
      end)
      return ""
    end
    if vim.bo.filetype == "fzf" or vim.api.nvim_win_get_config(0).relative ~= "" then
      return "<C-" .. key .. ">"
    end
    return "<C-\\><C-n><C-w>" .. key
  end, { expr = true, desc = "Window " .. key })
end

vim.keymap.set("t", "<C-Space>", "<C-\\><C-n>", { desc = "Terminal Normal Mode" })

vim.env.CLAUDE_CODE_FORCE_TERMINAL_IMAGES = "1"

vim.api.nvim_create_autocmd("TermRequest", {
  callback = function(args)
    local seq = args.data.sequence
    if seq:sub(1, 3) ~= "\27_G" then
      return
    end
    local control = seq:match("^\27_G([^;]*)") or ""
    if control:find("a=q", 1, true) then
      local id = control:match("i=(%d+)")
      pcall(vim.api.nvim_chan_send, vim.bo[args.buf].channel, "\27_G" .. (id and ("i=" .. id) or "") .. ";OK\27\\")
      return
    end
    vim.api.nvim_ui_send(seq .. (args.data.terminator or "\27\\"))
  end,
})
