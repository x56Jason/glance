
local M = { }

local default_config = {
	patchdiff_mode = "diffonly",
}

local function open_logview(user_opts)
	local logview = require("glance.log_view").new(user_opts)
	logview:open()
end

function M.set_config(config)
	if config.patchdiff_mode == "full" or config.patchdiff_mode == "diffonly" then
		M.config.patchdiff_mode = config.patchdiff_mode
	end
end

local function cmd_set_patchdiff(user_opts)
	local opt = user_opts.args or ""
	local config = { patchdiff_mode = opt }
	M.set_config(config)
end

function M.setup(opts)
	local config = opts or {}

	M.config = default_config
	M.set_config(config)

	vim.api.nvim_create_user_command( "Glance", open_logview, { desc = "Open Git Log View", nargs = '*' })
	vim.api.nvim_create_user_command( "Patchdiff", cmd_set_patchdiff, { desc = "Open Git Log View", nargs = '*' })
end

return M
