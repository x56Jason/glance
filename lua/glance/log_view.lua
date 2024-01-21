local curl = require('plenary.curl')
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
	local pr_number = pr and pr.number
	local desc_head = pr and pr.desc_head
	local desc_body = pr and pr.desc_body

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
		cmdline = cmdline,
		pr = pr,
		pr_number = pr_number,
		labels = pr and pr.labels,
		head = desc_head,
		body = desc_body,
		commits = commits,
		commit_start_line = commit_start_line,
		comments = comments,
		comment_start_line = comment_start_line,
		text = {},
		buffer = nil,
	}

	setmetatable(instance, { __index = M })

	return instance
end

function M:open_alldiff_view()
	if not self.pr then
		vim.notify("Not a pr log", vim.log.levels.WARN, {})
	end
	local view = CommitView.new_pr_alldiff(self.cmdline, self)
	if not view then return end
	view:open()
	view:initialize()
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

function M:delete_pr_comment(comment)
	local token = glance.config.gitee.token
	local opts = {
		method = "delete",
		headers = {
			["Accept"] = "application/json",
			["User-Agent"] = "Glance",
		},
		body = {
			["access_token"] = token,
			["body"] = message,
		},
	}
	opts.url = "https://gitee.com/api/v5/repos/" .. glance.config.gitee.repo .. "/pulls/comments/" .. comment.id
	opts.url = opts.url .. "?access_token=" .. token .. "&id=" .. comment.id
	vim.notify("url: "..opts.url, vim.log.levels.INFO, {})
	local response = curl["delete"](opts)
	vim.notify("response: exit: "..response.exit.."status: "..response.status, vim.log.levels.INFO, {})
	if response.exit ~= 0 then
		vim.notify("response: " .. response.body, vim.log.levels.INFO, {})
	end
end

function M:post_pr_comment(message)
	local pr_number = self.pr_number
	local token = glance.config.gitee.token
	local opts = {
		method = "post",
		url = "https://gitee.com/api/v5/repos/" .. glance.config.gitee.repo .. "/pulls/" .. pr_number .. "/comments?number=" .. pr_number,
		headers = {
			["Accept"] = "application/json",
			["Connection"] = "keep-alive",
			["User-Agent"] = "Glance",
		},
		body = {
			["access_token"] = token,
			["body"] = message,
		},
	}
	if self.comment_file then
		opts.body["path"] = self.comment_file
		opts.body["position"] = self.comment_file_pos
		vim.notify("file: "..self.comment_file, vim.log.levels.INFO, {})
		vim.notify("file_pos: "..self.comment_file_pos, vim.log.levels.INFO, {})
	end
	vim.notify("url: " .. opts.url, vim.log.levels.INFO, {})
	local response = curl["post"](opts)
	if response.exit ~= 0 or response.status ~= 201 then
		vim.notify("response: " .. response.body, vim.log.levels.INFO, {})
		return nil
	end
	local comment = vim.fn.json_decode(response.body)
	vim.notify("new comment: \n" .. comment.body, vim.log.levels.INFO, {})
	return comment
end

local function concatenate_lines(lines)
	local message = nil
	for _, line in ipairs(lines) do
		if not message then 
			message = line
		else
			message = message .. "\n" .. line
		end
	end
	return message
end

function M:do_pr_comment(file, file_pos)
	self.comment_file = file
	self.comment_file_pos = file_pos
	local config = {
		name = "GlanceComment",
		mappings = {
			n = {
				["<c-p>"] = function()
					local lines = self.comment_buffer:get_lines(0, -1, false)
					local message = concatenate_lines(lines)
					local comment = self:post_pr_comment(message)
					if comment then
						table.insert(self.comments, comment)
						self:append_comment(comment, 0)
					end
					self.comment_buffer:close()
				end,
			},
		}
	}
	local buffer = Buffer.create(config)
	if buffer == nil then
		return
	end

	self.comment_buffer = buffer
	vim.api.nvim_create_autocmd("BufDelete", {
		buffer = 0,
		callback = function()
			self.comment_buffer = nil
		end,
	})

	vim.cmd('startinsert')
end

function M:append_comment(comment, level)
	local output = self.text
	local signs = {}

	local function add_sign(name)
		signs[#output] = name
	end

	local function space_with_level(level)
		local str = ""
		for i = 1, level do
			str = str .. "    "
		end
		return str
	end
	local function table_slice(tbl, first, last, step)
		local sliced = {}

		for i = first or 1, last or #tbl, step or 1 do
			sliced[#sliced+1] = tbl[i]
		end

		return sliced
	end
	local function put_one_comment(comment, level)
		local comment_head = string.format("%d | %s | %s | %s", comment.id, comment.user.login, comment.user.name, comment.created_at)
		local level_space = space_with_level(level)

		output:append(level_space .. "> " .. comment_head)
		add_sign("GlanceLogCommentHead")
		comment.start_line = #output

		output:append("")
		local comment_body = vim.split(comment.body, "\n")
		for _, line in pairs(comment_body) do
			output:append("  " .. level_space .. line)
		end
		output:append("")
		comment.end_line = #output

		if comment.children then
			for _, child in pairs(comment.children) do
				local child_level = level + 1
				put_one_comment(child, child_level)
			end
		end
	end

	if not comment.in_reply_to_id then
		put_one_comment(comment, level)
	end

	local lines = table_slice(output, comment.start_line, comment.end_line)
	self.buffer:unlock()
	self.buffer:set_lines(comment.start_line - 1, comment.end_line - 1, false, lines)

	for line, name in pairs(signs) do
		self.buffer:place_sign(line, name, "hl")
	end
	self.buffer:lock()
	vim.cmd("syntax on")
end

function M:get_cursor_comment(line)
	for _, comment in ipairs(self.comments) do
		if line >= comment.start_line and line <= comment.end_line then
			return comment
		end
	end
	return nil
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
				["<c-a>"] = function()
					self:open_alldiff_view()
				end,
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
				["<c-r>"] = function()
					if not self.pr_number then
						vim.notify("not a pr", vim.log.levels.WARN, {})
						return
					end
					local answer = vim.fn.confirm("Create a comment for this PR?", "&yes\n&no")
					if answer ~= 1 then
						return
					end
					self:do_pr_comment()
				end,
				["<c-d>"] = function()
					if not self.pr_number then
						vim.notify("not a pr", vim.log.levels.WARN, {})
						return
					end
					local line = vim.fn.line '.'
					local comment = self:get_cursor_comment(line)
					if not comment then
						vim.notify("Cursor not in a comment", vim.log.levels.WARN, {})
						return
					end
					local answer = vim.fn.confirm(string.format("Delete comment (id %d)?", comment.id), "&yes\n&no")
					if answer ~= 1 then
						return
					end
					self:delete_pr_comment(comment)
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
			local comment_head = string.format("%d | %s | %s | %s", comment.id, comment.user.login, comment.user.name, comment.created_at)
			local level_space = space_with_level(level)

			output:append(level_space .. "> " .. comment_head)
			add_sign("GlanceLogCommentHead")
			comment.start_line = #output

			output:append("")
			local comment_body = vim.split(comment.body, "\n")
			for _, line in pairs(comment_body) do
				output:append("  " .. level_space .. line)
			end
			output:append("")
			comment.end_line = #output

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

	self.text = output

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
