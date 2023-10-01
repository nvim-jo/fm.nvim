local fm = require("fm")
local util = require("fm.util")

local M = {}

M.show_help = {
  desc = "Show default keymaps",
  callback = function()
    local config = require("fm.config")
    require("fm.keymap_util").show_help(config.keymaps)
  end,
}

M.select = {
  desc = "Open the entry under the cursor",
  callback = fm.select,
}

M.select_vsplit = {
  desc = "Open the entry under the cursor in a vertical split",
  callback = function()
    fm.select({ vertical = true })
  end,
}

M.select_split = {
  desc = "Open the entry under the cursor in a horizontal split",
  callback = function()
    fm.select({ horizontal = true })
  end,
}

M.select_tab = {
  desc = "Open the entry under the cursor in a new tab",
  callback = function()
    fm.select({ tab = true })
  end,
}

M.preview = {
  desc = "Open the entry under the cursor in a preview window, or close the preview window if already open",
  callback = function()
    local entry = fm.get_cursor_entry()
    if not entry then
      vim.notify("Could not find entry under cursor", vim.log.levels.ERROR)
      return
    end
    local winid = util.get_preview_win()
    if winid then
      local cur_id = vim.w[winid].fm_entry_id
      if entry.id == cur_id then
        vim.api.nvim_win_close(winid, true)
        return
      end
    end
    fm.select({ preview = true })
  end,
}

M.preview_scroll_down = {
  desc = "Scroll down in the preview window",
  callback = function()
    local winid = util.get_preview_win()
    if winid then
      vim.api.nvim_win_call(winid, function()
        vim.cmd.normal({
          args = { vim.api.nvim_replace_termcodes("<C-d>", true, true, true) },
          bang = true,
        })
      end)
    end
  end,
}

M.preview_scroll_up = {
  desc = "Scroll up in the preview window",
  callback = function()
    local winid = util.get_preview_win()
    if winid then
      vim.api.nvim_win_call(winid, function()
        vim.cmd.normal({
          args = { vim.api.nvim_replace_termcodes("<C-u>", true, true, true) },
          bang = true,
        })
      end)
    end
  end,
}

M.parent = {
  desc = "Navigate to the parent path",
  callback = fm.open,
}

M.close = {
  desc = "Close fm and restore original buffer",
  callback = fm.close,
}

---@param cmd string
local function cd(cmd)
  local dir = fm.get_current_dir()
  if dir then
    vim.cmd({ cmd = cmd, args = { dir } })
  else
    vim.notify("Cannot :cd; not in a directory", vim.log.levels.WARN)
  end
end

M.cd = {
  desc = ":cd to the current fm directory",
  callback = function()
    cd("cd")
  end,
}

M.tcd = {
  desc = ":tcd to the current fm directory",
  callback = function()
    cd("tcd")
  end,
}

M.open_cwd = {
  desc = "Open fm in Neovim's current working directory",
  callback = function()
    fm.open(vim.fn.getcwd())
  end,
}

M.toggle_hidden = {
  desc = "Toggle hidden files and directories",
  callback = function()
    require("fm.view").toggle_hidden()
  end,
}

M.open_terminal = {
  desc = "Open a terminal in the current directory",
  callback = function()
    local config = require("fm.config")
    local bufname = vim.api.nvim_buf_get_name(0)
    local adapter = config.get_adapter_by_scheme(bufname)
    if not adapter then
      return
    end
    if adapter.name == "files" then
      local dir = fm.get_current_dir()
      assert(dir, "FM buffer with files adapter must have current directory")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.fn.termopen(vim.o.shell, { cwd = dir })
    elseif adapter.name == "ssh" then
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      local url = require("fm.adapters.ssh").parse_url(bufname)
      local cmd = require("fm.adapters.ssh.connection").create_ssh_command(url)
      local term_id = vim.fn.termopen(cmd)
      if term_id then
        vim.api.nvim_chan_send(term_id, string.format("cd %s\n", url.path))
      end
    else
      vim.notify(
        string.format("Cannot open terminal for unsupported adapter: '%s'", adapter.name),
        vim.log.levels.WARN
      )
    end
  end,
}

