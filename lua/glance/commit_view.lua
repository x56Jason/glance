local Buffer = require("glance.buffer")
local LineBuffer = require('glance.line_buffer')
local md5 = require('glance.md5')

local diff_add_matcher = vim.regex('^+')
local diff_delete_matcher = vim.regex('^-')

local notify = require("notify")

-- @class CommitOverviewFile
-- @field path the path to the file relative to the git root
-- @field changes how many changes were made to the file
-- @field insertions insertion count visualized as list of `+`
-- @field deletions deletion count visualized as list of `-`

-- @class CommitOverview
-- @field summary a short summary about what happened 
-- @field files a list of CommitOverviewFile
-- @see CommitOverviewFile
local CommitOverview = {}

-- @class CommitInfo
-- @field oid the oid of the commit
-- @field author_name the name of the author
-- @field author_email the email of the author
-- @field author_date when the author commited
-- @field committer_name the name of the committer
-- @field committer_email the email of the committer
-- @field committer_date when the committer commited
-- @field description a list of lines
-- @field diffs a list of diffs
-- @see Diff
local CommitInfo = {}

-- @return the abbreviation of the oid
function CommitInfo:abbrev()
	return self.oid:sub(1, 12)
end

local function parse_diff(output)
	local header = {}
	local hunks = {}
	local is_header = true

	for i=1,#output do
		if is_header and output[i]:match('^@@.*@@') then
			is_header = false
		end

		if is_header then
			table.insert(header, output[i])
		else
			table.insert(hunks, output[i])
		end
	end

	local file = ""
	local kind = "modified"

	if #header == 4 then
		file = header[3]:match("%-%-%- a/(.*)")
	elseif #header == 2 then
		file = header[2]:match("%+%+%+ /tmp/(.+).patch")
	else
		kind = header[2]:match("(.*) mode %d+")
		if kind == "new file" then
			file = header[5]:match("%+%+%+ b/(.*)")
		elseif kind == "deleted" then
			file = header[4]:match("%-%-%- a/(.*)")
		end
	end

	local diff = {
		lines = hunks,
		file = file,
		kind = kind,
		headers = header,
		hunks = {}
	}

	local len = #hunks

	local hunk = nil

	local hunk_content = ''
	for i=1,len do
		local line = hunks[i]
		if not vim.startswith(line, "+++") then
			local index_from, index_len, disk_from, disk_len = line:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')

			if index_from then
				if hunk ~= nil then
					hunk.hash = md5.sumhexa(hunk_content)
					hunk_content = ''
					table.insert(diff.hunks, hunk)
				end
				hunk = {
					index_from = tonumber(index_from),
					index_len = tonumber(index_len) or 1,
					disk_from = tonumber(disk_from),
					disk_len = tonumber(disk_len) or 1,
					line = line,
					diff_from = i,
					diff_to = i
				}
			else
				hunk_content = hunk_content .. '\n' .. line
				hunk.diff_to = hunk.diff_to + 1
			end
		end
	end

	if hunk then
		hunk.hash = md5.sumhexa(hunk_content)
		table.insert(diff.hunks, hunk)
	end

	return diff
end
local M = {}

