local M = {}

M.config = {
	patchdiff_mode = "diffonly",
}

local function do_glance_log(cmdline)
	local logview = require("glance.log_view").new(cmdline)
	logview:open()
end

function M.set_config(config)
	if config.patchdiff_mode == "full" or config.patchdiff_mode == "diffonly" then
		M.config.patchdiff_mode = config.patchdiff_mode
	end
end

local function do_glance_patchdiff(cmdline)
	local config = { patchdiff_mode = string.gsub(cmdline, "%s*(.-)%s*", "%1") }
	M.set_config(config)
end

local function do_glance_command(user_opts)
	local sub_cmd_str = user_opts.fargs[1]
	local sub_cmd

	if sub_cmd_str == "log" then
		sub_cmd = do_glance_log
	elseif sub_cmd_str == "patchdiff" then
		sub_cmd = do_glance_patchdiff
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
