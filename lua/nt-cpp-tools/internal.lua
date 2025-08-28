local previewer = require("nt-cpp-tools.preview_printer")
local output_handlers = require("nt-cpp-tools.output_handlers")
local util = require("nt-cpp-tools.util")

local M = {}

local function get_node_text(node, bufnr)
    if not node then
        return {}
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local txtStr = vim.treesitter.get_node_text(node, bufnr)
    local txt = {}

    for str in string.gmatch(txtStr, "([^\n]+)") do
        table.insert(txt, str)
    end
    return txt
end

local function run_on_nodes(query, runner, sel_start_row, sel_end_row)
    local bufnr = 0
    local ft = vim.bo[bufnr].filetype

    local parser = vim.treesitter.get_parser(bufnr, ft)
    local root = parser:parse()[1]:root()

    local matches = query:iter_matches(root, bufnr, sel_start_row, sel_end_row + 1)

    while true do
        local pattern, match = matches()
        if pattern == nil then
            break
        end
        if type(match[1][1]) == 'userdata' then -- fix for 6913c5e1 in nvim  
          for _, m in pairs(match) do
            runner(query.captures, m)
          end
        else
          runner(query.captures, match)
        end
    end

    return true
end


local function t2s(txt)
    local value
    for id, line in pairs(txt) do
        if line ~= '' then
            value = (id == 1 and line or value .. '\n' .. line)
        end
    end
    return value
end

local function get_default_values_locations(t)
    local positions = {}
    local child_count = t:child_count()
    -- inorder to remove strings easier,
    -- doing reverse order
    for j = child_count-1, 0, -1 do
        local child = t:child(j)
        if child:type() == 'optional_parameter_declaration' then
            local _, _, start_row, start_col = child:field('declarator')[1]:range()
            local _, _, end_row, end_col = child:field('default_value')[1]:range()
            table.insert(positions,
            {   start_row = start_row,
                start_col = start_col,
                end_row = end_row,
                end_col = end_col
            }
            )
        end
    end
    return positions
end

local function remove_entries_and_get_node_string(node, entries)
    -- we expect entries to be sorted from end to begining when
    -- considering a row so that changing the statement will not
    -- mess up the indexes of the entries
    local base_row_offset, base_col_offset, _, _ = node:range()
    local txt = get_node_text(node)
    for _, entry in pairs(entries) do
        entry.start_row = entry.start_row - base_row_offset + 1
        entry.end_row = entry.end_row - base_row_offset + 1
        -- start row is trimmed to the tagged other rows are not
        local column_offset = entry.start_row > 1 and 0 or base_col_offset
        if entry.start_row == entry.end_row then
            local line = txt[entry.start_row]
            local s = line:sub(1, entry.start_col - column_offset)
            local e = line:sub(entry.end_col - column_offset + 1)
            txt[entry.start_row] = s .. e
        else
            txt[entry.start_row] = txt[entry.start_row]:sub(1, entry.start_col - column_offset)
            -- we will just mark the rows in between as empty since deleting will
            -- mess up locations of following entries
            for l = entry.start_row + 1, entry.end_row - 1, 1 do
                txt[l] = ''
            end

            local tail_txt = txt[entry.end_row]
            local indent_start, indent_end = tail_txt:find('^ *')
            local indent_str = string.format('%' .. (indent_end - indent_start) .. 's', ' ')

            -- no need to add column offset since we know end_row is not trimmed
            txt[entry.end_row] = indent_str .. tail_txt:sub(entry.end_col + 1)
        end
    end
    return txt
end

