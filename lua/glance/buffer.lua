
local mappings_manager = require("glance.mappings_manager")

local Buffer = {
	handle = nil,
}
Buffer.__index = Buffer

function Buffer:new(handle)
	local this = {
		handle = handle,
		border = nil,
		mmanager = mappings_manager.new()
	}

	setmetatable(this, self)

	return this
end

function Buffer:focus()
	local windows = vim.fn.win_findbuf(self.handle)

	if #windows == 0 then
		return
	end

	vim.fn.win_gotoid(windows[1])
end

function Buffer:lock()
	self:set_option("readonly", true)
	self:set_option("modifiable", false)
end

function Buffer:define_autocmd(events, script)
	vim.cmd(string.format("au %s <buffer=%d> %s", events, self.handle, script))
end

function Buffer:clear()
	vim.api.nvim_buf_set_lines(self.handle, 0, -1, false, {})
end

function Buffer:get_lines(first, last, strict)
	return vim.api.nvim_buf_get_lines(self.handle, first, last, strict)
end

function Buffer:set_lines(first, last, strict, lines)
	vim.api.nvim_buf_set_lines(self.handle, first, last, strict, lines)
end

function Buffer:set_text(first_line, last_line, first_col, last_col, lines)
	vim.api.nvim_buf_set_text(self.handle, first_line, first_col, last_line, last_col, lines)
end

function Buffer:move_cursor(line)
	if line < 0 then
		self:focus()
		vim.cmd("norm G")
	else
		self:focus()
		vim.cmd("norm " .. line .. "G")
	end
end

function Buffer:close(force)
	if force == nil then
		force = false
	end
	vim.api.nvim_buf_delete(self.handle, { force = force })
	if self.border_buffer then
		vim.api.nvim_buf_delete(self.border_buffer, {})
	end
end

function Buffer:put(lines, after, follow)
	self:focus()
	vim.api.nvim_put(lines, "l", after, follow)
end

function Buffer:create_fold(first, last)
	vim.cmd(string.format(self.handle .. "bufdo %d,%dfold", first, last))
end

function Buffer:unlock()
	self:set_option("readonly", false)
	self:set_option("modifiable", true)
end

function Buffer:get_option(name)
	vim.api.nvim_buf_get_option(self.handle, name)
end

function Buffer:set_option(name, value)
	vim.api.nvim_buf_set_option(self.handle, name, value)
end

function Buffer:set_name(name)
	vim.api.nvim_buf_set_name(self.handle, name)
end

function Buffer:set_foldlevel(level)
	vim.cmd("setlocal foldlevel=" .. level)
end

function Buffer:replace_content_with(lines)
	self:set_lines(0, -1, false, lines)
end

function Buffer:open_fold(line, reset_pos)
	local pos
	if reset_pos == true then
		pos = vim.fn.getpos()
	end

	vim.fn.setpos('.', {self.handle, line, 0, 0})
	vim.cmd('normal zo')

	if reset_pos == true then
		vim.fn.setpos('.', pos)
	end
end

function Buffer:add_highlight(line, col_start, col_end, name, ns_id)
	local ns_id = ns_id or 0

	vim.api.nvim_buf_add_highlight(self.handle, ns_id, name, line, col_start, col_end)
end

function Buffer:place_sign(line, name, group, id)
	local sign_id = id or 1
	vim.api.nvim_buf_set_extmark(self.handle, sign_id, line - 1, 0, {end_row = line - 1, line_hl_group=name})
end

function Buffer:get_sign_at_line(line, group)
	group = group or "*"
	return vim.fn.sign_getplaced(self.handle, {
		group = group,
		lnum = line
	})[1]
end

function Buffer:clear_sign_group(group)
	vim.cmd('sign unplace * group='..group..' buffer='..self.handle)
end

function Buffer:set_filetype(ft)
	vim.cmd("setlocal filetype=" .. ft)
end

function Buffer:call(f)
	vim.api.nvim_buf_call(self.handle, f)
end

function Buffer.exists(name)
	return vim.fn.bufnr(name) ~= -1
end

function Buffer:set_extmark(...)
	return vim.api.nvim_buf_set_extmark(self.handle, ...)
end

function Buffer:get_extmark(ns, id)
	return vim.api.nvim_buf_get_extmark_by_id(self.handle, ns, id, { details = true })
end

function Buffer:del_extmark(ns, id)
	return vim.api.nvim_buf_del_extmark(self.handle, ns, id)
end

function Buffer.create(config)
	local config = config or {}
	local kind = config.kind or "split"
	local buffer = nil

	if kind == "tab" then
		vim.cmd("tabnew")
		buffer = Buffer:new(vim.api.nvim_get_current_buf())
	elseif kind == "split" then
		vim.cmd("below new")
		buffer = Buffer:new(vim.api.nvim_get_current_buf())
	elseif kind == "vsplit" then
		vim.cmd("bot vnew")
		buffer = Buffer:new(vim.api.nvim_get_current_buf())
	end

	if buffer == nil then
		return nil
	end

	vim.cmd("setlocal nonu")
	vim.cmd("setlocal nornu")

	buffer:set_name(config.name)

	buffer:set_option("bufhidden", config.bufhidden or "wipe")
	buffer:set_option("buftype", config.buftype or "nofile")
	buffer:set_option("swapfile", false)

	if config.filetype then
		buffer:set_filetype(config.filetype)
	end

	if config.mappings then
		for mode, val in pairs(config.mappings) do
			for key, cb in pairs(val) do
				buffer.mmanager.mappings[key] = { mode, function() cb(buffer) end, mode:find("v") ~= nil }
			end
		end
	end

	buffer.mmanager.register()

	return buffer
end

return Buffer
