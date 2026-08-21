local _ = require("sui_i18n").translate
local InputDialog = require("ui/widget/inputdialog")
local CheckButton = require("ui/widget/checkbutton")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local BookList = require("ui/widget/booklist")
local ConfirmBox = require("ui/widget/confirmbox")
local FileChooser = require("ui/widget/filechooser")
local DocumentRegistry = require("document/documentregistry")
local SQ3 = require("lua-ljsqlite3/init")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")
local T = require("ffi/util").template

local function addCachedBookSearch(FileSearcher)

    local db_path = "settings/bookinfo_cache.sqlite3"
    local conn = nil


    function FileSearcher:onShowCachedBookSearch(search_string)
        if not self.ui.coverbrowser then return end
        local search_dialog, check_button_case

        local function _doSearch()
            local search_str = search_dialog:getInputText()
            if search_str == "" then return end
            FileSearcher.search_string = search_str
            UIManager:close(search_dialog)
            self.case_sensitive = check_button_case.checked

            local Trapper = require("ui/trapper")
            Trapper:wrap(function()
                self:doSearchCachedBook()
            end)
        end

        search_dialog = InputDialog:new{
            title = _("Enter text to search for"),
            input = search_string or FileSearcher.search_string,
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(search_dialog)
                        end,
                    },
                    {
                        text = _("Search by tag"),
                        callback = function()
                            self.search_by_tag = true
                            _doSearch()
                        end,
                    },
                    {
                        text = _("Search"),
                        callback = function()
                            self.search_by_tag = false
                            _doSearch()
                        end,
                    }
                },
            },
        }
        check_button_case = CheckButton:new{
            text = _("Case sensitive"),
            checked = self.case_sensitive,
            parent = search_dialog,
        }
        search_dialog:addWidget(check_button_case)
        UIManager:show(search_dialog)
        search_dialog:onShowKeyboard()
        return true
    end




    function FileSearcher:doSearchCachedBook()
        local search_cached_books_hash = (FileSearcher.search_string or "") ..
            tostring(self.case_sensitive) .. tostring(self.search_by_tag)
        local not_cached = FileSearcher.search_cached_books_hash ~= search_cached_books_hash
        if not_cached then
            local Trapper = require("ui/trapper")
            local info = InfoMessage:new{ text = _("Searching… (tap to cancel)") }
            UIManager:show(info)
            UIManager:forceRePaint()
            local completed, files = Trapper:dismissableRunInSubprocess(function()
                return self:getCachedBookList()
            end, info)

            if not completed then return end
            UIManager:close(info)
            FileSearcher.search_cached_books_hash = search_cached_books_hash

            local fc = self.ui.file_chooser or FileChooser:new{ ui = self.ui }
            local collate = fc:getCollate()

            for i, v in ipairs(files) do
                local f, fullpath, attributes = unpack(v)
                files[i] = fc:getListItem(nil, f, fullpath, attributes, collate)
            end
            FileSearcher.cached_books_search_results = fc:genItemTable({}, files)
        end
        if #FileSearcher.cached_books_search_results > 0 then
            self:onShowCachedBookSearchResults(not_cached)
        else
            self:showSearchCachedBookResultsMessage(true)
        end
    end





    function FileSearcher:getCachedBookList()
        local search_string = FileSearcher.search_string

        local clean_search = self.case_sensitive and search_string or util.stringLower(search_string)
        local sql_search = "%" .. clean_search .. "%"

        local function sql_lower(column_name)
            local cyrillic_pairs = {
                ["А"]="а", ["Б"]="б", ["В"]="в", ["Г"]="г", ["Д"]="д", ["Е"]="е", ["Ё"]="ё",
                ["Ж"]="ж", ["З"]="з", ["И"]="и", ["Й"]="й", ["К"]="к", ["Л"]="л", ["М"]="м",
                ["Н"]="н", ["О"]="о", ["П"]="п", ["Р"]="р", ["С"]="с", ["Т"]="т", ["У"]="у",
                ["Ф"]="ф", ["Х"]="х", ["Ц"]="ц", ["Ч"]="ч", ["Ш"]="ш", ["Щ"]="щ", ["Ъ"]="ъ",
                ["Ы"]="ы", ["Ь"]="ь", ["Э"]="э", ["Ю"]="ю", ["Я"]="я"
            }
            local sql = "LOWER(" .. column_name .. ")"
            for upper, lower in pairs(cyrillic_pairs) do
                sql = string.format("REPLACE(%s, '%s', '%s')", sql, upper, lower)
            end
            return sql
        end

        local files = {}

        pcall(function()
            conn = SQ3.open(db_path)
        end)

        if not conn then 
            return files
        end

        local stmt

        if self.search_by_tag then 
            if self.case_sensitive then
                stmt = conn:prepare([[
                SELECT filename, directory
                FROM bookinfo
                WHERE keywords LIKE ? 
            ]])
            else 
                stmt = conn:prepare([[
                SELECT filename, directory
                FROM bookinfo
                WHERE ]] .. sql_lower("keywords") .. [[ LIKE ? 
            ]])
            end
    
            stmt:reset():bind(sql_search)
        else 
            if self.case_sensitive then
                stmt = conn:prepare([[
                SELECT filename, directory
                FROM bookinfo
                WHERE title LIKE ? 
                    OR authors LIKE ? 
                    OR series LIKE ?
            ]])
            else 
                stmt = conn:prepare([[
                SELECT filename, directory
                FROM bookinfo
                WHERE ]] .. sql_lower("title") .. [[ LIKE ? 
                    OR ]] .. sql_lower("authors") .. [[ LIKE ? 
                    OR ]] .. sql_lower("series") .. [[ LIKE ?
            ]])
            end
    
            stmt:reset():bind(sql_search, sql_search, sql_search)
        end

        local rows = stmt:rows()

        for row in rows do
            if row and row[1] then 
                local filename = row[1]
                local directory = row[2] or ""
                local fullpath = directory .. filename 
                -- Получаем атрибуты файла, чтобы убедиться, что он физически существует
                local attributes = lfs.attributes(fullpath)
                if attributes and attributes.mode == "file" then
                    local is_hidden = util.stringStartsWith(filename, ".")
                    local is_mac_fork = util.stringStartsWith(filename, "._")
                    if not is_mac_fork and (FileChooser.show_hidden or not is_hidden)
                    and (FileChooser.show_unsupported or DocumentRegistry:hasProvider(fullpath))
                    and FileChooser:show_file(filename, fullpath) then
                        table.insert(files, { filename, fullpath, attributes })
                    end
                end
            end
        end
        stmt:close()
        conn:close()
        return files
    end




    function FileSearcher:onShowCachedBookSearchResults(not_cached)
        if not not_cached and FileSearcher.cached_books_search_results == nil then
            self:onShowCachedBookSearch()
            return true
        end
        self.booklist_menu = BookList:new{
            name = "filesearcher",
            subtitle = T(_("Query: %1"), FileSearcher.search_string),
            title_bar_left_icon = "appbar.menu",
            onLeftButtonTap = function() self:setSelectMode() end,
            onMenuSelect = self.onMenuSelect,
            onMenuHold = self.onMenuHold,
            ui = self.ui,
            _manager = self,
            _recreate_func = function() self:onShowCachedBookSearchResults(not_cached) end,
        }
        self.booklist_menu.close_callback = function()
            self:refreshFileManager()
            UIManager:close(self.booklist_menu)
            self.booklist_menu = nil
            if self.selected_files then
                self.selected_files = nil
                for _, item in ipairs(FileSearcher.cached_books_search_results) do
                    item.dim = nil
                end
            end
        end
        self:updateItemTable(FileSearcher.cached_books_search_results)
        UIManager:show(self.booklist_menu)
        if not_cached and FileSearcher.cached_books_search_results == nil then
            self:showSearchCachedBookResultsMessage()
        end
        return true
    end




    function FileSearcher:showSearchCachedBookResultsMessage(no_results)
        local text = no_results and T(_("No results for '%1'."), FileSearcher.search_string)
        UIManager:show(ConfirmBox:new{
            text = text,
            icon = "notice-info",
            ok_text = _("New search"),
            ok_callback = function()
                self:onShowCachedBookSearch()
            end,
        })
    end


    
    local Dispatcher = package.loaded["dispatcher"]
    Dispatcher:registerAction("cached_books_search", {category="none", event="ShowCachedBookSearch", title=_("Search cached books"), filemanager=true})
end

return addCachedBookSearch





