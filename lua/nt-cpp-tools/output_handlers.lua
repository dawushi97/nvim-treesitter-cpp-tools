local util = require("nt-cpp-tools.util")
local configs = require("nt-cpp-tools.config")
local previewer = require("nt-cpp-tools.preview_printer")

local M = {}


local function preview_and_apply(output, context)
    local on_preview_succces = function (row)
        util.add_text_edit(output, row, 0)
    end

    previewer.start_preview(output, context.class_end_row + 1, on_preview_succces)
end

function M.get_preview_and_apply(_)
    return preview_and_apply
end

local function add_to_cpp(output, _)
    local config = configs.get_cfg()
    local file_name = vim.fn.expand('%:r')
    vim.api.nvim_command('vsp ' .. file_name ..
        '.' .. config.source_extension)
    
    -- Get total line count of current buffer, add at the end
    local line_count = vim.api.nvim_buf_line_count(0)
    
    -- Add an empty line at the end, then add the generated code
    local final_output = "\n" .. output
    util.add_text_edit(final_output, line_count, 0)
end

function M.get_add_to_cpp(_)
    return add_to_cpp
end

return M
