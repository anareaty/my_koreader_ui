local FileSearcher = require("apps/filemanager/filemanagerfilesearcher")

function FileSearcher:onShowCachedBooksSearch(search_string)
    return self:onShowFileSearch(search_string)
end


Dispatcher:registerAction("cached_books_search", {category="none", event="ShowCachedBooksSearch", title=_("Search cached books"), filemanager=true})