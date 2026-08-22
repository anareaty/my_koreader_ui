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



local function patchCollectionMenu(FileManagerCollection)

    function FileManagerCollection:isItemMatch(item)
        if self.match_table then
            if self.match_table.status then
                if self.match_table.status == "uncomplete" then
                    if BookList.getBookStatus(item.file) == "complete" then
                        return false
                    end
                elseif self.match_table.status ~= BookList.getBookStatus(item.file) then
                    return false
                end
            end
            if self.match_table.props then
                local doc_props = self.ui.bookinfo:getDocProps(item.file, nil, true)
                for prop, value in pairs(self.match_table.props) do
                    if (doc_props[prop] or self.empty_prop) ~= value then
                        return false
                    end
                end
            end
        end
        return true
    end





    function FileManagerCollection:showCollDialog()
        local collection_name = self.booklist_menu.path
        local coll_not_empty = #self.booklist_menu.item_table > 0
        local coll_dialog
        local function genFilterByStatusButton(button_status)
            local icon = "book.closed"
            if button_status == "reading" then
                icon = "book.opened"
            elseif button_status == "abandoned" then
                icon = "pause"
            elseif button_status == "uncomplete" then
                icon = "continue"
            elseif button_status == "complete" then
                icon = "check"
            end
            return {
                --text = BookList.getBookStatusString(button_status),
                icon = icon,
                enabled = coll_not_empty,
                callback = function()
                    UIManager:close(coll_dialog)
                    util.tableSetValue(self, button_status, "match_table", "status")
                    self:updateItemTable()
                end,
                hold_callback = function()
                    UIManager:show(InfoMessage:new{ text = "hold callback" })
                end
            }
        end
        local function genFilterByMetadataButton(button_text, button_prop)

            
            if self.match_table and self.match_table.props and self.match_table.props[button_prop] then
                button_text = button_text .. "  \u{2713}"
            end


            return {
                text = button_text,  

                --icon = button_icon,
                enabled = coll_not_empty,
                callback = function()
                    UIManager:close(coll_dialog)
                    local prop_values = {}
                    for idx, item in ipairs(self.booklist_menu.item_table) do
                        local doc_prop = self.ui.bookinfo:getDocProps(item.file, nil, true)[button_prop]
                        if doc_prop == nil then
                            doc_prop = { self.empty_prop }
                        elseif button_prop == "series" then
                            doc_prop = { doc_prop }
                        elseif button_prop == "language" then
                            doc_prop = { doc_prop:lower() }
                        elseif button_prop == "keywords" then
                            doc_prop = util.splitToArray(doc_prop, "\n")
                        elseif button_prop == "authors" then
                            -- авторы разделены запятыми
                            doc_prop = util.splitToArray(doc_prop, ",")
                            -- Поменять местами имя и фамилию автора
                            for i, author in pairs(doc_prop) do
                                -- Убрать пробелы в начале и в конце
                                author = author:match("^%s*(.-)%s*$") or ""
                                local last_space = author:reverse():find(" ")
                                if last_space then
                                    local last_name = author:sub(-last_space + 1)
                                    local first_name = author:sub(1, -last_space - 1)
                                    author = last_name .. " " .. first_name
                                end
                                author = author:match("^%s*(.-)%s*$") or ""
                                doc_prop[i] = author
                            end
                        end


                        for _, prop in ipairs(doc_prop) do
                            prop_values[prop] = prop_values[prop] or {}
                            table.insert(prop_values[prop], idx)
                        end
                    end
                    self:showPropValueList(button_prop, prop_values)
                end,
                hold_callback = function()
                    UIManager:close(coll_dialog)
                    util.tableSetValue(self, nil, "match_table", "props", button_prop)
                    self:updateItemTable()
                end
            }
        end
        local buttons = {
            {{
                text = _("Collections"),
                callback = function()
                    UIManager:close(coll_dialog)
                    self.booklist_menu.close_callback()
                    self:onShowCollList()
                end,
            }},


            {
                genFilterByStatusButton("new"),
                genFilterByStatusButton("reading"),
                genFilterByStatusButton("abandoned"),
                genFilterByStatusButton("complete"),
                genFilterByStatusButton("uncomplete"),
            },
            {
                genFilterByMetadataButton("Авторы", "authors"),
                genFilterByMetadataButton("Циклы", "series"),
                genFilterByMetadataButton("Тэги", "keywords"),
            },
            {{
                text = _("Reset all filters"),
                enabled = self.match_table ~= nil,
                callback = function()
                    UIManager:close(coll_dialog)
                    self.match_table = nil
                    self:updateItemTable()
                end,
            }},

            {
                {
                    icon = "select",
                    enabled = coll_not_empty,
                    callback = function()
                        UIManager:close(coll_dialog)
                        self:toggleSelectMode()
                    end,
                },
                {
                    icon = "search2",
                    enabled = coll_not_empty,
                    callback = function()
                        UIManager:close(coll_dialog)
                        self:onShowCollectionsSearchDialog(nil, collection_name)
                    end,
                },
                {
                    icon = "sort",
                    enabled = coll_not_empty and self.match_table == nil,
                    callback = function()
                        UIManager:close(coll_dialog)
                        self:showArrangeBooksDialog()
                    end,
                },
                {
                    icon = "add", 
                    callback = function()
                        UIManager:show(self.more_dialog)
                    end,
                }
            },
            
        }


        local more_buttons = {
            {{
                text = _("Add all books from a folder"),
                callback = function()
                    UIManager:close(coll_dialog)
                    self:addBooksFromFolder(false)
                end,
            }},
            {{
                text = _("Add all books from a folder and its subfolders"),
                callback = function()
                    UIManager:close(coll_dialog)
                    self:addBooksFromFolder(true)
                end,
            }},
            {{
                text = _("Add a book to collection"),
                callback = function()
                    UIManager:close(coll_dialog)
                    local PathChooser = require("ui/widget/pathchooser")
                    local path_chooser = PathChooser:new{
                        path = G_reader_settings:readSetting("home_dir"),
                        select_directory = false,
                        onConfirm = function(file)
                            if not ReadCollection:isFileInCollection(file, collection_name) then
                                self.updated_collections[collection_name] = true
                                ReadCollection:addItem(file, collection_name)
                                self:updateItemTable(nil, file) -- show added item
                                self.files_updated = self.show_mark
                            end
                        end,
                    }
                    UIManager:show(path_chooser)
                end,
            }},
        }



        if self.ui.document then
            local file = self.ui.document.file
            local is_in_collection = ReadCollection:isFileInCollection(file, collection_name)
            table.insert(buttons, {{
                text_func = function()
                    return is_in_collection and _("Remove current book from collection") or _("Add current book to collection")
                end,
                callback = function()
                    UIManager:close(coll_dialog)
                    self.updated_collections[collection_name] = true
                    if is_in_collection then
                        ReadCollection:removeItem(file, collection_name, true)
                        file = nil
                    else
                        ReadCollection:addItem(file, collection_name)
                    end
                    self:updateItemTable(nil, file)
                    self.files_updated = self.show_mark
                end,
            }})
        end
        coll_dialog = ButtonDialog:new{
            buttons = buttons,
            shrink_unneeded_width = true,
            shrink_min_width = 700
        }
        UIManager:show(coll_dialog)

        
        self.more_dialog = ButtonDialog:new{
            buttons = more_buttons,
            shrink_unneeded_width = true,
            shrink_min_width = 900
        }
    end
end



return patchCollectionMenu













