local M = {}

M.config = {
	patchdiff = "diffonly",
	q_quit_log = "off",
}

local function do_glance_log(cmdline)
	local logview = require("glance.log_view").new(cmdline)
	logview:open()
end

function M.set_config(config)
	if config.patchdiff == "full" or config.patchdiff == "diffonly" then
		M.config.patchdiff = config.patchdiff
	end
	if config.q_quit_log == "on" or config.q_quit_log == "off" then
		M.config.q_quit_log = config.q_quit_log
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

local function do_glance_command(user_opts)
	local sub_cmd_str = user_opts.fargs[1]
	local sub_cmd

	if sub_cmd_str == "log" then
		sub_cmd = do_glance_log
	elseif sub_cmd_str == "patchdiff" then
		sub_cmd = do_glance_patchdiff
	elseif sub_cmd_str == "q_quit_log" then
		sub_cmd = do_glance_q_quit_log
	else
		return
	end

	local cmdline = ""
	for i, arg in ipairs(user_opts.fargs) do
		if i ~= 1 then
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
