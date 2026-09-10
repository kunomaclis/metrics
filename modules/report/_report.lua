Report = { }

require('modules.report.config')
require('modules.report.publishing')
require('modules.report.widgets')

Report.Name   = 'Report'
Report.Title  = 'Metrics - Reporting'
Report.Module = 'Report'
Report.File   = 'report'

Report.Section = { }

------------------------------------------------------------------------------------------------------
-- Initializes the Hub screen.
------------------------------------------------------------------------------------------------------
---@param settings? table settings that come from the Ashita settings_update event.
------------------------------------------------------------------------------------------------------
Report.Initialize = function(settings)
    -- Get saved settings from file.
    Report.Settings = settings or SettingsFile.load(Report.Config.Defaults, Report.File)

    -- Create the Overview Window.
    Report.Window = Window:New
    ({
        Name     = Report.Name,
        Title    = Report.Title,
        Module   = Report.Module,
        Settings = Report.Settings,
    })
end

------------------------------------------------------------------------------------------------------
-- Creates some buttons to publish various party metrics to chat.
------------------------------------------------------------------------------------------------------
Report.Content = function()
    Report.Widgets.SettingsButton()
    UI.Separator() Report.Section.ChatReports()
    UI.Separator() Report.Section.Export()
    UI.Separator() Report.Section.Import()
end

------------------------------------------------------------------------------------------------------
-- Builds the chat report section.
------------------------------------------------------------------------------------------------------
Report.Section.ChatReports = function()
    local colFlags = Column.Flags.None
    local width    = Column.Widths.Report
    local publish

    UI.Text('Chat Reports')
    Report.Widgets.ChatMode()

    if UI.BeginTable('Chat Reports', 4, WindowManager.Table.Flags.None) then
        UI.TableSetupColumn('Col 1', colFlags, width)
        UI.TableSetupColumn('Col 2', colFlags, width)
        UI.TableSetupColumn('Col 3', colFlags, width)
        UI.TableSetupColumn('Col 4', colFlags, width)

        UI.TableNextRow()
        UI.TableNextColumn() if UI.Button('Overall     ') then publish = true end
        UI.TableNextColumn()
        UI.TableNextColumn()
        UI.TableNextColumn()
        --
        UI.TableNextColumn() if UI.Button('Melee       ') then publish = DB.Trackable.MELEE_OVERALL end
        UI.TableNextColumn() if UI.Button('Weaponskills') then publish = DB.Trackable.WEAPONSKILL end
        UI.TableNextColumn() if UI.Button('Magic       ') then publish = DB.Trackable.SPELLS_OVERALL end
        UI.TableNextColumn() if UI.Button('Pet         ') then publish = DB.Trackable.PET_OVERALL end
        --
        UI.TableNextColumn() if UI.Button('Abilities   ') then publish = DB.Trackable.ABILITY_DAMAGING end
        UI.TableNextColumn() if UI.Button('Healing     ') then publish = DB.Trackable.ALL_HEAL end
        UI.TableNextColumn()
        UI.TableNextColumn()

        UI.EndTable()
    end

    if publish == true then
        Report.Publishing.Overall()
    elseif publish then
        Report.Publishing.DamageByType(publish)
    end
end

------------------------------------------------------------------------------------------------------
-- Builds the export section.
------------------------------------------------------------------------------------------------------
Report.Section.Export = function()
    local colFlags = Column.Flags.None
    local width    = Column.Widths.Report
    local saveAction
    UI.Text('Export Data')
    UI.Text('Files can be found in: /config/Metrics/')

    local blogLength = #Blog.Log
    if blogLength >= 50000 then
        UI.Text('NOTICE: There are ' .. tostring(blogLength) .. ' entries in the battle log.')
        UI.Text('        You may notice a stagger when saving it.')
    end

    if UI.BeginTable('Save File', 4, WindowManager.Table.Flags.None) then
        UI.TableSetupColumn('Col 1', colFlags, width)
        UI.TableSetupColumn('Col 2', colFlags, width)
        UI.TableSetupColumn('Col 3', colFlags, width)
        UI.TableSetupColumn('Col 4', colFlags, width)

        UI.TableNextRow()
        UI.TableNextColumn()
        if UI.Button('Database    ') then
            saveAction = File.SaveData
        end

        UI.TableNextColumn()
        if UI.Button('Battle Log  ') then
            saveAction = File.SaveBattlelog
        end

        UI.TableNextColumn()
        if UI.Button('Loot        ') then
            saveAction = File.SaveLoot
        end

        UI.EndTable()
    end

    if saveAction then
        saveAction()
    end
end

------------------------------------------------------------------------------------------------------
-- Builds the import section.
------------------------------------------------------------------------------------------------------
Report.Section.Import = function()
    Import             = { }
    Import.DialogTitle = 'Import CSV'
    Import.Selected    = nil

    UI.Text('Import Data')
    UI.Text('Database files from /config/Metrics/')

    if UI.Button('Import') then
        UI.OpenPopup(Import.DialogTitle)
    end

    UI.Separator()

    if UI.BeginPopup(Import.DialogTitle) then
        UI.BeginChild('File List', { 420, 240 })

        local directory = tostring(AshitaCore:GetInstallPath()) .. 'config\\Metrics'
        local p = io.popen('dir /b /a:-d "' .. directory .. '"')

        if p then
            for line in p:lines() do
                if line:lower():find('database', 1, true) then
                    local name = line
                    local is_sel = (Import.Selected == name)

                    if UI.Selectable(name, is_sel) then
                        Import.Selected = name
                    end

                    if UI.IsItemHovered() and UI.IsMouseDoubleClicked(0) then
                        Import.Selected = name
                        Ashita.Chat.Echo(('Importing: %s'):format(Import.Selected))
                        File.Import(string.format('%s\\%s', directory, name))
                        UI.CloseCurrentPopup()
                    end
                end
            end
            p:close()
        end
        UI.EndChild()

        UI.Separator()
        if UI.Button('Cancel') then
            UI.CloseCurrentPopup()
        end

        UI.EndPopup()
    end
end