---Copied from vim.ui.open in Neovim 0.10+
---@param path string
---@return nil|string[] cmd
---@return nil|string error
local function get_open_cmd(path)
  if vim.fn.has("mac") == 1 then
    return { "open", path }
  elseif vim.fn.has("win32") == 1 then
    if vim.fn.executable("rundll32") == 1 then
      return { "rundll32", "url.dll,FileProtocolHandler", path }
    else
      return nil, "rundll32 not found"
    end
  elseif vim.fn.executable("wslview") == 1 then
    return { "wslview", path }
  elseif vim.fn.executable("xdg-open") == 1 then
    return { "xdg-open", path }
  else
    return nil, "no handler found"
  end
end

M.open_external = {
  desc = "Open the entry under the cursor in an external program",
  callback = function()
    local entry = fm.get_cursor_entry()
    local dir = fm.get_current_dir()
    if not entry or not dir then
      return
    end
    local path = dir .. entry.name
    -- TODO use vim.ui.open once this is resolved
    -- https://github.com/neovim/neovim/issues/24567
    local cmd, err = get_open_cmd(path)
    if not cmd then
      vim.notify(string.format("Could not open %s: %s", path, err), vim.log.levels.ERROR)
      return
    end
    local jid = vim.fn.jobstart(cmd, { detach = true })
    assert(jid > 0, "Failed to start job")
  end,
}

M.refresh = {
  desc = "Refresh current directory list",
  callback = function()
    if vim.bo.modified then
      local ok, choice = pcall(vim.fn.confirm, "Discard changes?", "No\nYes")
      if not ok or choice ~= 2 then
        return
      end
    end
    vim.cmd.edit({ bang = true })
  end,
}

local function open_cmdline_with_args(args)
  local escaped = vim.api.nvim_replace_termcodes(
    ": " .. args .. string.rep("<Left>", args:len() + 1),
    true,
    false,
    true
  )
  vim.api.nvim_feedkeys(escaped, "n", true)
end

M.open_cmdline = {
  desc = "Open vim cmdline with current entry as an argument",
  callback = function()
    local config = require("fm.config")
    local fs = require("fm.fs")
    local entry = fm.get_cursor_entry()
    if not entry then
      return
    end
    local bufname = vim.api.nvim_buf_get_name(0)
    local scheme, path = util.parse_url(bufname)
    if not scheme then
      return
    end
    local adapter = config.get_adapter_by_scheme(scheme)
    if not adapter or not path or adapter.name ~= "files" then
      return
    end
    local fullpath = fs.shorten_path(fs.posix_to_os_path(path) .. entry.name)
    open_cmdline_with_args(fullpath)
  end,
}

M.copy_entry_path = {
  desc = "Yank the filepath of the entry under the cursor to a register",
  callback = function()
    local entry = fm.get_cursor_entry()
    local dir = fm.get_current_dir()
    if not entry or not dir then
      return
    end
    vim.fn.setreg(vim.v.register, dir .. entry.name)
  end,
}

M.open_cmdline_dir = {
  desc = "Open vim cmdline with current directory as an argument",
  callback = function()
    local fs = require("fm.fs")
    local dir = fm.get_current_dir()
    if dir then
      open_cmdline_with_args(fs.shorten_path(dir))
    end
  end,
}

M.change_sort = {
  desc = "Change the sort order",
  callback = function()
    local sort_cols = { "name", "size", "atime", "mtime", "ctime", "birthtime" }
    vim.ui.select(sort_cols, { prompt = "Sort by", kind = "fm_sort_col" }, function(col)
      if not col then
        return
      end
      vim.ui.select(
        { "ascending", "descending" },
        { prompt = "Sort order", kind = "fm_sort_order" },
        function(order)
          if not order then
            return
          end
          order = order == "ascending" and "asc" or "desc"
          fm.set_sort({
            { "type", "asc" },
            { col, order },
          })
        end
      )
    end)
  end,
}

---List actions for documentation generation
---@private
M._get_actions = function()
  local ret = {}
  for name, action in pairs(M) do
    if type(action) == "table" and action.desc then
      table.insert(ret, {
        name = name,
        desc = action.desc,
      })
    end
  end
  return ret
end

return M
