local glance = require("glance")
local Buffer = require("glance.buffer")
local CommitView = require("glance.commit_view")
local LineBuffer = require('glance.line_buffer')

local M = {}

local function parse_log(output)
	local output_len = #output
	local commits = {}

	for i=1,output_len do
		local hash, rest = output[i]:match("([a-zA-Z0-9]+) (.*)")
		if hash ~= nil then
			local remote, message = rest:match("^%((.+)%) (.*)")
			if remote == nil then
				message = rest
			end

			local commit = {
				hash = hash,
				remote = remote or "",
				message = message
			}
			table.insert(commits, commit)
		end
	end

	return commits
end

function M.new(cmdline)
	local commit_limit = "-256"
	if cmdline ~= "" then
		commit_limit = cmdline
	end
	local cmd = "git log --oneline --no-abbrev-commit --decorate " .. commit_limit
	local raw_output = vim.fn.systemlist(cmd)
	local commits = parse_log(raw_output)

	local instance = {
		commits = commits,
		buffer = nil,
	}

	setmetatable(instance, { __index = M })

	return instance
end

function M:open_commit_view(commit)
	local view = CommitView.new(commit)
	if (view == nil) then
		vim.notify("Bad commit: " .. commit, vim.log.levels.ERROR, {})
		return
	end
	view:open()
	view:initialize()
end

function M:open_parallel_views(commit)
	local upstream_commit_id = CommitView.get_upstream_commit(commit)

	if upstream_commit_id == nil then
		vim.notify("Not a backport commit", vim.log.levels.ERROR, {})
		return
	end

	local view_left = CommitView.new(upstream_commit_id)
	if (view_left == nil) then
		vim.notify("Bad commit: " .. upstream_commit_id, vim.log.levels.ERROR, {})
		return
	end
	view_left:open({name = "Upstream: " .. upstream_commit_id})
	view_left:initialize()
	vim.cmd("wincmd o")
	vim.cmd(string.format("%d", view_left:get_first_hunk_line()))
	vim.cmd.normal("zz")
	vim.cmd("set scrollbind")

	local view_right = CommitView.new(commit)
	if (view_right == nil) then
		vim.notify("Bad commit: " .. commit, vim.log.levels.ERROR, {})
		view_left:close()
		return
	end
	view_right:open({name = "Backport: " .. commit})
	view_right:initialize()
	vim.cmd("wincmd L")
	vim.cmd(string.format("%d", view_right:get_first_hunk_line()))
	vim.cmd.normal("zz")
	vim.cmd("set scrollbind")

	view_left:set_scrollbind_view(view_right)
	view_right:set_scrollbind_view(view_left)
end

function M:open_patchdiff_view(commit)
	local view = CommitView.new_patchdiff(commit)
	if not view then return end
	view:open({filetype="GlancePatchDiff"})
	view:initialize()
end

function M:close()
	if self.buffer == nil or glance.config.q_quit_log == "off" then
		return
	end
	self.buffer:close()
	self.buffer = nil
end

function M:create_buffer()
	local commits = self.commits
	local config = {
		name = "GlanceLog",
		filetype = "GlanceLog",
		bufhidden = "hide",
		mappings = {
			n = {
				["<enter>"] = function()
					local line = vim.fn.line '.'
					local commit = commits[line].hash
					self:open_commit_view(commit)
				end,
				["l"] = function()
					local line = vim.fn.line '.'
					local commit = commits[line].hash
					self:open_parallel_views(commit)
				end,
				["p"] = function()
					local line = vim.fn.line '.'
					local commit = commits[line].hash
					self:open_patchdiff_view(commit)
				end,
				["q"] = function()
					self:close()
				end
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

	for _, commit in pairs(self.commits) do
		if commit.remote == "" then
			output:append(string.sub(commit.hash, 1, 12) .. " " .. commit.message)
		else
			output:append(string.sub(commit.hash, 1, 12) .. " (" .. commit.remote .. ") " .. commit.message)
		end

		local from = 0
		local to = 12 -- length of abrev commit_id
		add_highlight(from, to, "GlanceLogCommit")
		from = to + 1
		if commit.remote ~= "" then
			to = from + #commit.remote + 2
			add_highlight(from, to, "GlanceLogRemote")
			from = to + 1
		end
		to = from + #commit.message
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
