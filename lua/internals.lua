local M = {}

-- maximum height of a registereditor window. This can become a configurable
-- option in the future
local MAX_BUFFER_LINES = 20

-- https://stackoverflow.com/questions/72386387/lua-split-string-to-table
-- Split string into table on newlines, include empty lines (\n\n\n)
function string:split(sep)
    local sep = sep or "\n"
    local result = {}
    local i = 1
    for c in (self .. sep):gmatch("(.-)" .. sep) do
        result[i] = c
        i = i + 1
    end
    return result
end

-- https://gist.github.com/kgriffs/124aae3ac80eefe57199451b823c24ec
function string:endswith(ending)
    return ending == "" or self:sub(-#ending) == ending
end

local function set_register(reg)
    vim.fn.setreg(reg, "")

    local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local last_line = table.remove(buf_lines)

    if #buf_lines > 0 then
        vim.fn.setreg(reg, buf_lines)
    end

    -- Saving a buffer with a newline at the end puts ^J at the end of register
    -- If last line is text, ^J is omitted: for macros or something like "qy$
    if last_line ~= "" then
        vim.cmd("let @" .. reg .. " ..= '" .. last_line .. "'")
    end
end

-- set the contents of a buffer and mark it is not modified
local function set_buffer_content(buffer, content)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, content)
    vim.api.nvim_set_option_value("modified", false, { buf = buffer })
end

local function open_editor_window(reg)
    if reg:len() > 1 or not reg:match('["0-9a-zA-Z-*+.:%%#/=_]') then
        print("Not a register: @" .. reg)
        return
    end

    local reg_content = ""

    -- Registers A-Z are append registers, they should have no initial content
    if not reg:match("[A-Z]") then
        reg_content = vim.fn.getreg(reg)
    end

    local buf_lines = reg_content:split("\n")
    local window_height = math.min(#buf_lines, MAX_BUFFER_LINES)

    -- keep track of existing equalalways setting, and set equalalways to
    -- false. See https://github.com/tuurep/registereditor/issues/1 for
    -- details.
    local old_equalalways = vim.o.equalalways
    vim.o.equalalways = false

    -- get information about old window
    local old_window_id = vim.fn.win_getid()
    local old_window_height = vim.api.nvim_win_get_height(old_window_id)

    -- make sure the old window is big enough to split
    vim.api.nvim_win_set_height(old_window_id, old_window_height + 2)

    -- open the new window
    vim.cmd("below " .. window_height .. "new @\\" .. reg)

    -- return the old window to its previous size
    vim.api.nvim_win_set_height(old_window_id, old_window_height)

    -- resize the new window back to its proper size.
    vim.api.nvim_win_set_height(0, window_height)

    vim.wo.winfixheight = true

    -- restore the original equalalways setting
    vim.o.equalalways = old_equalalways

    -- Scratch buffer settings
    vim.bo.filetype = "registereditor"
    vim.bo.bufhidden = "wipe"
    vim.bo.swapfile = false
    vim.bo.buflisted = false

    set_buffer_content(0, buf_lines)

    -- Special readonly registers
    if reg:match("[.:%%#]") then
        vim.bo.readonly = true
    end

    vim.api.nvim_create_autocmd({ "BufWriteCmd" }, {
        buffer = 0,
        callback = function()
            vim.bo.modified = false
            set_register(reg)
        end,
    })
end

local function check_string_is_register(value)
    return value:len() == 1 and value:match('["0-9a-zA-Z-*+.:%%#/=_]')
end

-- parse a list of single-character registers from a string argument. For
-- example, if the argument is "a b c" then the list should be {"a", "b", "c"}
local function parse_register_list(arg)
    local registers = {}
    for register in arg:gmatch("[^%s]+") do
        if not check_string_is_register(register) then
            print("Not a register: @" .. register)
            return
        end
        table.insert(registers, register)
    end
    return registers
end

M.open_all_windows = function(arg)
    -- check all args and build table
    local registers = parse_register_list(arg)
    if #registers == 0 then
        return
    end

    -- open a new editor window for each register specified
    for i, register in ipairs(registers) do
        open_editor_window(register)
        if i ~= #registers then
            vim.cmd("wincmd p")
        end
    end
end

-- update all open RegisterEdit buffers based on the macro that was just
-- recorded
M.update_register_buffers = function(yank)
    -- get the register that is being recorded or yanked into
    local register = yank and vim.api.nvim_get_vvar("event").regname
        or vim.fn.reg_recording()
    -- if this is a yank operation and no register was specified, then we will
    -- be yanking into the " register
    if yank and register == "" then
        register = '"'
    end
    -- get a list of all buffers
    local all_buffers = vim.api.nvim_list_bufs()
    -- iterate over all buffers, updating the matching ones
    for _, buffer in pairs(all_buffers) do
        -- get info about the buffer
        local buffer_name = vim.api.nvim_buf_get_name(buffer)
        local buffer_filetype =
            vim.api.nvim_get_option_value("filetype", { buf = buffer })
        -- if the buffer has the 'registereditor' filetype and is named
        -- @<register>, then it should be updated
        if
            buffer_filetype == "registereditor"
            and buffer_name:endswith("@" .. register)
        then
            -- get the content of the register
            local reg_content = vim.api.nvim_get_vvar("event").regcontents
            local buf_lines = yank and reg_content or reg_content:split("\n")
            -- update the buffer with the register contents
            vim.schedule(function()
                set_buffer_content(buffer, buf_lines)
            end)
        end
    end
end

local function get_register_from_buffer(buffer)
    return string.sub(vim.api.nvim_buf_get_name(buffer), -1, -1)
end

local function close_buffer(buffer)
    vim.cmd("bd " .. buffer)
end

M.close_windows = function(arg)
    -- see what registers were specified. If there were none, then registers
    -- will be nil
    local registers = nil
    if arg ~= nil and arg ~= "" then
        registers = parse_register_list(arg)
    end

    -- loop over all the buffers and close the appropriate ones.
    loop_over_register_buffers(function(buffer)
        -- if the registers list is nil or empty, then close all the buffers
        if registers == nil or #registers == 0 then
            close_buffer(buffer)
        else
            -- find out what register the buffer corresponds to
            local buffer_register = get_register_from_buffer(buffer)

            -- determine if the buffer should be closed based on the supplied
            -- list of registers
            local should_close = false
            for _, register in pairs(registers) do
                if register == buffer_register then
                    should_close = true
                end
            end

            -- close the buffer if necessary
            if should_close then
                close_buffer(buffer)
            end
        end
    end)
end

return M
