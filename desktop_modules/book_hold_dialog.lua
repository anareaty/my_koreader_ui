local ButtonDialog = require("ui/widget/buttondialog")
local FileManager = require("apps/filemanager/filemanager")
local UIManager       = require("ui/uimanager")
local util = require("util")
local _ = require("sui_i18n").translate

local BookHoldDialog = {}

function BookHoldDialog:openDialog(filepath)


    local buttons = {{
        {
            text = _("Show folder"),
            callback = function()
                FileManager:showFiles(filepath)
                local pathname = util.splitFilePathName(filepath)
                FileManager.instance.file_chooser:changeToPath(pathname, filepath)     
            end,
        }
    }}

    self.file_dialog = ButtonDialog:new{
        buttons = buttons,
        shrink_unneeded_width = true,
        shrink_min_width = 600,
    }
    UIManager:show(self.file_dialog)
end


return BookHoldDialog