local function check_get_template_info(node)
    if node:parent():type() ~= 'template_declaration' then
        return nil, nil
    end

    local typename_names = {}
    local remove_entries = {}

    local template_param_list = node:parent():field('parameters')[1]
    local parameters_count = template_param_list:named_child_count()
    for param_id = parameters_count - 1, 0, -1 do
        local param_node = template_param_list:named_child(param_id)
        if param_node:type() == 'type_parameter_declaration' then
            table.insert(typename_names,
                    t2s(get_node_text(param_node:named_child(0))))
        elseif param_node:type() == 'optional_type_parameter_declaration' then
            local type_identifier = param_node:field('name')[1]
            table.insert(typename_names,
                    t2s(get_node_text(type_identifier)))
            local _, _, start_row, start_col = type_identifier:range()
            local _, _, end_row, end_col = param_node:field('default_type')[1]:range()
            table.insert(remove_entries,
            {   start_row = start_row,
                start_col = start_col,
                end_row = end_row,
                end_col = end_col
            }
            )
        end
    end
    return t2s(remove_entries_and_get_node_string(template_param_list, remove_entries)),
                typename_names
end


-- supports both reference return type and non reference return type
-- and no return type member functions
local function get_member_function_data(node)
    local result = {template = '', ret_type = '', fun_dec = '', class_details = nil}

    result.template, _ = check_get_template_info(node)
    result.template = result.template and 'template ' .. result.template

    local return_node = node:field('type')[1]
    local function_dec_node = node:field('declarator')[1]

    if next(node:field('default_value')) ~= nil then -- pure virtual
        return nil
    end

    result.ret_type = t2s(get_node_text(return_node)) -- return tye
    local node_child_count = node:named_child_count()
    for c = 0, node_child_count - 1, 1 do
        local child = node:named_child(c)
        if child:type() == 'type_qualifier' then -- return constness
            result.ret_type = t2s(get_node_text(child)) .. ' ' .. result.ret_type
            break
        end
    end

    if function_dec_node:type() == 'reference_declarator' or
        function_dec_node:type() == 'pointer_declarator' then
        result.ret_type = result.ret_type ..
            (function_dec_node:type() == 'reference_declarator' and '&' or '*')
        function_dec_node = function_dec_node:named_child(0)
    end

    result.fun_dec = t2s(get_node_text(function_dec_node:field('declarator')[1]))

    local fun_params = function_dec_node:field('parameters')[1]
    result.fun_dec = result.fun_dec .. t2s(remove_entries_and_get_node_string(fun_params,
                                                get_default_values_locations(fun_params)))

    local fun_dec_child_count = function_dec_node:named_child_count()
    for c = 0, fun_dec_child_count - 1, 1 do
        local child = function_dec_node:named_child(c)
        if child:type() == 'type_qualifier' or child:type() == 'noexcept' then -- function constness or noexcept
            result.fun_dec = result.fun_dec .. ' ' .. t2s(get_node_text(child))
        end
        if child:type() == 'trailing_return_type' then
            result.fun_dec = result.fun_dec .. ' ' .. t2s(get_node_text(child))
        end
    end
    return result
end

local function get_nth_parent(node, n)
    local parent = node
    for _ = 0 , n , 1 do
        parent = parent:parent()
        if not parent then return nil end
    end
    return parent
end

local function find_class_details(member_node, member_data)
    member_data.class_details = {}
    local end_row

    if member_node:parent():type() == 'template_declaration'  then
      member_node = member_node:parent()
    end

    -- If global function, member node is the highest, no class data available
    -- but function requires the scope end row to return
    if member_node:parent():type() == 'translation_unit' or
      member_node:parent():type() == 'preproc_ifdef' or
      ( member_node:parent():parent() ~= nil and
        member_node:parent():parent():type() == 'namespace_definition') then
      _, _, end_row, _ = member_node:range()
      return end_row
    end

    -- the function could be a template, therefore going an extra parent higher
    local class_node = member_node:parent():parent()

    while class_node and
        (class_node:type() == 'class_specifier' or
        class_node:type() == 'struct_specifier' or
        class_node:type() == 'union_specifier' ) do
        local class_data = {}
        class_data.name = t2s(get_node_text(class_node:field('name')[1]))

        local template_statement, params = check_get_template_info(class_node)
        if template_statement then
            class_data.class_template_statement = 'template ' .. template_statement
            for i = #params, 1, -1 do
                local val = params[i]
                class_data.class_template_params = (i == #params and '<' or
                                class_data.class_template_params .. ',') .. val
            end
            class_data.class_template_params = class_data.class_template_params .. '>'
        end

        _, _, end_row, _ = class_node:range()
        table.insert(member_data.class_details, class_data)

        class_node = get_nth_parent(class_node, 2)
    end
    return end_row
