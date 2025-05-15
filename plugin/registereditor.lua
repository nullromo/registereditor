local internals = require("internals")

local function setup_user_commands()
    vim.api.nvim_create_user_command("RegisterEdit", function(opts)
        internals.open_all_windows(opts.args)
    end, { nargs = "+" })

    vim.api.nvim_create_user_command("RegisterEditClose", function(opts)
        internals.close_windows(opts.args)
    end, { nargs = "*" })
end

local function setup_autocommands()
    -- create a new autocommand group, clearing all previous autocommands
    local autocommand_group = vim.api.nvim_create_augroup(
        "registereditor_autocommands",
        { clear = true }
    )

    -- update open RegisterEdit buffers when a macro is recorded
    vim.api.nvim_create_autocmd({ "RecordingLeave" }, {
        callback = internals.update_register_buffers,
    })
end

setup_user_commands()
setup_autocommands()
