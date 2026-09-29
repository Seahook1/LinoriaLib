--[[
    ThemeManager (file-driven)
    - On first run: writes the 11 built-in themes as .json files
    - Afterwards: everything is read from LinoriaLibSettings/themes/*.json
    - Users can edit those JSONs by hand to tweak any theme
]]

local httpService = game:GetService('HttpService')

local ThemeManager = {} do
    ThemeManager.Folder = 'LinoriaLibSettings'
    ThemeManager.Library = nil
    ThemeManager.CurrentTheme = 'Default'
    ThemeManager.Ignore = {}

    ------------------------------------------------------------------
    -- Keys we know how to read/write
    ------------------------------------------------------------------
    ThemeManager.ThemeKeys = {
        'MainColor', 'BackgroundColor', 'AccentColor',
        'OutlineColor', 'FontColor', 'RiskColor'
    }

    -- Preferred order for the built-in seed pack (also used for sort order)
    ThemeManager.BuiltInOrder = {
        'Default', 'BBot', 'Fatality', 'Ocean', 'Nord',
        'Dracula', 'Gruvbox', 'Rose Pine', 'Tokyo Night',
        'Catppuccin', 'Light',
    }

    -- Seed data used only if the corresponding .json is missing.
    -- All hex values match the JSON files shown above.
    ThemeManager.SeedThemes = {
        ['Default']     = { MainColor = '1C1C1C', BackgroundColor = '141414', AccentColor = '0055FF', OutlineColor = '323232', FontColor = 'FFFFFF', RiskColor = 'FF3232' },
        ['BBot']        = { MainColor = '181818', BackgroundColor = '121212', AccentColor = '00FFAA', OutlineColor = '282828', FontColor = 'F0F0F0', RiskColor = 'FF3232' },
        ['Fatality']    = { MainColor = '1E1E1E', BackgroundColor = '161616', AccentColor = 'FF6464', OutlineColor = '373737', FontColor = 'FFFFFF', RiskColor = 'FF3232' },
        ['Ocean']       = { MainColor = '1A222E', BackgroundColor = '121822', AccentColor = '40AAFF', OutlineColor = '303C4E', FontColor = 'E6F0FF', RiskColor = 'FF5050' },
        ['Nord']        = { MainColor = '2E3440', BackgroundColor = '242933', AccentColor = '88C0D0', OutlineColor = '3B4252', FontColor = 'D8DEE9', RiskColor = 'BF616A' },
        ['Dracula']     = { MainColor = '282A36', BackgroundColor = '21222C', AccentColor = 'BD93F9', OutlineColor = '44475A', FontColor = 'F8F8F2', RiskColor = 'FF5555' },
        ['Gruvbox']     = { MainColor = '282828', BackgroundColor = '1D2021', AccentColor = 'D79921', OutlineColor = '3C3836', FontColor = 'EBDBB2', RiskColor = 'CC241D' },
        ['Rose Pine']   = { MainColor = '1F1D2E', BackgroundColor = '191724', AccentColor = 'EB6F92', OutlineColor = '403D52', FontColor = 'E0DEF4', RiskColor = 'F6C177' },
        ['Tokyo Night'] = { MainColor = '1A1B26', BackgroundColor = '14151F', AccentColor = '7AA2F7', OutlineColor = '333754', FontColor = 'C0CAF5', RiskColor = 'F7768E' },
        ['Catppuccin']  = { MainColor = '1E1E2E', BackgroundColor = '181825', AccentColor = 'CBA6F7', OutlineColor = '313244', FontColor = 'CDD6F4', RiskColor = 'F38BA8' },
        ['Light']       = { MainColor = 'F0F0F0', BackgroundColor = 'FFFFFF', AccentColor = '0055FF', OutlineColor = 'C8C8C8', FontColor = '141414', RiskColor = 'DC3232' },
    }

    ------------------------------------------------------------------
    -- Filesystem helpers
    ------------------------------------------------------------------
    function ThemeManager:SetFolder(folder)
        self.Folder = folder
        self:BuildFolderTree()
        self:SeedBuiltInThemes()
    end

    function ThemeManager:ThemePath(name)
        return self.Folder .. '/themes/' .. name .. '.json'
    end

    function ThemeManager:BuildFolderTree()
        local paths = {
            self.Folder,
            self.Folder .. '/themes',
            self.Folder .. '/settings',
        }
        for _, p in next, paths do
            if not isfolder(p) then makefolder(p) end
        end
    end

    -- Write the built-in .json files if they don't exist yet.
    -- Existing files are NEVER overwritten — so user edits survive.
    function ThemeManager:SeedBuiltInThemes()
        for _, name in next, self.BuiltInOrder do
            local path = self:ThemePath(name)
            if not isfile(path) then
                local ok, encoded = pcall(httpService.JSONEncode, httpService, self.SeedThemes[name])
                if ok then
                    pcall(writefile, path, encoded)
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- Read / write
    ------------------------------------------------------------------
    function ThemeManager:ReadThemeFile(name)
        local path = self:ThemePath(name)
        if not isfile(path) then return nil, 'theme file not found' end

        local ok, decoded = pcall(httpService.JSONDecode, httpService, readfile(path))
        if not ok then return nil, 'decode error' end

        local theme = {}
        for _, key in next, self.ThemeKeys do
            local v = decoded[key]
            if type(v) == 'string' then
                local cOK, c = pcall(Color3.fromHex, v)
                if cOK then theme[key] = c end
            end
        end
        return theme
    end

    function ThemeManager:SaveTheme(name)
        if (not name) or name:gsub(' ', '') == '' then
            return false, 'invalid theme name'
        end

        local data = {}
        for _, key in next, self.ThemeKeys do
            data[key] = self.Library[key]:ToHex()
        end

        local ok, encoded = pcall(httpService.JSONEncode, httpService, data)
        if not ok then return false, 'encode error' end

        local writeOK = pcall(writefile, self:ThemePath(name), encoded)
        if not writeOK then return false, 'write failed' end
        return true
    end

    function ThemeManager:DeleteTheme(name)
        local path = self:ThemePath(name)
        if isfile(path) then
            delfile(path)
            return true
        end
        return false, 'theme does not exist'
    end

    ------------------------------------------------------------------
    -- Apply
    ------------------------------------------------------------------
    function ThemeManager:ApplyTheme(themeData)
        assert(self.Library, 'Must set ThemeManager.Library')

        local Theme = themeData
        if type(themeData) == 'string' then
            local ok, loaded = self:ReadThemeFile(themeData)
            if not ok then return false, loaded end
            Theme = loaded
        end

        for _, key in next, self.ThemeKeys do
            local c = Theme[key]
            if typeof(c) == 'Color3' then
                self.Library[key] = c
            end
        end

        self.Library.AccentColorDark = self.Library:GetDarkerColor(self.Library.AccentColor)
        self.Library:UpdateColorsUsingRegistry()
        return true
    end

    function ThemeManager:LoadTheme(name)
        local ok, err = self:ApplyTheme(name)
        if not ok then return false, err end
        self.CurrentTheme = name
        return true
    end

    function ThemeManager:GetTheme()
        local t = {}
        for _, key in next, self.ThemeKeys do
            t[key] = self.Library[key]
        end
        return t
    end

    function ThemeManager:GetCurrentThemeName()
        return self.CurrentTheme or 'Default'
    end

    function ThemeManager:IsBuiltIn(name)
        return table.find(self.BuiltInOrder, name) ~= nil
    end

    ------------------------------------------------------------------
    -- Theme list (built-ins in order, then customs alphabetically)
    ------------------------------------------------------------------
    function ThemeManager:RefreshThemeList()
        local out = {}
        local seen = {}

        -- built-ins first, only if the file actually exists
        for _, name in next, self.BuiltInOrder do
            if isfile(self:ThemePath(name)) then
                table.insert(out, name)
                seen[name] = true
            end
        end

        -- then any other .json in themes/, alphabetically
        local list = listfiles(self.Folder .. '/themes')
        local custom = {}
        for i = 1, #list do
            local file = list[i]
            if file:sub(-5) == '.json' then
                local pos = file:find('.json', 1, true)
                local start = pos
                local char = file:sub(pos, pos)
                while char ~= '/' and char ~= '\\' and char ~= '' do
                    pos = pos - 1
                    char = file:sub(pos, pos)
                end
                if char == '/' or char == '\\' then
                    local name = file:sub(pos + 1, start - 1)
                    if not seen[name] then
                        table.insert(custom, name)
                    end
                end
            end
        end
        table.sort(custom, function(a, b) return a < b end)
        for _, name in next, custom do
            table.insert(out, name)
        end

        return out
    end

    ------------------------------------------------------------------
    -- Library hooks
    ------------------------------------------------------------------
    function ThemeManager:SetLibrary(library)
        self.Library = library
    end

    function ThemeManager:SetIgnoreIndexes(list)
        for _, key in next, list do
            self.Ignore[key] = true
        end
    end

    ------------------------------------------------------------------
    -- UI
    ------------------------------------------------------------------
    function ThemeManager:BuildThemeSection(tab)
        assert(self.Library, 'Must set ThemeManager.Library')

        local section = tab:AddRightGroupbox('Theme')

        local initialList = self:RefreshThemeList()
        local initialValue = table.find(initialList, self.CurrentTheme) and self.CurrentTheme or initialList[1]

        section:AddDropdown('ThemeManager_ThemeList', {
            Text      = 'Theme',
            Values    = initialList,
            Default   = initialValue,
            AllowNull = false,
            Callback  = function(value)
                if not value then return end
                local ok, err = self:LoadTheme(value)
                if not ok then
                    self.Library:Notify('Failed to load theme: ' .. err)
                    return
                end
                if self.ThemeNameBox then
                    self.ThemeNameBox:SetValue(value)
                end
            end,
        })

        section:AddInput('ThemeManager_ThemeName', {
            Text        = 'Theme name',
            Placeholder = 'my theme',
            Default     = self.CurrentTheme,
        })
        self.ThemeNameBox = Options.ThemeManager_ThemeName

        section:AddDivider()

        section:AddButton('Save current theme', function()
            local name = Options.ThemeManager_ThemeName.Value
            local ok, err = self:SaveTheme(name)
            if not ok then
                return self.Library:Notify('Failed to save theme: ' .. err)
            end
            self.Library:Notify(string.format('Saved theme %q', name))

            self.CurrentTheme = name
            Options.ThemeManager_ThemeList:SetValues(self:RefreshThemeList())
            Options.ThemeManager_ThemeList:SetValue(name)
        end)

        section:AddButton('Load theme', function()
            local name = Options.ThemeManager_ThemeList.Value
            if not name then
                return self.Library:Notify('Pick a theme from the list first', 2)
            end
            local ok, err = self:LoadTheme(name)
            if not ok then
                return self.Library:Notify('Failed to load theme: ' .. err)
            end
            self.Library:Notify(string.format('Loaded theme %q', name))
        end)

        section:AddButton('Delete theme', function()
            local name = Options.ThemeManager_ThemeList.Value
            if not name then
                return self.Library:Notify('Pick a theme first', 2)
            end

            local ok, err = self:DeleteTheme(name)
            if not ok then
                return self.Library:Notify('Failed to delete theme: ' .. err)
            end
            self.Library:Notify(string.format('Deleted theme %q', name))

            Options.ThemeManager_ThemeList:SetValues(self:RefreshThemeList())
            Options.ThemeManager_ThemeList:SetValue(nil)

            -- reseed a built-in if the user deleted one
            self:SeedBuiltInThemes()
        end)

        section:AddButton('Refresh theme list', function()
            Options.ThemeManager_ThemeList:SetValues(self:RefreshThemeList())
            Options.ThemeManager_ThemeList:SetValue(self.CurrentTheme)
        end)

        section:AddButton('Reveal themes folder', function()
            -- best-effort; only works in executors that expose it
            if typeof(setclipboard) == 'function' then
                pcall(setclipboard, self.Folder .. '/themes/')
                self.Library:Notify('Themes folder path copied to clipboard', 3)
            end
        end)

        self:SetIgnoreIndexes({
            'ThemeManager_ThemeList',
            'ThemeManager_ThemeName',
        })

        -- apply default on open
        if self.CurrentTheme then
            self:ApplyTheme(self.CurrentTheme)
        end
    end

    ThemeManager:BuildFolderTree()
    ThemeManager:SeedBuiltInThemes()
end

return ThemeManager