end

function M.imp_func(range_start, range_end, custom_cb)
    range_start = range_start - 1
    range_end = range_end - 1

    local query = vim.treesitter.query.get('cpp', 'outside_class_def')

    local e_row
    local results = {}
    local runner =  function(captures, match)
        for cid, node_or_table in pairs(match) do
            -- Handle new API: match may contain node tables
            local node = node_or_table
            if type(node_or_table) == 'table' and node_or_table[1] then
                node = node_or_table[1]
            end
            
            local cap_str = captures[cid]
            if cap_str == 'member_function' then
                local fun_start, _, fun_end, _ = node:range()
                if fun_end >= range_start and fun_start <= range_end then
                    local member_data = get_member_function_data(node)
                    if member_data then
                        e_row = find_class_details(node, member_data)
                        table.insert(results, member_data)
                    end
                end
            end
        end
    end

    if not run_on_nodes(query, runner, range_start, range_end) then
        return
    end

    local output = ''
    for _, fun in ipairs(results) do
        if fun.fun_dec ~= '' then

            local classes_name
            local classes_template_statemets

            if fun.class_details then
              for h = #fun.class_details, 1, -1 do
                  local templ_class_name = fun.class_details[h].name ..
                              (fun.class_details[h].class_template_params or '') .. '::'
                  classes_name = (h == #fun.class_details) and templ_class_name or classes_name .. templ_class_name
                  if fun.class_details[h].class_template_statement then
                    if not classes_template_statemets then
                        classes_template_statemets = fun.class_details[h].class_template_statement
                    else
                        classes_template_statemets = classes_template_statemets .. ' '
                                                .. fun.class_details[h].class_template_statement
                    end
                  end
              end
            end

            local template_statements
            if classes_template_statemets and fun.template then
                template_statements = classes_template_statemets .. ' ' .. fun.template
            elseif classes_template_statemets  then
                template_statements = classes_template_statemets
            elseif fun.template then
                template_statements = fun.template
            end

            output = output .. (template_statements and template_statements .. '\n' or '') ..
                                (fun.ret_type and fun.ret_type .. ' ' or '' ) ..
                                (classes_name and classes_name or '')
                                .. fun.fun_dec .. '\n{\n}\n'
        end
    end

    if output ~= '' then
        local context = {class_end_row = e_row}
        if custom_cb then
            custom_cb(output, context)
        else
            output_handlers.get_preview_and_apply()(output, context)
        end
    end

end

function M.concrete_class_imp(range_start, range_end)
    range_start = range_start - 1
    range_end = range_end - 1

    -- Get selected text directly from buffer
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, range_start, range_end + 1, false)
    local selected_text = table.concat(lines, '\n')
    
    -- Extract class name using simple pattern matching
    local base_class = selected_text:match('class%s+([%w_]+)')
    if not base_class then
        vim.notify('Error: Could not find class name in selection', vim.log.levels.ERROR)
        return
    end
    
    -- Find pure virtual functions using pattern matching
    local virtual_functions = {}
    
    -- Pattern to match virtual functions ending with = 0
    for line in selected_text:gmatch('[^\r\n]+') do
        local trimmed = line:match('^%s*(.-)%s*$') -- trim whitespace
        if trimmed:match('virtual.*=.*0') then
            -- Clean up the function declaration
            local cleaned = trimmed
                :gsub('^%s*virtual%s+', '')  -- Remove 'virtual' keyword
                :gsub('%s*=%s*0%s*;?%s*$', ' override;')  -- Replace '= 0' with 'override;'
                
            -- Ensure proper semicolon
            if not cleaned:match(';%s*$') then
                cleaned = cleaned .. ';'
            end
            
            table.insert(virtual_functions, cleaned)
        end
    end
    
    if #virtual_functions == 0 then
        vim.notify('No pure virtual functions found in selection', vim.log.levels.WARN)
        return
    end
    
    -- Ask user for new class name
    local class_name = vim.fn.input("New concrete class name: ", base_class .. "Impl")
    if class_name == "" then
        vim.notify('Operation cancelled', vim.log.levels.INFO)
        return
    end
    
    -- Generate concrete class
    local class_lines = {}
    table.insert(class_lines, string.format('class %s : public %s', class_name, base_class))
    table.insert(class_lines, '{')
    table.insert(class_lines, 'public:')
    
    for _, func in ipairs(virtual_functions) do
        table.insert(class_lines, '    ' .. func)
    end
    
    table.insert(class_lines, '};')
    
    local class_text = table.concat(class_lines, '\n')
    
    -- Use the preview and apply system
    output_handlers.get_preview_and_apply()(class_text, {class_end_row = range_end})