local function parse_commit_overview(raw)
	local overview = {
		summary = vim.trim(raw[#raw]),
		files = {}
	}

	for i = 2, #raw - 1 do
	local file = {}
		if raw[i] ~= "" then
			file.path, file.changes, file.insertions, file.deletions = raw[i]:match(" (.*)%s+|%s+(%d+) ?(%+*)(%-*)")
			table.insert(overview.files, file)
		end
	end

	setmetatable(overview, { __index = CommitOverview })

	return overview
end

local function parse_commit_info(raw_info, diffonly)
	local idx = 0

	local function peek()
		return raw_info[idx+1]
	end

	local function advance()
		idx = idx + 1
		return raw_info[idx]
	end

	local info = {}

	if not diffonly then
		info.oid = advance():match("commit (%w+)")
		if vim.startswith(peek(), "Merge: ") then advance() end
		info.author_name, info.author_email = advance():match("Author:%s*(.+) <(.+)>")
		info.author_date = advance():match("AuthorDate:%s*(.+)")
		info.committer_name, info.committer_email = advance():match("Commit:%s*(.+) <(.+)>")
		info.committer_date = advance():match("CommitDate:%s*(.+)")
		info.description = {}

		-- skip empty line
		advance()

		local line = advance()
		while line ~= "" and line ~= nil do
			table.insert(info.description, vim.trim(line))
			line = advance()
		end
	end

	local raw_diff_info = {}

	info.diffs = {}
	line = advance()
	while line do
		table.insert(raw_diff_info, line)
		line = advance()
		if line == nil or vim.startswith(line, "diff") then
			table.insert(info.diffs, parse_diff(raw_diff_info))
			raw_diff_info = {}
		end
	end

	setmetatable(info, { __index = CommitInfo })

	return info
end

local function parse_upstream_commit(raw_info)
	local idx = 0

	local function advance()
		idx = idx + 1
		return raw_info[idx]
	end

	local line = advance()
	while line do
		if vim.startswith(line, "commit ") then
			commit_id = line:match("commit (%w+)")
			return commit_id
		end
		line = advance()
	end
	return nil
end

function M:set_scrollbind_view(view)
	self.view_scrollbind = view
end

-- @class CommitViewBuffer
-- @field is_open whether the buffer is currently shown
-- @field commit_info CommitInfo
-- @field commit_overview CommitOverview
-- @field buffer Buffer
-- @see CommitInfo
-- @see Buffer

--- Creates a new CommitViewBuffer
-- @param commit_id the id of the commit
-- @return CommitViewBuffer
function M.new(commit_id)
	local output = vim.fn.systemlist("git show --format=fuller " .. commit_id)
	if vim.v.shell_error ~= 0 then
		return nil
	end
	local commit_info = parse_commit_info(output, false)

	output = vim.fn.systemlist("git show --stat --oneline " .. commit_id)
	if vim.v.shell_error ~= 0 then
		return nil
	end
	local commit_overview = parse_commit_overview(output)

	local instance = {
		is_open = false,
		commit_id = commit_id,
		commit_info = commit_info,
		commit_overview = commit_overview,
		buffer = nil,
		view_scrollbind = nil,
	}

	setmetatable(instance, { __index = M })

	return instance
end

function M.get_upstream_commit(commit_id)
	local upstream_commit_id = parse_upstream_commit(vim.fn.systemlist("git log --format=%B -n 1 " .. commit_id))

	return upstream_commit_id
end

function M:get_first_hunk_line()
	return self.first_hunk_line
end

function patchdiff_full_compose(commit_id)
	local commit_patch_path = "/tmp/" .. commit_id .. ".patch"
	local commit_patch_cmd = "git show --output=" .. commit_patch_path .. " " .. commit_id

	return {patch_cmd = commit_patch_cmd, patch_path = commit_patch_path}
end

function patchdiff_diffonly_compose(commit_id)
	local commit_patch_path = "/tmp/" .. commit_id .. ".patch"
	local commit_patch_cmd = "git diff --output=" .. commit_patch_path .. " " .. commit_id .. "^.." .. commit_id

	return {patch_cmd = commit_patch_cmd, patch_path = commit_patch_path}
end

function M.new_patchdiff(commit_id)
	local upstream_commit_id = parse_upstream_commit(vim.fn.systemlist("git log --format=%B -n 1 " .. commit_id))

	if upstream_commit_id == nil then
		vim.notify("Not a backport commit", vim.log.levels.ERROR, {})
		return nil
	end

	local config = require("glance").config
	local cmd_compose_func = patchdiff_full_compose
	if config.patchdiff_mode == "diffonly" then
		cmd_compose_func = patchdiff_diffonly_compose
	end

	local backport = cmd_compose_func(commit_id)
	local upstream = cmd_compose_func(upstream_commit_id)

	vim.fn.system(upstream.patch_cmd)
	vim.fn.system(backport.patch_cmd)

	local output = vim.fn.systemlist("diff -u " .. upstream.patch_path .. " " .. backport.patch_path)
	local commit_info = parse_commit_info(output, true)

	local instance = {
		is_open = false,
		commit_id = commit_id,
		upstream_commit_id = upstream_commit_id,
		commit_info = commit_info,
		buffer = nil,
	}

	setmetatable(instance, { __index = M })

	return instance
end

function M:close()
	if self.is_open == false then
		return
	end
	self.is_open = false
	self.buffer:close()
	self.buffer = nil
	if self.view_scrollbind then
		self.view_scrollbind:close()
	end
	self.view_scrollbind = nil
end

function M:open(usr_opts)
	if self.is_open then
		return
	end

	local opts = usr_opts or {}
	self.is_open = true
	self.buffer = Buffer.create {
		name = opts.name or "GlanceCommit",
		filetype = opts.filetype or "GlanceCommit",
		kind = "vsplit",
		mappings = {
			n = {
				["q"] = function()
					self:close()
				end
			}
		},
	}
end

local highlight_maps = {
	Commit = {
		diffadd = "GlanceCommitDiffAdd",
		diffdel = "GlanceCommitDiffDelete",
		hunkheader = "GlanceCommitHunkHeader",
		filepath = "GlanceCommitFilePath",
		viewheader = "GlanceCommitViewHeader",
		viewdesc = "GlanceCommitViewDescription",
	},
	PatchDiff = {
		diffadd = "GlancePatchDiffAdd",
		diffdel = "GlancePatchDiffDelete",
		hunkheader = "GlancePatchDiffHunkHeader",
		filepath = "GlancePatchDiffFilePath",
		viewheader = "GlancePatchDiffViewHeader",
		viewdesc = "GlancePatchDiffViewDescription",
	},
}

function M:initialize()
	local buffer = self.buffer
	if buffer == nil then
		return
	end

	local output = LineBuffer.new()
	local info = self.commit_info
	local overview = self.commit_overview
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

	local hl_map = {}
	if vim.bo.filetype == "GlancePatchDiff" then
		hl_map = highlight_maps.PatchDiff
	else
		hl_map = highlight_maps.Commit
	end

	if vim.bo.filetype == "GlanceCommit" then
		output:append("Commit " .. self.commit_id)
		add_sign(hl_map.viewheader) -- 'GlanceCommitViewHeader'
		output:append("<remote>/<branch> " .. info.oid)
		output:append("Author:     " .. info.author_name .. " <" .. info.author_email .. ">")
		output:append("AuthorDate: " .. info.author_date)
		output:append("Commit:     " .. info.committer_name .. " <" .. info.committer_email .. ">")
		output:append("CommitDate: " .. info.committer_date)
		output:append("")
		for _, line in ipairs(info.description) do
			output:append(line)
			add_sign(hl_map.viewdesc) -- 'GReviewCommitViewDescription'
		end
		output:append("")
		output:append(overview.summary)
		for _, file in ipairs(overview.files) do
			local insertions = file.insertions or ""
			local deletions = file.deletions or ""
			local changes = file.changes or ""
			output:append(
				file.path .. " | " .. changes ..
				" " .. insertions .. deletions
			)
			local from = 0
			local to = #file.path
			add_highlight(from, to, hl_map.filepath) -- "GReviewFilePath"
			from = to + 3
			to = from + #tostring(changes)
			add_highlight(from, to, "Number")
			from = to + 1
			to = from + #insertions
			add_highlight(from, to, hl_map.diffadd) -- "GReviewDiffAdd"
			from = to
			to = from + #deletions
			add_highlight(from, to, hl_map.diffdel) -- "GReviewDiffDelete"
		end
		output:append("")
	end

	for _, diff in ipairs(info.diffs) do
		for _, header in ipairs(diff.headers) do
			output:append(header)
		end
		if self.first_hunk_line == nil then
			self.first_hunk_line = #output + 1
		end
		for _, hunk in ipairs(diff.hunks) do
			output:append(diff.lines[hunk.diff_from])
			add_sign(hl_map.hunkheader) -- 'GReviewHunkHeader'
			for i=hunk.diff_from + 1, hunk.diff_to do
				local l = diff.lines[i]
				local from = 0
				local to = #l
				output:append(l)
				if diff_add_matcher:match_str(l) then
					if vim.bo.filetype ~= "GlancePatchDiff" or
						vim.startswith(l, "+index ") or
						vim.startswith(l, "+@@ ") or
						vim.startswith(l, "+diff ") or
						vim.startswith(l, "+commit ") or
						vim.startswith(l, "++++ ") or
						vim.startswith(l, "+--- ")
					then
						add_highlight(from, to, hl_map.diffadd)
					else
						add_highlight(from, to, "PRDiffAdd")
					end
				elseif diff_delete_matcher:match_str(l) then
					if vim.bo.filetype ~= "GlancePatchDiff" or
						vim.startswith(l, "-index ") or
						vim.startswith(l, "-@@ ") or
						vim.startswith(l, "-diff ") or
						vim.startswith(l, "-commit ") or
						vim.startswith(l, "-+++ ") or
						vim.startswith(l, "---- ")
					then
						add_highlight(from, to, hl_map.diffdel)
					else
						add_highlight(from, to, "PRDiffDel")
					end
				end
			end
		end
	end
	buffer:replace_content_with(output)

	for line, name in pairs(signs) do
		buffer:place_sign(line, name, "hl")
	end

	for _, hi in ipairs(highlights) do
		buffer:add_highlight(
			hi.line,
			hi.from,
			hi.to,
			hi.name
		)
	end

	buffer:set_option("modifiable", false)
	buffer:set_option("readonly", true)

end

return M
