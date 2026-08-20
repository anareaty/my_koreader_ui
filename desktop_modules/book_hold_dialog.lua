local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local FileManager = require("apps/filemanager/filemanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local ReadCollection = require("readcollection")
local Screen = Device.screen
local UIManager       = require("ui/uimanager")
local util = require("util")
local _ = require("sui_i18n").translate
local C_ = require("gettext").pgettext

local BookHoldDialog = {}



function genStatusButtonsRow(doc_settings_or_file, caller_callback)
    local file, summary, status
    if type(doc_settings_or_file) == "table" then
        file = doc_settings_or_file:readSetting("doc_path")
        summary = doc_settings_or_file:readSetting("summary") or {}
        status = summary.status
    else
        file = doc_settings_or_file
        summary = {}
        status = BookList.getBookStatus(file)
    end

    local function genStatusButton(to_status)
        local icon = "book.closed"
        if to_status == "reading" then 
            icon = "book.opened"
        elseif to_status == "abandoned" then 
            icon = "pause"
        elseif to_status == "complete" then
            icon = "check"
        end
        return {
            icon = icon,
            width = 150,
            enabled = status ~= to_status,
            callback = function()
                summary.status = to_status
                filemanagerutil.saveSummary(doc_settings_or_file, summary)
                BookList.setBookInfoCacheProperty(file, "status", to_status)
                caller_callback()
            end,
        }
    end
    return {
        genStatusButton("new"),
        genStatusButton("reading"),
        genStatusButton("abandoned"),
        genStatusButton("complete"),
    }
end













local function genStarGroup(file, doc_settings_or_file, caller_callback)
    local summary
    if doc_settings_or_file.readSetting ~= nil then
        summary = doc_settings_or_file:readSetting("summary")
    end
    if summary == nil then summary = { rating = 0 } end
    local rating = summary.rating or 0
    
    local function starCallback(star_num) 
        if summary.rating == 1 and star_num == 1 then
            summary.rating = 0
        else
            summary.rating = star_num
        end
        filemanagerutil.saveSummary(doc_settings_or_file, summary)
        BookList.setBookInfoCacheProperty(file, "rating", summary.rating)
        caller_callback()
    end

    local empty_star = Button:new{
        icon = "star.empty",
        bordersize = 0,
        radius = 0,
        margin = 0,
        width = 120,
        icon_width = Screen:scaleBySize(30)
    }

    local row = {}

    for i = 1, rating do
        local star = empty_star:new{
            icon = "star.full",
            callback = function() 
                starCallback(i)
            end
        }
        table.insert(row, star)
    end

    for i = rating + 1, 5 do
        local star = empty_star:new{ 
            callback = function() 
                starCallback(i)
            end 
        }
        table.insert(row, star)
    end

    return row
end












function genAddToCollectionButton(ctx, file_or_files, caller_pre_callback, caller_post_callback)
    local file_manager_collections

    if ctx.type == "filemanager" then
        file_manager_collections = ctx.ctx_self.collections
    elseif ctx.type == "history" or ctx.type == "filesearcher" then
        file_manager_collections = ctx.ctx_self._manager.ui.collections
    elseif ctx.type == "collection" then
        file_manager_collections = ctx.ctx_self._manager
    else
        file_manager_collections = FileManager.instance.collections
    end
    
    local is_single_file = type(file_or_files) == "string"
    return {
        text = _("Collections"),
        enabled = true,
        callback = function()
            if caller_pre_callback then
                caller_pre_callback()
            end
            local caller_callback = function(selected_collections)
                for name in pairs(selected_collections) do
                    file_manager_collections.updated_collections[name] = true
                end
                if is_single_file then
                    ReadCollection:addRemoveItemMultiple(file_or_files, selected_collections)
                else -- selected files
                    ReadCollection:addItemsMultiple(file_or_files, selected_collections)
                end
                if caller_post_callback then
                    caller_post_callback()
                end
            end
            -- Для быстроты добавления книг в подборку, выключаем диалог подтверждения. 
            -- При этом мы не сможем создать новую подборку из данного окна, так что придётся их создавать отдельно.
            -- Или потом написать патч, чтобы добавить другой способ
            -- Может быть, на долгое нажатие на кнопку.
            local ignore_dialog = true
            file_manager_collections:onShowCollList(is_single_file and file_or_files or {}, caller_callback, ignore_dialog)
        end,
    }
end




function BookHoldDialog:openDialog(file, ctx)

    local fm = FileManager.instance
    local fc =  fm and fm.file_chooser
    local ctx_self = ctx.ctx_self

    local ctx_ui
    local is_widget

    if ctx.type == "filesearcher" or ctx.type == "collection" or ctx.type == "history" then
        ctx_ui = ctx_self.ui
        is_widget = true
    elseif ctx.type == "filemanager" then
        ctx_ui = ctx_self
    else
        ctx_ui = fm
    end

    local is_file = true

    if ctx.type == "filemanager" then
        is_file = ctx.item and ctx.item.is_file
    end
 
    local is_not_parent_folder = not (ctx.item and ctx.item.is_go_up)


    local function refreshHomeScreen()
        local HS = package.loaded["sui_homescreen"]
        if not (HS and HS._instance)  then return end
        HS._instance:_refreshImmediate(false)
    end



    -- Коллбэки

    -- Закрыть диалоги

    local function close_dialog_callback()
        UIManager:close(self.file_dialog)
        UIManager:close(self.more_dialog)
    end

    -- Обновить виджет

    local function refresh_callback()
        if ctx.type == "filemanager" then
            ctx_ui.file_chooser:refreshPath()
        elseif is_widget then
            ctx_self._manager:updateItemTable()
            ctx_self._manager.files_updated = true
        else
            refreshHomeScreen()
        end
    end

    -- Закрыть диалоги и обновить виджет

    local function close_dialog_refresh_callback()
        close_dialog_callback()
        refresh_callback()
    end

    -- Обновить диалог и обновить виджет

    local function update_dialog_refresh_callback()
        close_dialog_callback()
        self:openDialog(file, ctx)
        refresh_callback()
    end


    -- Обновить диалог и обновить виджет с обновлением истории

    local function close_dialog_update_callback()
        close_dialog_callback()

        if ctx.type == "history" then
            if ctx_self._manager.filter ~= "all" or ctx_self._manager.is_frozen then
                ctx_self._manager:fetchStatuses(false)
            else
                ctx_self._manager.statuses_fetched = false
            end
        end

        refresh_callback()
    end

    -- Закрыть диалоги и закрыть виджет

    local function close_dialog_menu_callback()
        close_dialog_callback()
        if is_widget then
            ctx_self.close_callback()
        end
    end





    

    


    

    





    local buttons = {}
    local more_buttons = {}
    local fm_buttons = {
        {
            {
                text = C_("File", "Paste"),
                enabled = fm.clipboard and true or false,
                callback = function()
                    UIManager:close(self.more_dialog)
                    fm:pasteFileFromClipboard(file)
                end,
            },
            {
                text = _("Select"),
                callback = function()
                    UIManager:close(self.more_dialog)
                    fm:onToggleSelectMode()
                    if is_file then
                        fm.selected_files[file] = true
                        ctx.item.dim = true
                        ctx_self:updateItems(1, true)
                    end
                end,
            },
            {
                text = _("Rename"),
                enabled = is_not_parent_folder,
                callback = function()
                    UIManager:close(self.more_dialog)
                    fm:showRenameFileDialog(file, is_file)
                end,
            },
        },
        {
            {
                text = _("Delete"),
                enabled = is_not_parent_folder,
                callback = function()
                    UIManager:close(self.more_dialog)
                    fm:showDeleteFileDialog(file, refresh_callback)
                end,
            },
            {
                text = _("Cut"),
                enabled = is_not_parent_folder,
                callback = function()
                    UIManager:close(self.more_dialog)
                    fm:cutFile(file)
                end,
            },
            {
                text = C_("File", "Copy"),
                enabled = is_not_parent_folder,
                callback = function()
                    UIManager:close(self.more_dialog)
                    fm:copyFile(file)
                end,
            },
        }

    }

    local book_props, is_currently_opened
    
    if is_file then 
        local has_provider = DocumentRegistry:hasProvider(file)
        local been_opened = BookList.hasBookBeenOpened(file)
        local doc_settings_or_file = file
        
        if has_provider or been_opened then
            book_props = ctx_ui.coverbrowser and ctx_ui.coverbrowser:getBookInfo(file)

            if is_widget then
                is_currently_opened = file == (ctx_ui.document and ctx_ui.document.file)
            end

            if is_currently_opened then
                doc_settings_or_file = ctx_ui.doc_settings
                if not book_props then
                    book_props = ctx_ui.doc_props
                end
            elseif been_opened then
                doc_settings_or_file = BookList.getDocSettings(file)
                if not book_props then
                    local props = doc_settings_or_file:readSetting("doc_props")
                    book_props = ctx_ui.bookinfo.extendProps(props, file)
                end
            end

            table.insert(buttons, genStatusButtonsRow(doc_settings_or_file, update_dialog_refresh_callback))
            table.insert(buttons, genStarGroup(file, doc_settings_or_file, update_dialog_refresh_callback))

        end


        table.insert(buttons, {genAddToCollectionButton(ctx, file, close_dialog_callback, close_dialog_update_callback)})


        local resetSettingsButton = filemanagerutil.genResetSettingsButton(doc_settings_or_file, close_dialog_refresh_callback)
        local reset_callback_orig = resetSettingsButton.callback
        resetSettingsButton.callback = function()
            reset_callback_orig()
            UIManager:close(self.more_dialog)
        end

        if ctx.type == "filemanager" then
            more_buttons = fm_buttons
            table.insert(more_buttons, {resetSettingsButton})
        else
            table.insert(more_buttons, {
                resetSettingsButton,
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(self.more_dialog)
                        fm:showDeleteFileDialog(file, refresh_callback)
                    end,
                }
            })
        end

        table.insert(more_buttons, {
            filemanagerutil.genBookDescriptionButton(file, book_props, close_dialog_callback)
        })


        if fm.file_dialog_added_buttons ~= nil then
            for i, row_func in ipairs(fm.file_dialog_added_buttons) do
                local row = row_func(file, true, book_props)
                if row ~= nil then
                    for i, button in pairs(row) do

                        local callback_orig = button.callback
                        button.callback = function()
                            callback_orig()
                            close_dialog_refresh_callback()
                        end
                        
                        if button.text == _("Remove from To Be Read") or 
                        button.text == _("Add to To Be Read") then

                            button.callback = function()
                                close_dialog_callback()
                                callback_orig()
                            end

                            table.insert(buttons, {button})
                        elseif button.text ~= _("Ignore cover") and
                        button.text ~= _("Unignore cover") and
                        button.text ~= _("Ignore metadata") and
                        button.text ~= _("Unignore metadata") and 
                        (button.text ~= _("Refresh cached book information") or ctx.type ~= "sui_homescreen") then
                            table.insert(more_buttons, {button})
                        end
                    end
                end
            end
        end



        local author, author_books_count
        local series, series_books_count
        local ok_bm, BM = pcall(require, "sui_browsemeta")
        if ok_bm and BM then 
            local authors_raw = book_props and book_props.authors
            if authors_raw and authors_raw ~= "" then
                author = authors_raw:match("^([^,]+)") or authors_raw
                author = author:match("^%s*(.-)%s*$") -- trim whitespace
                author_books_count = BM.getAuthorBookCount(author) or 1
            end

            series = book_props and book_props.series

            if series and series ~= "" then
                series_books_count = BM.getSeriesBookCount(series) or 1
            end
        end

        if author and author_books_count and author_books_count > 1 then
            table.insert(buttons, {
                {
                    text = _("More by author"),
                    callback = function()
                        close_dialog_menu_callback()
                        local target = "/\u{E257}/\u{F2C0}/" .. author
                        if ctx.type == "sui_homescreen" then
                            FileManager:showFiles(file)
                        end
                        FileManager.instance.file_chooser:changeToPath(target)   
                    end,
                }
            })
        end

        if series and series_books_count and series_books_count > 1 then
            table.insert(buttons, {
                {
                    text = _("More in series"),
                    callback = function()
                        close_dialog_menu_callback()
                        local target = "/\u{E257}/\u{ECD7}/" .. series
                        if ctx.type == "sui_homescreen" then
                            FileManager:showFiles(file)
                        end
                        FileManager.instance.file_chooser:changeToPath(target) 
   
                    end,
                }
            })
        end






            






        if ctx.type == "collection" then
            table.insert(buttons, {
                {
                    text = _("Remove from collection"),
                    callback = function()
                        ctx_self._manager.updated_collections[ctx_self.path] = true
                        ReadCollection:removeItem(file, ctx_self.path, true)
                        close_dialog_update_callback()
                    end,
                },
            })
        elseif ctx.type == "history" then
            table.insert(buttons, {
                {
                    text = _("Remove from history"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        local item = ctx.item
                        local index = item.idx
                        if ctx_self._manager.search_string or ctx_self._manager.selected_collections or ctx_self._manager.filter ~= "all" then
                            index = nil
                        end
                        require("readhistory"):removeItem(item, index)
                        ctx_self._manager:updateItemTable()
                    end,
                }
            })
        end

        -- Показать папку
        if ctx.type == "sui_homescreen" then
            table.insert(buttons, {
                {
                    text = _("Show folder"),
                    callback = function()
                        FileManager:showFiles(file)
                        local parent_folder = util.splitFilePathName(file)
                        FileManager.instance.file_chooser:changeToPath(parent_folder, file)     
                    end,
                }
            })



        elseif is_widget then
            table.insert(buttons, {
                filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback),
            })
        end

        table.insert(buttons, {{
            text = _("..."),
            callback = function()
                UIManager:close(self.file_dialog)
                UIManager:show(self.more_dialog)
            end,
        }})
    else -- folder
        local folder = ffiUtil.realpath(file)
        buttons = fm_buttons
        table.insert(more_buttons, 1,  {
            {
                text = _("Set as HOME folder"),
                callback = function()
                    UIManager:close(self.file_dialog)
                    fm:setHome(folder)
                end
            },
        })

        local addRemoveShortcutButton = fm.folder_shortcuts:genAddRemoveShortcutButton(folder, close_dialog_callback, refresh_callback)
        local add_remove_shortcut_callback_orig = addRemoveShortcutButton.callback
        addRemoveShortcutButton.callback = function()
            add_remove_shortcut_callback_orig()
            UIManager:close(self.file_dialog)
        end

        table.insert(more_buttons, {
            fm.folder_shortcuts:genAddRemoveShortcutButton(folder, close_dialog_callback, refresh_callback)
        })
    end


    


    



    




    

    self.file_dialog = ButtonDialog:new{
        title = book_props.title or BD.filename(file:match("([^/]+)$")),
        title_align = "center",
        buttons = buttons,
        shrink_unneeded_width = true,
        shrink_min_width = 700,
    }
    UIManager:show(self.file_dialog)


    self.more_dialog = ButtonDialog:new{
        title = BD.filename(file:match("([^/]+)$")),
        title_align = "center",
        buttons = more_buttons,
        shrink_unneeded_width = true,
        shrink_min_width = 800,
    }

end


return BookHoldDialog