end

function M.rule_of_5(limit_at_3, range_start, range_end)
    
    -- If range is invalid (user didn't select text), try auto-detection
    if range_start == range_end then
        -- Get current cursor position
        local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1  -- Convert to 0-indexed
        
        -- Try to find the class definition range at cursor
        local bufnr = vim.api.nvim_get_current_buf()
        local parser = vim.treesitter.get_parser(bufnr, 'cpp')
        local tree = parser:parse()[1]
        local root = tree:root()
        
        -- Find class definition containing cursor position
        local function find_class_at_cursor(node, cursor_row)
            if node:type() == "class_specifier" then
                local start_row, _, end_row, _ = node:range()
                if start_row <= cursor_row and cursor_row <= end_row then
                    return start_row, end_row
                end
            end
            
            for child in node:iter_children() do
                local class_start, class_end = find_class_at_cursor(child, cursor_row)
                if class_start then
                    return class_start, class_end
                end
            end
            return nil
        end
        
        local class_start, class_end = find_class_at_cursor(root, cursor_line)
        if class_start then
            range_start = class_start
            range_end = class_end
        else
            vim.notify("Error: Unable to find class definition at cursor", vim.log.levels.ERROR)
            return
        end
    else
        range_start = range_start - 1
        range_end = range_end - 1
    end
    
    -- Get current buffer filetype, supporting various C++ header filetypes
    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.bo[bufnr].filetype
    
    -- Map various C++ related filetypes to cpp
    local cpp_filetypes = { cpp = 'cpp', c = 'cpp', hpp = 'cpp', h = 'cpp' }
    local query_ft = cpp_filetypes[ft] or ft
    
    -- First use general query to find class name
    local class_query = vim.treesitter.query.get(query_ft, 'class_detectors')
    local special_query = vim.treesitter.query.get(query_ft, 'special_function_detectors')
    

    local checkers = {
        destructor = false,
        copy_constructor = false,
        copy_assignment = false,
        move_constructor = false,
        move_assignment = false
    }

    local entry_location
    local class_name

    local entry_location_update = function (start_row, start_col)
        if entry_location == nil or entry_location.start_row < start_row then
            entry_location = { start_row = start_row + 1 , start_col = start_col }
        end
    end

    local runner = function(captures, matches)
        
        for capture_id, node_list in pairs(matches) do
            local cap_str = captures[capture_id]
            
            -- In Neovim 0.11, matches now returns node arrays instead of single nodes
            -- We need to iterate through each captured node
            local nodes_to_process = {}
            if type(node_list) == 'table' and not node_list.type then
                -- This is a node array
                nodes_to_process = node_list
            else
                -- This is a single node (backward compatibility)
                nodes_to_process = {node_list}
            end
            
            for _, node in ipairs(nodes_to_process) do
                -- Add nil check
                if not node then
                    goto continue_node
                end
                
                
                local value = vim.treesitter.get_node_text(node, 0) or ''
                local start_row, start_col, _, _ = node:range()

                -- Determine capture type based on node type, as old API index mapping is unreliable
                local node_type = node:type()
                
                if node_type == "type_identifier" then
                    -- This should be the class name
                    class_name = value
                elseif node_type == "destructor_name" then
                    -- Destructor
                    checkers.destructor = true
                    entry_location_update(start_row, start_col)
                elseif node_type == "reference_declarator" then
                    -- This might be assignment operator or constructor
                    -- Need to further check parent node or content
                    if value:find("operator=") then
                        if value:find("&&") then
                            if not limit_at_3 then
                                checkers.move_assignment = true
                                entry_location_update(start_row, start_col)
                            end
                        else
                            checkers.copy_assignment = true
                            entry_location_update(start_row, start_col)
                        end
                    end
                elseif node_type == "function_declarator" then
                    -- This might be a constructor
                    if value:find("&&") then
                        if not limit_at_3 then
                            checkers.move_constructor = true
                            entry_location_update(start_row, start_col)
                        end
                    else
                        checkers.copy_constructor = true
                        entry_location_update(start_row, start_col)
                    end
                elseif node_type == "class_specifier" then
                    -- This is the entire class definition, no processing needed
                    -- (class name already obtained from type_identifier)
                end
                ::continue_node::
            end
        end
    end

    -- Stage 1: Use general query to get class name
    local class_runner = function(captures, matches)
        for capture_id, node_list in pairs(matches) do
            local cap_str = captures[capture_id]
            local nodes_to_process = type(node_list) == 'table' and not node_list.type and node_list or {node_list}
            
            for _, node in ipairs(nodes_to_process) do
                if not node then goto continue_node end
                
                local node_type = node:type()
                if node_type == "type_identifier" and cap_str == "class_name" then
                    class_name = vim.treesitter.get_node_text(node, 0) or ''
                end
                ::continue_node::
            end
        end
    end
    
    -- First try to get class name
    if not run_on_nodes(class_query, class_runner, range_start, range_end) then
        return
    end
    
    -- Stage 2: Detect special member functions
    local special_result = run_on_nodes(special_query, runner, range_start, range_end)
    
    if not special_result then
        -- If special function query fails but we have class name, continue processing
        if not class_name then
            return
        end
    end
    
    -- If no special functions were found, set a default entry location
    -- This typically happens when the class has no special member functions at all
    if not entry_location then
        -- Default to the line before the closing brace
        -- range_end is 0-indexed, we want to insert before the closing brace
        local buf_line_count = vim.api.nvim_buf_line_count(0)
        local insert_row = math.min(range_end - 1, buf_line_count - 1)
        entry_location = { start_row = insert_row, start_col = 0 }
    end

    -- Check if class name was successfully obtained
    if not class_name then
        vim.notify("Error: Unable to find class name. Please ensure cursor is within a class definition.", vim.log.levels.ERROR)
        return
    end
    

    -- Rule of 3: Only supplement when partially implemented
    -- Skip conditions: fully implemented or not implemented at all
    local skip_rule_of_3 = (checkers.copy_assignment and checkers.copy_constructor and checkers.destructor) or
                            (not checkers.copy_assignment and not checkers.copy_constructor and not checkers.destructor)

    -- Rule of 5: Only supplement when partially implemented  
    -- Skip conditions: fully implemented or not implemented at all
    local skip_rule_of_5 = (checkers.copy_assignment and checkers.copy_constructor and checkers.destructor and
                                checkers.move_assignment and checkers.move_constructor) or
                            (not checkers.copy_assignment and not checkers.copy_constructor and not checkers.destructor and
                                not checkers.move_assignment and not checkers.move_constructor)

    if limit_at_3 and skip_rule_of_3 then
        local all_implemented = checkers.copy_assignment and checkers.copy_constructor and checkers.destructor
        local none_implemented = not checkers.copy_assignment and not checkers.copy_constructor and not checkers.destructor
        
        if all_implemented then
            vim.notify("Rule of 3: All functions already implemented", vim.log.levels.INFO)
        elseif none_implemented then
            vim.notify("Rule of 3: No special functions detected, default behavior sufficient", vim.log.levels.INFO)
        end
        return
    end

    if not limit_at_3 and skip_rule_of_5 then
        local all_implemented = checkers.copy_assignment and checkers.copy_constructor and checkers.destructor and
                                checkers.move_assignment and checkers.move_constructor
        local none_implemented = not checkers.copy_assignment and not checkers.copy_constructor and not checkers.destructor and
                                 not checkers.move_assignment and not checkers.move_constructor
        
        if all_implemented then
            vim.notify("Rule of 5: All functions already implemented", vim.log.levels.INFO)
        elseif none_implemented then
            vim.notify("Rule of 5: No special functions detected, default behavior sufficient", vim.log.levels.INFO)
        end
        return
    end

    local add_txt_below_existing_def = function (txt)
        util.add_text_edit(txt, entry_location.start_row, entry_location.start_col)
        entry_location.start_row = entry_location.start_row + 1
    end

    -- We are first adding a empty string on the required line which is of length start_col since
    -- lsp text edit cannot add strings beyond already edited region
    -- TODO need a stable method of handling this entry

    local newLine = string.format('%' .. (entry_location.start_col + 1) .. 's', '\n')

    if not checkers.copy_assignment then
        util.add_text_edit(newLine, entry_location.start_row, 0)
        local txt = class_name .. '& operator=(const ' .. class_name .. '&);'
        add_txt_below_existing_def(txt)
    end

    if not checkers.copy_constructor then
        util.add_text_edit(newLine, entry_location.start_row, 0)
        local txt = class_name .. '(const ' .. class_name .. '&);'
        add_txt_below_existing_def(txt)
    end

    if not checkers.destructor then
        util.add_text_edit(newLine, entry_location.start_row, 0)
        local txt = '~' .. class_name .. '();'
        add_txt_below_existing_def(txt)
    end

    if not limit_at_3 then
        if not checkers.move_assignment then
            util.add_text_edit(newLine, entry_location.start_row, 0)
            local txt = class_name .. '& operator=(' .. class_name .. '&&) noexcept;'
            add_txt_below_existing_def(txt)
        end

        if not checkers.move_constructor then
            util.add_text_edit(newLine, entry_location.start_row, 0)
            local txt = class_name .. '(' .. class_name .. '&&) noexcept;'
            add_txt_below_existing_def(txt)
        end
    end
end

function M.attach(bufnr, lang)
end

function M.detach(bufnr)
end

M.commands = {
    TSCppDefineClassFunc = {
        run = M.imp_func,
        f_args = "<line1>, <line2>",
        args = {
            "-range"
        }
    },
    TSCppMakeConcreteClass = {
        run = M.concrete_class_imp,
        f_args = "<line1>, <line2>",
        args = {
            "-range"
        }
    },
    TSCppRuleOf3 = {
        run = function (s, e) M.rule_of_5(true, s, e) end,
        f_args = "<line1>, <line2>",
        args = {
            "-range"
        }
    },
    TSCppRuleOf5 = {
        run = function (s, e) M.rule_of_5(false, s, e) end,
        f_args = "<line1>, <line2>",
        args = {
            "-range"
        }
    },
}

return M
