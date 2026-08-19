local _ = require("sui_i18n").translate
local InputDialog = require("ui/widget/inputdialog")
local CheckButton = require("ui/widget/checkbutton")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")

local FileChooser = require("ui/widget/filechooser")
local DocumentRegistry = require("document/documentregistry")
local SQ3 = require("lua-ljsqlite3/init")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")

local function addCachedBookSearch(FileSearcher)

    local db_path = "settings/bookinfo_cache.sqlite3"
    local conn = nil


    function FileSearcher:onShowCachedBooksSearch(search_string)
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

    
        print("do search cached book")

        


        local search_cached_books_hash = (FileSearcher.search_string or "") ..
            tostring(self.case_sensitive) .. tostring(self.search_by_tag)
        local not_cached = FileSearcher.search_cached_books_hash ~= search_cached_books_hash
        if not_cached then
            local Trapper = require("ui/trapper")
            local info = InfoMessage:new{ text = _("Searching… (tap to cancel)") }
            UIManager:show(info)
            UIManager:forceRePaint()
            local completed, dirs, files, no_metadata_count = Trapper:dismissableRunInSubprocess(function()
                return self:getCachedBookList()
            end, info)
            if not completed then return end
            UIManager:close(info)
            FileSearcher.search_cached_books_hash = search_cached_books_hash
            --self.no_metadata_count = no_metadata_count
            -- Cannot do this in getList() within Trapper (cannot serialize function)
            local fc = self.ui.file_chooser or FileChooser:new{ ui = self.ui }
            local collate = fc:getCollate()
            for i, v in ipairs(dirs) do
                local f, fullpath, attributes = unpack(v)
                dirs[i] = fc:getListItem(nil, f, fullpath, attributes, collate)
            end
            for i, v in ipairs(files) do
                local f, fullpath, attributes = unpack(v)

                print(f)
                files[i] = fc:getListItem(nil, f, fullpath, attributes, collate)
            end
            FileSearcher.search_results = fc:genItemTable(dirs, files)
        end
        if #FileSearcher.search_results > 0 then

            print(#FileSearcher.search_results)

            self.no_metadata_count = 0
            self:onShowSearchResults(not_cached)
        else
            self.no_metadata_count = 0
            self:showSearchResultsMessage(true)
        end
    end











    function FileSearcher:getCachedBookList()

        print("get cached books list")

        self.no_metadata_count = 0
        local search_string = FileSearcher.search_string

        -- Нормализуем поисковый запрос для SQL LIKE (приводим к нижнему регистру)
        local clean_search = self.case_sensitive and search_string or util.stringLower(search_string)
        local sql_search = "%" .. clean_search .. "%"



        local dirs, files = {}, {}

        print(sql_search)

        
        -- Запрос: ищем записи, где путь (key) начинается с текущей папки,
        -- и при этом поисковая строка совпадает либо с путем файла, либо с его метаданными (value)

        print(1)

        pcall(function()
            conn = SQ3.open(db_path)
        end)

        print(2)

        if not conn then 
            print("no conn")
            return dirs, files, self.no_metadata_count
        end

        print(3)

        local smth = conn:prepare([[
            SELECT filename, directory
            FROM bookinfo
            WHERE title LIKE ? 
        ]])

        print(4)
        
        smth:reset():bind(sql_search)

        print(5)

        local cursor = smth:rows()

        for row in cursor do
            if row and row[1] then 
                local filename = row[1]
                local directory = row[2] or ""
                local fullpath = directory .. filename 

                -- Получаем атрибуты файла, чтобы убедиться, что он физически существует
                local attributes = lfs.attributes(fullpath)
                if attributes and attributes.mode == "file" then
                    
                    -- Проверяем стандартные фильтры KOReader (скрытые файлы, поддержка формата)
                    local is_hidden = util.stringStartsWith(filename, ".")
                    local is_mac_fork = util.stringStartsWith(filename, "._")

                    if not is_mac_fork and (FileChooser.show_hidden or not is_hidden)
                    and (FileChooser.show_unsupported or DocumentRegistry:hasProvider(fullpath))
                    and FileChooser:show_file(filename) then

                        
                        
                        -- Структура элемента в таблице files: { имя, полный_путь, атрибуты }
                        table.insert(files, { filename, fullpath, attributes })
                    end
                end

                
            
            end
        end

        

            --[=[
            local fullpath = row
            
            -- Получаем атрибуты файла, чтобы убедиться, что он физически существует
            local attributes = lfs.attributes(fullpath)
            if attributes and attributes.mode == "file" then
                
                -- Проверяем стандартные фильтры KOReader (скрытые файлы, поддержка формата)
                local filename = fullpath:match("^.+/(.+)$") or fullpath
                local is_hidden = util.stringStartsWith(filename, ".")
                local is_mac_fork = util.stringStartsWith(filename, "._")

                if not is_mac_fork and (FileChooser.show_hidden or not is_hidden)
                and (FileChooser.show_unsupported or DocumentRegistry:hasProvider(fullpath))
                and FileChooser:show_file(filename) then
                    
                    -- Структура элемента в таблице files: { имя, полный_путь, атрибуты }
                    table.insert(files, { filename, fullpath, attributes })
                end
            end

            ]=]
            
        
       

        return dirs, files, self.no_metadata_count
    end







    
    local Dispatcher = package.loaded["dispatcher"]
    Dispatcher:registerAction("cached_books_search", {category="none", event="ShowCachedBooksSearch", title=_("Search cached books"), filemanager=true})
end

return addCachedBookSearch





--[=[
-- 1. Подключаем необходимые модули KOReader
local SQ3 = require("lua-ljsqlite3/init")
local util = require("util") -- Встроенный модуль утилит KOReader

local conn = SQ3.open_memory()

-- 2. SQL-генератор lower для колонки (база данных KOReader не знает про утилиты Lua)
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

-- ==========================================
-- ТЕСТ
-- ==========================================
conn:exec([[
    CREATE TABLE books (id INTEGER PRIMARY KEY, title TEXT);
    INSERT INTO books (title) VALUES ('Мастер и Маргарита');
    INSERT INTO books (title) VALUES ('МАСТЕР И МАРГАРИТА');
    INSERT INTO books (title) VALUES ('мастер и маргарита');
]])

-- Входящий поисковый запрос
local raw_search = "%Мастер%"

-- ИСПОЛЬЗУЕМ ВСТРОЕННЫЙ МЕТОД КОРЕДЕРА ДЛЯ СТРОКИ ПОИСКА
local safe_search_term = util.stringLower(raw_search) -- Станет "%мастер%" с полной поддержкой UTF-8

-- Собираем запрос с оператором LIKE
local sql_query = "SELECT title FROM books WHERE " .. sql_lower("title") .. " LIKE ?"

local stmt = conn:prepare(sql_query)
stmt:bind(safe_search_term)

print("Результаты поиска:")
for row in stmt:rows() do
    print("- " .. tostring(row[1])) 
end

stmt:close()
conn:close()


]=]