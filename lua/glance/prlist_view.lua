local glance = require("glance")
local Buffer = require("glance.buffer")
local LineBuffer = require('glance.line_buffer')

local M = {}

local function add_highlight(highlights, line, from, to, name)
	table.insert(highlights, {
		line = line - 1,
		from = from,
		to = to,
		name = name
	})
end

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

local function prepare_one_pr(output, highlights, pr)
	local title = pr.title:match("%s*(.+)") .. "                        "
	local entry = string.format("%04d", pr.number) .. " " .. title

	local from = 0
	local to = 4
	add_highlight(highlights, #output + 1, from, to, "GlanceLogCommit")
	from = to + 1
	to = from + #title
	add_highlight(highlights, #output + 1, from, to, "GlanceLogSubject")

	local label_hl_name = {
		["openeuler-cla/yes"] = "GlanceLogCLAYes",
		["lgtm"] = "GlanceLogLGTM",
		["ci_successful"] = "GlanceLogCISuccess",
		["sig/Kernel"] = "GlanceLogSigKernel",
		["stat/needs-squash"] = "GlanceLogNeedSquash",
		["newcomer"] = "GlanceLogNewComer",
	}

	for _, label in pairs(pr.labels) do
		local label_str = label.name
		entry = entry .. " | " .. label_str
		from = to + 3
		to = from + #label_str
		if label_hl_name[label_str] then
			add_highlight(highlights, #output + 1, from, to, label_hl_name[label_str])
		end
	end

	output:append(entry)
end

function M:open_buffer()
	local buffer = self.buffer
	if buffer == nil then
		return
	end

	local output = LineBuffer.new()
	local highlights = {}

	for _, pr in ipairs(self.prlist) do
		prepare_one_pr(output, highlights, pr)
	end

	buffer:replace_content_with(output)

	for _, hi in ipairs(highlights) do
		buffer:add_highlight(hi.line, hi.from, hi.to, hi.name)
	end

	buffer:set_option("modifiable", false)
	buffer:set_option("readonly", true)

	M.buffer = buffer
	M.highlights = highlights

	vim.cmd("hi CursorLine cterm=NONE ctermbg=darkred ctermfg=white guibg=darkred guifg=white")
	--vim.cmd("hi CursorLine cterm=NONE ctermbg=#dc322f ctermfg=white guibg=#dc322f guifg=white")
	vim.cmd("setlocal cursorline")

	vim.api.nvim_create_autocmd({"ColorScheme"}, {
		pattern = { "*" },
		callback = function()
			--vim.cmd("hi CursorLine cterm=NONE ctermbg=#dc322f ctermfg=white guibg=#dc322f guifg=white")
			vim.cmd("hi CursorLine cterm=NONE ctermbg=darkred ctermfg=white guibg=darkred guifg=white")
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
