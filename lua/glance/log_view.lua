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

local function get_table_size(t)
    local count = 0
    for _, __ in pairs(t) do
        count = count + 1
    end
    return count
end

function M.new(cmdline, pr)
	local pr_number = pr.number
	local desc_head = pr.desc_head
	local desc_body = pr.desc_body

	local commit_limit = "-256"
	if cmdline ~= "" then
		commit_limit = cmdline
	end
	local cmd = "git log --oneline --no-abbrev-commit --decorate " .. commit_limit
	local raw_output = vim.fn.systemlist(cmd)
	local commits = parse_log(raw_output)
	local commit_start_line = 1
	if desc_body then
		commit_start_line = commit_start_line + 2 + get_table_size(desc_head) + 1 + #desc_body + 1
	end
	local comment_start_line = commit_start_line + get_table_size(commits) + 1

	local comments = {}
	if pr_number then
		comments = glance.get_pr_comments(pr_number)
	end

	local instance = {
		pr_number = pr_number,
		labels = pr.labels,
		head = desc_head,
		body = desc_body,
		commits = commits,
		commit_start_line = commit_start_line,
		comments = comments,
		comment_start_line = comment_start_line,
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
	local view_right = CommitView.new(commit)
	if (view_right == nil) then
		vim.notify("Bad commit: " .. commit, vim.log.levels.ERROR, {})
		view_left:close()
		return
	end

	CommitView.sort_diffs_file(view_left, view_right)

	view_left:open({name = "Upstream: " .. upstream_commit_id})
	view_left:initialize()
	vim.cmd("wincmd o")
	vim.cmd(string.format("%d", view_left:get_first_hunk_line()))
	vim.cmd.normal("zz")
	vim.cmd("set scrollbind")

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
	local commit_start_line = self.commit_start_line
	local commit_count = get_table_size(self.commits)
	local config = {
		name = "GlanceLog",
		filetype = "GlanceLog",
		bufhidden = "hide",
		mappings = {
			n = {
				["<enter>"] = function()
					local line = vim.fn.line '.'
					if line >= commit_start_line and line < commit_start_line + commit_count then
						line = line - commit_start_line + 1
						local commit = commits[line].hash
						self:open_commit_view(commit)
						return
					end
					vim.notify("Not a commit", vim.log.levels.WARN)
				end,
				["l"] = function()
					local line = vim.fn.line '.'
					if line >= commit_start_line and line < commit_start_line + commit_count then
						line = line - commit_start_line + 1
						local commit = commits[line].hash
						self:open_parallel_views(commit)
						return
					end
					vim.notify("Not a commit", vim.log.levels.WARN)
				end,
				["p"] = function()
					local line = vim.fn.line '.'
					if line >= commit_start_line and line < commit_start_line + commit_count then
						line = line - commit_start_line + 1
						local commit = commits[line].hash
						self:open_patchdiff_view(commit)
						return
					end
					vim.notify("Not a commit", vim.log.levels.WARN)
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
	local signs = {}
	local highlights = {}

	local function add_sign(name)
		signs[#output] = name
	end

	local function add_highlight(from, to, name)
		table.insert(highlights, {
			line = #output - 1,
			from = from,
			to = to,
			name = name
		})
	end

	if self.body then
		local label_hl_name = {
			["openeuler-cla/yes"] = "GlanceLogCLAYes",
			["lgtm"] = "GlanceLogLGTM",
			["ci_successful"] = "GlanceLogCISuccess",
			["sig/Kernel"] = "GlanceLogSigKernel",
			["stat/needs-squash"] = "GlanceLogNeedSquash",
			["newcomer"] = "GlanceLogNewComer",
		}
		local head = "Pull-Request !" .. self.pr_number .. "        "
		local hls = {}
		local from = 0
		local to = #head
		table.insert(hls, {from=from, to=to, name="GlanceLogHeader"})
		for _, label in pairs(self.labels) do
			local label_str = label.name
			head = head .. " | " .. label_str
			from = to + 3
			to = from + #label_str
			if label_hl_name[label_str] then
				table.insert(hls, {from=from, to=to, name=label_hl_name[label_str]})
			end
		end
		output:append(head)
		for _, hl in pairs(hls) do
			add_highlight(hl.from, hl.to, hl.name)
		end

		output:append("---")

		output:append("URL:      " .. self.head.url)
		add_sign("GlanceLogHeaderField")
		output:append("Creator:  " .. self.head.creator)
		add_sign("GlanceLogHeaderField")
		output:append("Head:     " .. self.head.head)
		add_sign("GlanceLogHeaderHead")
		output:append("Base:     " .. self.head.base)
		add_sign("GlanceLogHeaderBase")
		output:append("Created:  " .. self.head.created_at)
		add_sign("GlanceLogHeaderField")
		output:append("Updated:  " .. self.head.updated_at)
		add_sign("GlanceLogHeaderField")
		if self.head.mergeable then
			output:append("Mergable: true")
		else
			output:append("Mergable: false")
		end
		add_sign("GlanceLogHeaderField")
		output:append("State:    " .. self.head.state)
		add_sign("GlanceLogHeaderField")
		output:append("Title:    " .. self.head.title)
		output:append("---")

		for _, line in pairs(self.body) do
			local to = string.find(line, "\r", 1)
			if to then
				line = string.sub(line, 1, to - 1)
			end
			output:append("    " .. line)
		end
		output:append("---")
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
	output:append("---")

	local level = 0
	for _, comment in pairs(self.comments) do
		local function space_with_level(level)
			local str = ""
			for i = 1, level do
				str = str .. "    "
			end
			return str
		end
		local function put_one_comment(comment, level)
			local comment_head = string.format("%s | %s | %s", comment.user.login, comment.user.name, comment.created_at)
			local level_space = space_with_level(level)
			output:append(level_space .. "> " .. comment_head)
			add_sign("GlanceLogCommentHead")

			output:append("")
			local comment_body = vim.split(comment.body, "\n")
			for _, line in pairs(comment_body) do
				output:append("  " .. level_space .. line)
			end
			output:append("")

			if comment.children then
				local child_level = level + 1
				for _, child in pairs(comment.children) do
					put_one_comment(child, child_level)
				end
			end
		end

		if not comment.in_reply_to_id then
			put_one_comment(comment, level)
		end
	end

	buffer:replace_content_with(output)

	for line, name in pairs(signs) do
		buffer:place_sign(line, name, "hl")
	end

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
