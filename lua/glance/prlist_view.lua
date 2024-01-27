local glance = require("glance")
local Buffer = require("glance.buffer")
local LineBuffer = require('glance.line_buffer')

local M = {
	index = 0
}

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

function M.new(prlist, cmdline)
	local instance = {
		name = "GlancePRList-" .. M.index,
		cmdline = cmdline,
		prlist = prlist,
		buffer = nil,
	}
	M.index = M.index + 1

	setmetatable(instance, { __index = M })

	return instance
end

function M:close()
	glance.set_state(self.buffer.handle, nil)
	if self.buffer == nil then
		return
	end
	self.buffer:close()
	self.name = nil
	self.prlist = nil
	self.buffer = nil
end

function M:create_buffer()
	local prlist = self.prlist
	local config = {
		name = self.name,
		filetype = "GlancePRList",
		bufhidden = "hide",
		mappings = {
			n = {
				["<enter>"] = function()
					local line = vim.fn.line '.'
					local pr = prlist[line].number
					glance.do_glance_pr(pr)
				end,
				["<F5>"] = function()
					local cmdline = self.cmdline
					self:close()
					vim.cmd("redraw")
					vim.print("Refreshing pull request list...")
					vim.schedule(function()
						glance.do_glance_prlist(cmdline)
						vim.print("Refresh done")
					end)
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

local function find_pr_label(labels, label_names)
	for _, label in pairs(labels) do
		for _, label_name in ipairs(label_names) do
			if label.name == label_name then
				return label
			end
		end
	end
end

local function label_add_highlight(label, entry, highlights, line)
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

	local label_name = {
		["openeuler-cla/yes"] = "cla/yes",
		["openeuler-cla/no"] = "cla/no ",
		["lgtm"] = "lgtm",
		["ci_successful"] = "ci_ok    ",
		["ci_failed"] = "ci_failed",
		["stat/needs-squash"] = "squash",
		["newcomer"] = "newcomer",
	}
	local name = label_name[label.name]
	local to = #entry
	entry = entry .. " | " .. name
	local from = to + 3
	to = from + #name
	if label_hl_name[label.name] then
		add_highlight(highlights, line, from, to, label_hl_name[label.name])
	end
	return entry
end

local function prepare_one_pr(output, highlights, pr)
	local title = pr.title:match("%s*(.+)")
	if #title > 94 then
		title = title:sub(1, 94)
	end
	local entry = string.format("%04d", pr.number) .. " " .. title

	local from = 0
	local to = 4
	add_highlight(highlights, #output + 1, from, to, "GlancePRListCommit")
	from = to + 1
	to = from + vim.fn.strlen(title)
	add_highlight(highlights, #output + 1, from, to, "GlancePRListSubject")

	local label_start = 100
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

	local label = find_pr_label(pr.labels, {"openeuler-cla/yes", "openeuler-cla/no"})
	if label then
		entry = label_add_highlight(label, entry, highlights, #output+1)
	else
		entry = entry .. " |        "
	end

	label = find_pr_label(pr.labels, {"ci_successful", "ci_failed"})
	if label then
		entry = label_add_highlight(label, entry, highlights, #output+1)
	else
		entry = entry .. " |          "
	end

	label = find_pr_label(pr.labels, {"lgtm"})
	if label then
		entry = label_add_highlight(label, entry, highlights, #output+1)
	else
		entry = entry .. " |     "
	end

	label = find_pr_label(pr.labels, {"stat/needs-squash"})
	if label then
		entry = label_add_highlight(label, entry, highlights, #output+1)
	else
		entry = entry .. " |       "
	end

	-- no alignment since here

	label = find_pr_label(pr.labels, {"newcomer"})
	if label then
		entry = label_add_highlight(label, entry, highlights, #output+1)
	end

	entry = entry .. " | " .. pr.head.repo.full_name .. ":" .. pr.head.ref .. " -> " .. pr.base.repo.full_name .. ":" .. pr.base.ref

	pr.text = entry
	output:append(entry)
end

function M.fuzzy_filter()
	local bufnr = vim.api.nvim_get_current_buf()
	local prlist_view = glance.get_state(bufnr)

	local opts = { previewer = false }
	opts.attach_mappings = function(_, map)
		local actions = require("telescope.actions")
		local action_state = require "telescope.actions.state"
		map({"i", "n"}, "<c-a>", function(prompt_bufnr)
			actions.select_all(prompt_bufnr)
		end)
		map({"i", "n"}, "<c-g>", function(prompt_bufnr)
			local picker = action_state.get_current_picker(prompt_bufnr)
			local new_prlist = {}
			for _, entry in ipairs(picker:get_multi_selection()) do
				local pr = prlist_view.prlist[entry.lnum]
				table.insert(new_prlist, pr)
			end
			actions.close(prompt_bufnr)
			if #new_prlist == 0 then
				vim.notify("No entry selected", vim.log.levels.INFO, {})
				return
			end
			local new_view = require("glance.prlist_view").new(new_prlist)
			new_view:open()
		end)
		map({"i", "n"}, "<cr>", function(prompt_bufnr)
			actions.close(prompt_bufnr)
			local entry = action_state.get_selected_entry()
			if not entry then
				vim.notify("No entry selected", vim.log.levels.INFO, {})
				return
			end
			local pr = prlist_view.prlist[entry.lnum]
			glance.do_glance_pr(pr.number)
		end)
		return true
	end
	require("telescope.builtin").current_buffer_fuzzy_find(opts)
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

	local bufnr = vim.api.nvim_get_current_buf()
	glance.set_state(bufnr, self)

	vim.api.nvim_buf_set_keymap(0, "n", "<c-g>",
		"<cmd>lua require('glance.prlist_view').fuzzy_filter()<CR>",
		{noremap = true, silent = true})

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
