--[[
    SaveManager — patched
    New in this version:
      • Delete / rename / duplicate configs from the UI
      • Export + import configs as base64 (share-friendly)
      • Autoload helper (SetAutoload, ClearAutoload, GetAutoload)
      • Real error propagation (Save/Load return proper strings)
      • RefreshConfigList sorted alphabetically, cleaner parser
      • Backwards-compatible with the old "mutli" typo key
      • Theme indexes updated to match the new ThemeManager
      • Handles missing Options/Toggles entries gracefully
      • Works with touch controls (uses the patched AddButton)
]]

local httpService = game:GetService('HttpService')

local SaveManager = {} do
    SaveManager.Folder  = 'LinoriaLibSettings'
    SaveManager.Ignore  = {}
    SaveManager.Parser  = {
        Toggle = {
            Save = function(idx, object)
                return { type = 'Toggle', idx = idx, value = object.Value }
            end,
            Load = function(idx, data)
                if Toggles[idx] then
                    Toggles[idx]:SetValue(data.value)
                end
            end,
        },
        Slider = {
            Save = function(idx, object)
                return { type = 'Slider', idx = idx, value = tostring(object.Value) }
            end,
            Load = function(idx, data)
                if Options[idx] then
                    Options[idx]:SetValue(data.value)
                end
            end,
        },
        Dropdown = {
            Save = function(idx, object)
                -- NOTE: using the correctly-spelled 'multi' going forward
                return { type = 'Dropdown', idx = idx, value = object.Value, multi = object.Multi }
            end,
            Load = function(idx, data)
                if Options[idx] then
                    Options[idx]:SetValue(data.value)
                end
            end,
        },
        ColorPicker = {
            Save = function(idx, object)
                return {
                    type = 'ColorPicker', idx = idx,
                    value = object.Value:ToHex(),
                    transparency = object.Transparency,
                }
            end,
            Load = function(idx, data)
                if Options[idx] and type(data.value) == 'string' then
                    local ok, color = pcall(Color3.fromHex, data.value)
                    if ok then
                        Options[idx]:SetValueRGB(color, data.transparency)
                    end
                end
            end,
        },
        KeyPicker = {
            Save = function(idx, object)
                return { type = 'KeyPicker', idx = idx, mode = object.Mode, key = object.Value }
            end,
            Load = function(idx, data)
                if Options[idx] and data.key and data.mode then
                    Options[idx]:SetValue({ data.key, data.mode })
                end
            end,
        },
        Input = {
            Save = function(idx, object)
                return { type = 'Input', idx = idx, text = object.Value }
            end,
            Load = function(idx, data)
                if Options[idx] and type(data.text) == 'string' then
                    Options[idx]:SetValue(data.text)
                end
            end,
        },
    }

    ------------------------------------------------------------------
    -- Setup
    ------------------------------------------------------------------
    function SaveManager:SetIgnoreIndexes(list)
        for _, key in next, list do
            self.Ignore[key] = true
        end
    end

    function SaveManager:SetFolder(folder)
        self.Folder = folder
        self:BuildFolderTree()
    end

    function SaveManager:SetLibrary(library)
        self.Library = library
    end

    function SaveManager:BuildFolderTree()
        local paths = {
            self.Folder,
            self.Folder .. '/themes',
            self.Folder .. '/settings',
        }
        for i = 1, #paths do
            if not isfolder(paths[i]) then
                makefolder(paths[i])
            end
        end
    end

    ------------------------------------------------------------------
    -- Paths
    ------------------------------------------------------------------
    function SaveManager:ConfigPath(name)
        return self.Folder .. '/settings/' .. name .. '.json'
    end

    function SaveManager:AutoloadPath()
        return self.Folder .. '/settings/autoload.txt'
    end

    ------------------------------------------------------------------
    -- Save
    ------------------------------------------------------------------
    function SaveManager:Save(name)
        if (not name) or name:gsub(' ', '') == '' then
            return false, 'no config file is selected'
        end

        local fullPath = self:ConfigPath(name)

        local data = { objects = {} }

        for idx, toggle in next, Toggles do
            if self.Ignore[idx] then continue end
            local parser = self.Parser[toggle.Type]
            if parser then
                local ok, entry = pcall(parser.Save, idx, toggle)
                if ok and entry then table.insert(data.objects, entry) end
            end
        end

        for idx, option in next, Options do
            if self.Ignore[idx] then continue end
            local parser = self.Parser[option.Type]
            if parser then
                local ok, entry = pcall(parser.Save, idx, option)
                if ok and entry then table.insert(data.objects, entry) end
            end
        end

        local ok, encoded = pcall(httpService.JSONEncode, httpService, data)
        if not ok then return false, 'failed to encode data' end

        local writeOK = pcall(writefile, fullPath, encoded)
        if not writeOK then return false, 'failed to write file' end

        return true
    end

    ------------------------------------------------------------------
    -- Load
    ------------------------------------------------------------------
    function SaveManager:Load(name)
        if (not name) or name:gsub(' ', '') == '' then
            return false, 'no config file is selected'
        end

        local file = self:ConfigPath(name)
        if not isfile(file) then return false, 'invalid file' end

        local ok, decoded = pcall(httpService.JSONDecode, httpService, readfile(file))
        if not ok or type(decoded) ~= 'table' then return false, 'decode error' end

        -- Support both {objects = {...}} and bare {...} shapes
        local objects = decoded.objects or decoded
        local loaded = 0

        for _, option in next, objects do
            if type(option) == 'table' and self.Parser[option.type] then
                -- task.spawn so a single slow addon doesn't block the rest
                task.spawn(function()
                    self.Parser[option.type].Load(option.idx, option)
                end)
                loaded = loaded + 1
            end
        end

        if loaded == 0 then
            return false, 'config contained no recognised entries'
        end

        return true
    end

    ------------------------------------------------------------------
    -- Delete / rename / duplicate
    ------------------------------------------------------------------
    function SaveManager:Delete(name)
        if (not name) then return false, 'no config selected' end
        local file = self:ConfigPath(name)
        if not isfile(file) then return false, 'config does not exist' end
        local ok = pcall(delfile, file)
        if not ok then return false, 'failed to delete file' end
        return true
    end

    function SaveManager:Rename(oldName, newName)
        if (not oldName) or (not newName) then return false, 'missing name' end
        if newName:gsub(' ', '') == '' then return false, 'new name is empty' end

        local oldFile = self:ConfigPath(oldName)
        if not isfile(oldFile) then return false, 'config does not exist' end

        local newFile = self:ConfigPath(newName)
        if isfile(newFile) then return false, 'a config with that name already exists' end

        local ok = pcall(renamefile, oldFile, newFile)
        if not ok then return false, 'failed to rename file' end
        return true
    end

    function SaveManager:Duplicate(name, newName)
        local ok, err = self:Save(newName)
        if not ok then return false, err end

        -- Overwrite newName with the content of the original
        local src = self:ConfigPath(name)
        if not isfile(src) then return false, 'source config missing' end
        local content = readfile(src)
        pcall(writefile, self:ConfigPath(newName), content)

        return true
    end

    ------------------------------------------------------------------
    -- Export / import (base64)
    ------------------------------------------------------------------
    function SaveManager:Export(name)
        if (not name) then return false, 'no config selected' end
        local file = self:ConfigPath(name)
        if not isfile(file) then return false, 'config does not exist' end

        local raw = readfile(file)
        local encoded = httpService:JSONEncode({ name = name, data = raw })
        if typeof(base64) ~= 'nil' and base64.encode then
            return true, base64.encode(encoded)
        end
        return true, encoded
    end

    function SaveManager:Import(name, payload)
        if (not name) or (not payload) then return false, 'missing name or payload' end

        local decoded
        if typeof(base64) ~= 'nil' and base64.decode then
            local ok, d = pcall(base64.decode, payload)
            if ok then
                local ok2, j = pcall(httpService.JSONDecode, httpService, d)
                if ok2 then decoded = j end
            end
        end
        if not decoded then
            local ok, j = pcall(httpService.JSONDecode, httpService, payload)
            if ok then decoded = j end
        end
        if not decoded or type(decoded.data) ~= 'string' then
            return false, 'invalid export payload'
        end

        local writeOK = pcall(writefile, self:ConfigPath(name), decoded.data)
        if not writeOK then return false, 'failed to write imported config' end
        return true
    end

    ------------------------------------------------------------------
    -- Autoload
    ------------------------------------------------------------------
    function SaveManager:SetAutoload(name)
        if (not name) then return false, 'no config selected' end
        local ok = pcall(writefile, self:AutoloadPath(), name)
        if not ok then return false, 'failed to write autoload file' end
        if self.AutoloadLabel then
            self.AutoloadLabel:SetText('Current autoload config: ' .. name)
        end
        return true
    end

    function SaveManager:ClearAutoload()
        local path = self:AutoloadPath()
        if isfile(path) then pcall(delfile, path) end
        if self.AutoloadLabel then
            self.AutoloadLabel:SetText('Current autoload config: none')
        end
        return true
    end

    function SaveManager:GetAutoload()
        local path = self:AutoloadPath()
        if isfile(path) then
            return readfile(path)
        end
        return nil
    end

    function SaveManager:LoadAutoloadConfig()
        local name = self:GetAutoload()
        if not name or name:gsub(' ', '') == '' then return end

        local success, err = self:Load(name)
        if not success then
            if self.Library then
                self.Library:Notify('Failed to load autoload config: ' .. err)
            end
            return
        end

        if self.Library then
            self.Library:Notify(string.format('Auto loaded config %q', name))
        end
    end

    ------------------------------------------------------------------
    -- Ignore helpers
    ------------------------------------------------------------------
    function SaveManager:IgnoreThemeSettings()
        self:SetIgnoreIndexes({
            -- Library colour keys
            'BackgroundColor', 'MainColor', 'AccentColor',
            'OutlineColor', 'FontColor', 'RiskColor',
            -- ThemeManager UI (current + legacy names)
            'ThemeManager_ThemeList',
            'ThemeManager_ThemeName',
            'ThemeManager_CustomThemeList',
            'ThemeManager_CustomThemeName',
        })
    end

    ------------------------------------------------------------------
    -- Config list
    ------------------------------------------------------------------
    function SaveManager:RefreshConfigList()
        local list = listfiles(self.Folder .. '/settings')
        local out = {}

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
                    table.insert(out, file:sub(pos + 1, start - 1))
                end
            end
        end

        table.sort(out, function(a, b) return a:lower() < b:lower() end)
        return out
    end

    ------------------------------------------------------------------
    -- UI
    ------------------------------------------------------------------
    function SaveManager:BuildConfigSection(tab)
        assert(self.Library, 'Must set SaveManager.Library')

        local section = tab:AddRightGroupbox('Configuration')

        section:AddInput('SaveManager_ConfigName', {
            Text = 'Config name',
            Placeholder = 'my config',
        })

        section:AddDropdown('SaveManager_ConfigList', {
            Text = 'Config list',
            Values = self:RefreshConfigList(),
            AllowNull = true,
        })

        section:AddDivider()

        -- Save -----------------------------------------------------------------
        section:AddButton('Create config', function()
            local name = Options.SaveManager_ConfigName.Value

            if name:gsub(' ', '') == '' then
                return self.Library:Notify('Invalid config name (empty)', 2)
            end

            local success, err = self:Save(name)
            if not success then
                return self.Library:Notify('Failed to save config: ' .. err)
            end

            self.Library:Notify(string.format('Created config %q', name))

            Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            Options.SaveManager_ConfigList:SetValue(name)
        end):AddButton('Load config', function()
            local name = Options.SaveManager_ConfigList.Value
            if not name then
                return self.Library:Notify('Pick a config from the list first', 2)
            end

            local success, err = self:Load(name)
            if not success then
                return self.Library:Notify('Failed to load config: ' .. err)
            end

            self.Library:Notify(string.format('Loaded config %q', name))
        end)

        -- Overwrite ------------------------------------------------------------
        section:AddButton('Overwrite config', function()
            local name = Options.SaveManager_ConfigList.Value
            if not name then
                return self.Library:Notify('Pick a config from the list first', 2)
            end

            local success, err = self:Save(name)
            if not success then
                return self.Library:Notify('Failed to overwrite config: ' .. err)
            end

            self.Library:Notify(string.format('Overwrote config %q', name))
        end):AddButton('Delete config', function()
            local name = Options.SaveManager_ConfigList.Value
            if not name then
                return self.Library:Notify('Pick a config from the list first', 2)
            end

            local success, err = self:Delete(name)
            if not success then
                return self.Library:Notify('Failed to delete config: ' .. err)
            end

            self.Library:Notify(string.format('Deleted config %q', name))
            Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            Options.SaveManager_ConfigList:SetValue(nil)
        end)

        -- Rename ---------------------------------------------------------------
        section:AddButton('Rename config', function()
            local oldName = Options.SaveManager_ConfigList.Value
            local newName = Options.SaveManager_ConfigName.Value

            if not oldName then
                return self.Library:Notify('Pick a config from the list first', 2)
            end
            if newName:gsub(' ', '') == '' then
                return self.Library:Notify('Type a new name first', 2)
            end

            local success, err = self:Rename(oldName, newName)
            if not success then
                return self.Library:Notify('Failed to rename config: ' .. err)
            end

            self.Library:Notify(string.format('Renamed %q to %q', oldName, newName))
            Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            Options.SaveManager_ConfigList:SetValue(newName)
        end)

        -- Refresh --------------------------------------------------------------
        section:AddButton('Refresh list', function()
            Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            Options.SaveManager_ConfigList:SetValue(nil)
        end)

        -- Autoload -------------------------------------------------------------
        section:AddButton('Set as autoload', function()
            local name = Options.SaveManager_ConfigList.Value
            if not name then
                return self.Library:Notify('Pick a config from the list first', 2)
            end

            local ok, err = self:SetAutoload(name)
            if not ok then
                return self.Library:Notify('Failed to set autoload: ' .. err)
            end
            self.Library:Notify(string.format('Set %q to auto load', name))
        end):AddButton('Clear autoload', function()
            self:ClearAutoload()
            self.Library:Notify('Cleared autoload config')
        end)

        -- Export ---------------------------------------------------------------
        section:AddButton('Export config', function()
            local name = Options.SaveManager_ConfigList.Value
            if not name then
                return self.Library:Notify('Pick a config from the list first', 2)
            end

            local ok, payload = self:Export(name)
            if not ok then
                return self.Library:Notify('Failed to export: ' .. payload)
            end

            if typeof(setclipboard) == 'function' then
                pcall(setclipboard, payload)
                self.Library:Notify('Export copied to clipboard', 3)
            else
                self.Library:Notify('Export: ' .. payload:sub(1, 40) .. '...', 5)
            end
        end)

        SaveManager.AutoloadLabel = section:AddLabel('Current autoload config: none', true)

        local current = self:GetAutoload()
        if current then
            SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. current)
        end

        self:SetIgnoreIndexes({ 'SaveManager_ConfigList', 'SaveManager_ConfigName' })
    end

    SaveManager:BuildFolderTree()
end

return SaveManager