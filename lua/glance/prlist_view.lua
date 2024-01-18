local glance = require("glance")
local Buffer = require("glance.buffer")
local LineBuffer = require('glance.line_buffer')

local M = {}

function M.new(prlist)
	local instance = {
		prlist = prlist,
		buffer = nil,
	}

	setmetatable(instance, { __index = M })

	return instance
end

function M:close()
	if self.buffer == nil then
		return
	end
	self.buffer:close()
	self.buffer = nil
end

function M:create_buffer()
	local prlist = self.prlist
	local config = {
		name = "GlancePRList",
		filetype = "GlanceLog",
		bufhidden = "hide",
		mappings = {
			n = {
				["<enter>"] = function()
					local line = vim.fn.line '.'
					local pr = prlist[line].number
					glance.do_glance_pr(pr)
				end,
			}
		},
	}

	local buffer = Buffer.create(config)
	if buffer == nil then
		return
	end
	vim.cmd("wincmd o")

	self.buffer = buffer
end

function M:open_buffer()
	local buffer = self.buffer
	if buffer == nil then
		return
	end

	local output = LineBuffer.new()
	local highlights = {}

	local function add_highlight(from, to, name)
		table.insert(highlights, {
			line = #output - 1,
			from = from,
			to = to,
			name = name
		})
	end

	for _, pr in ipairs(self.prlist) do
		local title = pr.title:match("%s*(.+)")
		output:append(string.format("%04d", pr.number) .. " " .. title)
		local from = 0
		local to = 4
		add_highlight(from, to, "GlanceLogCommit")
		from = to + 1
		to = from + #title
		add_highlight(from, to, "GlanceLogSubject")
	end

	buffer:replace_content_with(output)

	for _, hi in ipairs(highlights) do
		buffer:add_highlight(hi.line, hi.from, hi.to, hi.name)
	end
	buffer:set_option("modifiable", false)
	buffer:set_option("readonly", true)

	M.buffer = buffer
	M.highlights = highlights
	vim.api.nvim_create_autocmd({"ColorScheme"}, {
		pattern = { "*" },
		callback = function()
			vim.cmd("syntax on")
		end,
	})
end

function M:open()
	self:create_buffer()
	if self.buffer == nil then
		return
	end

	self:open_buffer()
end

return M
