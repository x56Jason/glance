local curl = require('plenary.curl')

local M = {}

M.config = {
	patchdiff = "diffonly",
	q_quit_log = "off",
}

local function do_glance_log(cmdline, pr)
	local logview = require("glance.log_view").new(cmdline, pr)
	logview:open()
end

function M.set_config(config)
	if config.patchdiff == "full" or config.patchdiff == "diffonly" then
		M.config.patchdiff = config.patchdiff
	end
	if config.q_quit_log == "on" or config.q_quit_log == "off" then
		M.config.q_quit_log = config.q_quit_log
	end
	if config.gitee then
		M.config.gitee = M.config.gitee or {}
		if config.gitee.token_file then
			local token = vim.fn.systemlist("cat " .. config.gitee.token_file)
			if vim.v.shell_error == 0 then
				M.config.gitee.token = token[1]
			end
		end
		if config.gitee.repo then
			M.config.gitee.repo = config.gitee.repo
		end
	end
end

local function do_glance_patchdiff(cmdline)
	local config = { patchdiff = string.gsub(cmdline, "%s*(.-)%s*", "%1") }
	M.set_config(config)
end

local function do_glance_q_quit_log(cmdline)
	local config = { q_quit_log = string.gsub(cmdline, "%s*(.-)%s*", "%1") }
	M.set_config(config)
end

local function find_comment_by_id(comments, id)
	for _, comment in ipairs(comments) do
		if comment.id == id then
			return comment
		end
	end
end

function M.get_pr_comments(pr_number)
	local base_url = "https://gitee.com/api/v5/repos/" .. M.config.gitee.repo .. "/pulls/"
	local token = M.config.gitee.token
	local opts = {
		method = "get",
		headers = {
			["Accept"] = "application/json",
			["Connection"] = "keep-alive",
			["Content-Type"] = "\'application/json; charset=utf-8\'",
			["User-Agent"] = "Glance",
		},
		body = {},
	}
	opts.url = base_url .. pr_number .."/comments?access_token=" .. token .. "&number=" .. pr_number .. "&page=1&per_page=100"
	vim.notify("url: " .. opts.url, vim.log.levels.INFO, {})
	local response = curl["get"](opts)
	local json = vim.fn.json_decode(response.body)
	local comments = {}
	for _, comment in ipairs(json) do
		if comment.user.login ~= "openeuler-ci-bot" and comment.user.login ~= "openeuler-sync-bot" and comment.user.login ~= "ci-robot" then
			table.insert(comments, comment)
		end

	end
	for _, comment in ipairs(comments) do
		if comment.in_reply_to_id then
			local parent = find_comment_by_id(comments, comment.in_reply_to_id)
			parent.children = parent.children or {}
			table.insert(parent.children, comment)
		end
	end
	return comments
end

function M.do_glance_pr(cmdline)
	local pr_number = cmdline
	local base_url = "https://gitee.com/api/v5/repos/" .. M.config.gitee.repo .. "/pulls/"
	local token = M.config.gitee.token
	local opts = {
		method = "get",
		headers = {
			["Accept"] = "application/json",
			["Connection"] = "keep-alive",
			["Content-Type"] = "\'application/json; charset=utf-8\'",
			["User-Agent"] = "Glance",
		},
		body = {},
	}
	opts.url = base_url .. pr_number .."?access_token=" .. token .. "&number=" .. pr_number
	vim.notify("url: " .. opts.url, vim.log.levels.INFO, {})
	local response = curl["get"](opts)
	local json = vim.fn.json_decode(response.body)
	local desc_body = vim.fn.split(json.body, "\n")
	local pr = {
		number = pr_number,
		labels = json.labels,
		desc_head = {
			url = json.html_url,
			creator = json.head.user.name,
			head = json.head.repo.full_name .. " : " .. json.head.ref,
			base = json.base.repo.full_name .. " : " .. json.base.ref,
			state = json.state,
			created_at = json.created_at,
			updated_at = json.updated_at,
			mergeable = json.mergeable,
		},
		desc_body = desc_body,
		user = json.head.user.login,
		url = json.head.repo.html_url,
		branch = json.head.ref,
		sha = json.head.sha,
		base_user = json.base.user.login,
		base_url = json.base.repo.html_url,
		base_branch = json.base.ref,
		base_sha = json.base.sha,
	}
	vim.cmd(string.format("!git remote add %s %s", pr.user, pr.url))
	vim.cmd(string.format("!git remote add %s %s", pr.base_user, pr.base_url))
	vim.cmd(string.format("!git fetch %s %s", pr.user, pr.branch))
	vim.cmd(string.format("!git fetch %s %s", pr.base_user, pr.base_branch))

	local commit_from = vim.fn.systemlist(string.format("git merge-base %s %s", pr.sha, pr.base_sha))[1]

	do_glance_log(string.format("%s..%s", commit_from, pr.sha), pr)
end

local function table_concat(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

local function do_glance_prlist(cmdline)
	local howmany = cmdline ~= "" or 100
	local base_url = "https://gitee.com/api/v5/repos/" .. M.config.gitee.repo .. "/pulls"
	local token = M.config.gitee.token
	local opts = {
		method = "get",
		headers = {
			["Accept"] = "application/json",
			["Connection"] = "keep-alive",
			["Content-Type"] = "\'application/json; charset=utf-8\'",
			["User-Agent"] = "Glance",
		},
		body = {},
	}
	local json = {}
	local count = 0
	while count*100 < tonumber(howmany) do
		count = count + 1
		opts.url = base_url .. "?access_token=" .. token .. "&state=open&sort=created&direction=desc&page="..count.."&per_page=100"
		local response = curl["get"](opts)
		local tmp = vim.fn.json_decode(response.body)
		table_concat(json, tmp)
	end

	local prlist_view = require("glance.prlist_view").new(json)
	prlist_view:open()
end

local function do_glance_gitee(cmdline)
	local gitee_cmd = vim.split(cmdline, " ")
	local config = {
		gitee = {},
	}
	if gitee_cmd[1] == "repo" then
		config.gitee.repo = gitee_cmd[2]
	elseif gitee_cmd[1] == "token_file" then
		config.gitee.token_file = gitee_cmd[2]
	end
	M.set_config(config)
end

local function do_glance_command(user_opts)
	local sub_cmd_str = user_opts.fargs[1]
	local sub_cmd

	if sub_cmd_str == "log" then
		sub_cmd = do_glance_log
	elseif sub_cmd_str == "patchdiff" then
		sub_cmd = do_glance_patchdiff
	elseif sub_cmd_str == "q_quit_log" then
		sub_cmd = do_glance_q_quit_log
	elseif sub_cmd_str == "prlist" then
		sub_cmd = do_glance_prlist
	elseif sub_cmd_str == "pr" then
		sub_cmd = M.do_glance_pr
	elseif sub_cmd_str == "gitee" then
		sub_cmd = do_glance_gitee
	else
		return
	end

	local cmdline = ""
	for i, arg in ipairs(user_opts.fargs) do
		if i == 2 then
			cmdline = arg
		elseif i ~= 1 then
			cmdline = cmdline .. " " .. arg
		end
	end

	sub_cmd(cmdline)
end

function M.setup(opts)
	local config = opts or {}

	M.set_config(config)

	vim.api.nvim_create_user_command( "Glance", do_glance_command, { desc = "Glance Commands", nargs = '+' })
end

return M
