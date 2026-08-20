local FileChooser = require("ui/widget/filechooser")
local BookList = require("ui/widget/booklist")
local UIManager = require("ui/uimanager")
local _ = require("sui_i18n").translate
local ButtonDialog = require("ui/widget/buttondialog")
local util  = require("util")

local M = {}

function M.showFilterByStatusMenu(fm)

    local statuses = { "new", "reading", "abandoned", "complete" }
    local buttons = {
        {{
            text_func = function()
                local marker = "◯ "
                if FileChooser.show_filter.status == nil then
                    marker = "◉ "
                end
                return marker .. BookList.getBookStatusString("all")
            end,
            align = "left",
            callback = function()
                FileChooser.show_filter.status = nil
                fm.file_chooser:refreshPath()
                UIManager:close(M.status_dialog)
                M.showFilterByStatusMenu(fm)
            end,
        }},
    }

    for _, v in ipairs(statuses) do
        table.insert(buttons, {{
            text_func = function()
                local marker = "☐ "
                if FileChooser.show_filter.status and FileChooser.show_filter.status[v] then
                    marker = "☑ "
                end
                return marker .. BookList.getBookStatusString(v)
            end,
            align = "left",
            
            callback = function()
                FileChooser.show_filter.status = FileChooser.show_filter.status or {}
                FileChooser.show_filter.status[v] = not FileChooser.show_filter.status[v] or nil
                local statuses_nb = util.tableSize(FileChooser.show_filter.status)
                if statuses_nb == 0 or statuses_nb == #statuses then
                    FileChooser.show_filter.status = nil
                end
                fm.file_chooser:refreshPath()
                UIManager:close(M.status_dialog)
                M.showFilterByStatusMenu(fm)
            end,
        }})
    end


    M.status_dialog = ButtonDialog:new{
        title       = _("Filter by status"),
        title_align = "center",
        align = "left",
        shrink_unneeded_width = true,
        shrink_min_width = 500,
        buttons = buttons
    }
    UIManager:show(M.status_dialog)
end





function M.showFilterByRatingMenu(fm)

    local ratings = { "☆☆☆☆☆", "★☆☆☆☆", "★★☆☆☆", "★★★☆☆", "★★★★☆", "★★★★★" }
    local buttons = {
        {{
            text_func = function()
                local marker = "◯ "
                if FileChooser.show_filter.rating == nil then
                    marker = "◉ "
                end
                return marker .. BookList.getBookStatusString("all")
            end,
            align = "left",
            callback = function()
                FileChooser.show_filter.rating = nil
                fm.file_chooser:refreshPath()
                UIManager:close(M.rating_dialog)
                M.showFilterByRatingMenu(fm)
            end,
        }},
    }

    for i, v in ipairs(ratings) do
        table.insert(buttons, {{
            text_func = function()
                local marker = "☐ "
                if FileChooser.show_filter.rating and FileChooser.show_filter.rating[i] then
                    marker = "☑ "
                end
                return marker .. v
            end,
            align = "left",
            
            callback = function()
                FileChooser.show_filter.rating = FileChooser.show_filter.rating or {}
                FileChooser.show_filter.rating[i] = not FileChooser.show_filter.rating[i] or nil
                local ratings_nb = util.tableSize(FileChooser.show_filter.rating)
                if ratings_nb == 0 or ratings_nb == #ratings then
                    FileChooser.show_filter.rating = nil
                end
                fm.file_chooser:refreshPath()
                UIManager:close(M.rating_dialog)
                M.showFilterByRatingMenu(fm)
            end,
        }})
    end


    M.rating_dialog = ButtonDialog:new{
        title       = _("Filter by rating"),
        title_align = "center",
        align = "left",
        shrink_unneeded_width = true,
        shrink_min_width = 500,
        
        buttons = buttons
    }
    UIManager:show(M.rating_dialog)
end


return M