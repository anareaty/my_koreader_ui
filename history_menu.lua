local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local ReadCollection = require("readcollection")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Utf8Proc = require("ffi/utf8proc")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local FileManager = require("apps/filemanager/filemanager")
local Button = require("ui/widget/button")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Geom = require("ui/geometry")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local Device = require("device")
local Screen = Device.screen
local TitleBar = require("ui/widget/titlebar")
local InfoMessage = require("ui/widget/infomessage")




local function patchHistoryMenu(FileManagerHistory)
    function FileManagerHistory:showHistDialog()
        if not self.statuses_fetched then
            self:fetchStatuses(true)
        end

        local hist_dialog
        local buttons = {}
        local function genFilterButton(filter)

            local button_text = T(_("%1 (%2)"), BookList.getBookStatusString(filter), self.count[filter])
            if self.filter == filter then
                button_text = "◉ " .. button_text
            else
                button_text = "○ " .. button_text
            end
            
            return {
                text = button_text,
                menu_style = true,
                callback = function()
                    UIManager:close(hist_dialog)
                    self.filter = filter
                    if filter == "all" then -- reset all filters
                        self.search_string = nil
                        self.selected_collections = nil
                    end
                    self:updateItemTable()
                end,
            }
        end
        table.insert(buttons, {
            genFilterButton("all"),

        })
        table.insert(buttons, {
            genFilterButton("new"),
        })
        
        table.insert(buttons, {
            genFilterButton("reading"),
        })
        table.insert(buttons, {
            genFilterButton("abandoned"),
        })
        table.insert(buttons, {
            genFilterButton("complete"),
        })
        table.insert(buttons, {
            genFilterButton("deleted"),
        })

        local icon_row = {}

        table.insert(icon_row, {
            icon = "books",
            callback = function()
                UIManager:close(hist_dialog)
                local caller_callback = function(selected_collections)
                    self.selected_collections = selected_collections
                    self:updateItemTable()
                end
                self.ui.collections:onShowCollList(self.selected_collections or {}, caller_callback, true) -- no dialog to apply
            end,
        })


        table.insert(icon_row, 
            {
                icon = "search2",
                callback = function()
                    UIManager:close(hist_dialog)
                    self:onSearchHistory()
                end,
            }
        )
        if self.count.deleted > 0 then

            table.insert(icon_row, 
                {
                    --text = _("Clear history of deleted files"),
                    icon = "clear",
                    callback = function()
                        local confirmbox = ConfirmBox:new{
                            text = _("Clear history of deleted files?"),
                            ok_text = _("Clear"),
                            ok_callback = function()
                                UIManager:close(hist_dialog)
                                require("readhistory"):clearMissing()
                                self:updateItemTable()
                            end,
                        }
                        UIManager:show(confirmbox)
                    end,
                }
            )
        end


        table.insert(buttons, icon_row)
        hist_dialog = ButtonDialog:new{
            buttons = buttons,
            shrink_unneeded_width = true,
            anchor = function()
                local dimen = Geom:new {
                    y = 120,
                    x = 120
                }

                return dimen
            end,
        }
        UIManager:show(hist_dialog)
    end
end


return patchHistoryMenu














