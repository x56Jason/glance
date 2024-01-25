local glance = require("glance")
local Buffer = require("glance.buffer")
local LineBuffer = require('glance.line_buffer')

local M = {}

local function repeat_space(n)
	local str = ""
	for i = 1, n do
		str = str .. " "
	end
	return str
end

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
		filetype = "GlancePRList",
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
	local title = pr.title:match("%s*(.+)")
	local entry = string.format("%04d", pr.number) .. " " .. title

	local from = 0
	local to = 4
	add_highlight(highlights, #output + 1, from, to, "GlancePRListCommit")
	from = to + 1
	to = from + vim.fn.strlen(title)
	add_highlight(highlights, #output + 1, from, to, "GlancePRListSubject")

	local label_hl_name = {
		["openeuler-cla/yes"] = "GlancePRListCLAYes",
		["openeuler-cla/no"] = "GlancePRListCLANo",
		["lgtm"] = "GlancePRListLGTM",
		["ci_successful"] = "GlancePRListCISuccess",
		["ci_failed"] = "GlancePRListCIFail",
		["sig/Kernel"] = "GlancePRListSigKernel",
		["stat/needs-squash"] = "GlancePRListNeedSquash",
		["newcomer"] = "GlancePRListNewComer",
	}

	local label_start = 108
	local entry_width = vim.fn.strdisplaywidth(entry)
	if label_start > entry_width then
		local space_str = repeat_space(label_start - entry_width)
		entry = entry .. space_str
	else
		entry = entry .. "    "
	end
	local ref_str = "| " .. pr.base.ref
	if #ref_str < 25 then
		local space_str = repeat_space(25 - #ref_str)
		ref_str = ref_str .. space_str
	end
	entry = entry .. ref_str

	to = #entry
	for _, label in pairs(pr.labels) do
		local label_str = label.name
		entry = entry .. " | " .. label_str
		from = to + 3
		to = from + #label_str
		if label_hl_name[label_str] then
			add_highlight(highlights, #output + 1, from, to, label_hl_name[label_str])
		end
	end

	pr.text = entry
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

	self.buffer = buffer
	self.highlights = highlights

	vim.cmd("setlocal cursorline")

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
