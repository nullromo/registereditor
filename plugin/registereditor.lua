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
        callback = function()
            internals.update_register_buffers(
                vim.fn.reg_recording(),
                vim.api.nvim_get_vvar("event").regcontents:split("\n")
            )
        end,
    })

    -- update open RegisterEdit buffers when text is yanked into a register
    vim.api.nvim_create_autocmd({ "TextYankPost" }, {
        callback = function()
            local event = vim.api.nvim_get_vvar("event")
            internals.update_register_buffers(
                -- if no register was specified for the yank, then we will be
                -- yanking into the " register
                event.regname == "" and '"' or event.regname,
                event.regcontents
            )
        end,
    })

    -- update open RegisterEdit buffers after using the command line
    vim.api.nvim_create_autocmd({ "CmdlineLeave" }, {
        callback = vim.schedule_wrap(function()
            internals.refresh_all_register_buffers()
        end),
    })
end

setup_user_commands()
setup_autocommands()
