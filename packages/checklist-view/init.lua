local api = vim.api
local keys = vim.keymap.set

vim.opt.autoread = true
vim.opt.exrc = false
vim.opt.modeline = false
vim.opt.swapfile = false
-- Neovim wraps at the source width, even where link destinations are concealed.
vim.opt.wrap = false
vim.opt.shiftwidth = 2
vim.opt.mouse = 'a'
vim.opt.showmode = false
vim.opt.showcmd = false
vim.opt.laststatus = 2
vim.opt.fillchars:append({ eob = ' ' })

require('markview').setup({
  preview = { modes = { 'n', 'no', 'c', 'v', 'V' }, map_gx = false },
  markdown = { headings = { heading_1 = { sign = '', icon = '' } } },
  markdown_inline = {
    hyperlinks = { default = { icon = '' } },
    checkboxes = {
      unchecked = { text = '□' },
      ['/'] = { text = '◩' },
      checked = { text = '✓' },
    },
  },
})

function _G.checklist_help()
  if api.nvim_get_mode().mode:sub(1, 1) == 'i' then
    return ' Esc Preview    ^S Save'
  elseif api.nvim_win_get_width(0) < 68 then
    return ' SPC State  ↵ Link  e Edit  ^S Save  q Quit'
  end
  return ' Space Cycle status   Enter Open link   e Edit   ^S Save   q Quit'
end

vim.opt.statusline = '%{v:lua.checklist_help()}%<%=%m'

local function cycle_status()
  local line = api.nvim_get_current_line()
  local next_state = { [' '] = '/', ['/'] = 'x', x = ' ', X = ' ' }
  local updated, count = line:gsub('^(%s*[-+*]%s+%[)([ /xX])(%])', function(before, state, after)
    return before .. next_state[state] .. after
  end, 1)
  if count ~= 0 then
    api.nvim_set_current_line(updated)
  end
end

local function link_at(row, col)
  local node = vim.treesitter.get_node({ pos = { row, col }, ignore_injections = false })
  while node and node:type() ~= 'inline_link' do
    node = node:parent()
  end
  return node
end

local function open_link()
  if vim.bo.filetype ~= 'markdown' then
    return
  end
  local cursor = api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local node = link_at(row, cursor[2])
  if not node then
    -- A single runbook link is usually at the end of the task row.
    for col in api.nvim_get_current_line():gmatch('()%[') do
      node = link_at(row, col - 1)
      if node then
        break
      end
    end
  end
  if not node then
    vim.notify('No link on this line')
    return
  end
  for child in node:iter_children() do
    if child:type() == 'link_destination' then
      local dest = vim.treesitter.get_node_text(child, 0):gsub('^<(.*)>$', '%1')
      if dest:match('^https?://') then
        vim.ui.open(dest)
      elseif not dest:match('^[%a][%w+.-]*:') then
        local path = dest:match('^[^#]+')
        if not path then
          return
        end
        path = path:gsub('%%(%x%x)', function(hex)
          return string.char(tonumber(hex, 16))
        end)
        if path:sub(1, 1) ~= '/' then
          path = vim.fs.dirname(api.nvim_buf_get_name(0)) .. '/' .. path
        end
        path = vim.fs.normalize(path, { expand_env = false })
        if vim.fn.filereadable(path) == 1 then
          api.nvim_cmd({ cmd = 'edit', args = { path }, mods = { hide = true }, magic = { file = false } }, {})
        else
          vim.notify('Link target not found: ' .. path, vim.log.levels.WARN)
        end
      end
      return
    end
  end
end

keys('n', '<Space>', cycle_status)
keys('n', '<CR>', open_link)
keys('n', 'e', 'i')
keys('n', '<C-s>', '<Cmd>write<CR>')
keys('i', '<C-s>', '<Esc><Cmd>write<CR>')
keys('n', 'q', '<Cmd>qall<CR>')

-- Focus events are not enough: the checklist must update while the pane is idle.
api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    local timer = assert(vim.uv.new_timer())
    timer:start(1000, 1000, vim.schedule_wrap(function()
      local buf = api.nvim_get_current_buf()
      if vim.bo[buf].buftype == '' and not vim.bo[buf].modified and api.nvim_get_mode().mode == 'n' then
        local tick = api.nvim_buf_get_changedtick(buf)
        vim.cmd.checktime(buf)
        if vim.bo[buf].filetype == 'markdown' and api.nvim_buf_get_changedtick(buf) ~= tick then
          vim.cmd.Markview({ args = { 'render', tostring(buf) } })
        end
      end
    end))
    api.nvim_create_autocmd('VimLeavePre', {
      once = true,
      callback = function()
        timer:close()
      end,
    })
  end,
})
