script_name("Tmarket")
script_author("legacy.")
script_version("1.1")

local ffi = require("ffi")
local encoding = require("encoding")
local requests = require("requests")
local dlstatus = require("moonloader").download_status
local iconv = require("iconv")
local imgui = require("mimgui")
encoding.default = "CP1251"
local u8 = encoding.UTF8

-- Общие переменные
local configPath = getWorkingDirectory() .. "\\config\\market_price.ini"
local updateURL = "https://raw.githubusercontent.com/legacy-Chay/Tmarket/refs/heads/main/update.json"
local configURL, cachedNick = nil, nil
local window = imgui.new.bool(false)
local search = ffi.new("char[128]", "")
local items = {}

-- Утилиты
local function utf8ToCp1251(str)
    return iconv.new("WINDOWS-1251", "UTF-8"):iconv(str)
end
local function decode(buf) return u8:decode(ffi.string(buf)) end

-- Работа с файлами
local function loadData()
    items = {}
    local f = io.open(configPath, "r")
    if not f then return end
    while true do
        local name, buy, sell = f:read("*l"), f:read("*l"), f:read("*l")
        if not (name and buy and sell) then break end
        table.insert(items, {
            name = name,
            buy = buy,
            sell = sell,
            name_buf = ffi.new("char[128]", u8(name)),
            buy_buf = ffi.new("char[32]", u8(buy)),
            sell_buf = ffi.new("char[32]", u8(sell))
        })
    end
    f:close()
end

local function saveData()
    local f = io.open(configPath, "w")
    if f then
        for _, v in ipairs(items) do
            f:write(("%s\n%s\n%s\n"):format(v.name, v.buy, v.sell))
        end
        f:close()
    end
end

-- Проверка ника и обновление
local function checkNick(nick)
    local response = requests.get(updateURL)
    if response.status_code == 200 then
        local j = decodeJson(response.text)
        configURL = j.config_url or nil

        if configURL and j.nicknames and type(j.nicknames) == "table" then
            for _, n in ipairs(j.nicknames) do
                if nick == n then
                    if thisScript().version ~= j.last then
                        downloadUrlToFile(j.url, thisScript().path, function(_, status)
                            if status == dlstatus.STATUSEX_ENDDOWNLOAD then
                                local f = io.open(thisScript().path, "r")
                                local content = f:read("*a")
                                f:close()
                                local conv = utf8ToCp1251(content)
                                f = io.open(thisScript().path, "w")
                                f:write(conv)
                                f:close()
                                thisScript():reload()
                            end
                        end)
                    end
                    return true
                end
            end
        else
            sampAddChatMessage("{FF8C00}[Tmarket] {FFFFFF}Конфиг для вас {FF0000}не найден{FFFFFF}. Свяжитесь с {1E90FF}владельцем{FFFFFF} или {32CD32}приобретите Tmarket{FFFFFF}.", -1)
        end
    end
    return false
end

local function getNicknameSafe()
    local result, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if result and id >= 0 and id <= 1000 then
        return sampGetPlayerNickname(id)
    end
    return nil
end

local function downloadConfigFile(callback)
    if configURL then
        downloadUrlToFile(configURL, configPath, function(_, status)
            if status == dlstatus.STATUSEX_ENDDOWNLOAD and callback then
                local f = io.open(configPath, "r")
                if f then
                    local content = f:read("*a")
                    f:close()
                    local convertedContent = utf8ToCp1251(content)
                    f = io.open(configPath, "w")
                    f:write(convertedContent)
                    f:close()
                end
                callback()
            end
        end)
    end
end

-- Тема интерфейса
local function theme()
    local style, clr, col, ImVec4 = imgui.GetStyle(), imgui.Col, imgui.GetStyle().Colors, imgui.ImVec4
    style.WindowRounding = 4.0
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.84)
    style.ChildRounding = 2.0
    style.FrameRounding = 4.0
    style.ItemSpacing = imgui.ImVec2(10, 10)
    col[clr.Text] = ImVec4(0.95, 0.96, 0.98, 1)
    col[clr.WindowBg] = ImVec4(0.07, 0.11, 0.13, 1)
    col[clr.Button] = ImVec4(0.15, 0.20, 0.24, 1)
    col[clr.ButtonHovered] = ImVec4(0.20, 0.25, 0.29, 1)
    col[clr.ButtonActive] = col[clr.ButtonHovered]
end

imgui.OnInitialize(theme)

imgui.OnFrame(function()
    return window[0] and not (isPauseMenuActive() or isGamePaused() or sampIsDialogActive())
end, function()
    local resX, resY = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(900, 600), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))

    if not imgui.Begin(u8("legacy.-Tmarket — Таблица цен v1.3"), window) then
        imgui.End()
        return
    end

    imgui.InputTextWithHint("##search", u8("Поиск по товарам..."), search, ffi.sizeof(search))
    imgui.SameLine()
    if imgui.Button(u8("В разработке")) then
        sampAddChatMessage("{A47AFF}[Tmarket] {FFFFFF}Функция в разработке.", -1)
    end

    imgui.Separator()

    local contentWidth, contentHeight = imgui.GetContentRegionAvail().x, imgui.GetContentRegionAvail().y
    local filter = decode(search):lower()

    local filteredItems = {}
    for _, v in ipairs(items) do
        if filter == "" or v.name:lower():find(filter, 1, true) then
            table.insert(filteredItems, v)
        end
    end

    if #filteredItems > 0 then
        local colWidth = (contentWidth - 20) / 3
        imgui.BeginChild("##scroll_vertical", imgui.ImVec2(-1, contentHeight), true)

        local draw_list = imgui.GetWindowDrawList()
        local child_pos = imgui.GetCursorScreenPos()
        local style = imgui.GetStyle()
        local y0, y1 = child_pos.y - style.ItemSpacing.y, child_pos.y + contentHeight + imgui.GetScrollMaxY()
        local x0, x1 = child_pos.x + colWidth, child_pos.x + 2 * colWidth

        local separatorColor = imgui.GetColorU32(imgui.Col.Separator)
        draw_list:AddLine(imgui.ImVec2(x0, y0), imgui.ImVec2(x0, y1), separatorColor, 1)
        draw_list:AddLine(imgui.ImVec2(x1, y0), imgui.ImVec2(x1, y1), separatorColor, 1)

        imgui.Columns(3, nil, false)
        for _, header in ipairs({u8("Товар"), u8("Скупка"), u8("Продажа")}) do
            local textWidth = imgui.CalcTextSize(header).x
            imgui.SetCursorPosX(imgui.GetCursorPosX() + (colWidth - textWidth) / 2)
            imgui.Text(header)
            imgui.NextColumn()
        end
        imgui.Separator()

        local inputWidth = colWidth * 0.8
        for i, v in ipairs(filteredItems) do
            for idx, buf in ipairs({v.name_buf, v.buy_buf, v.sell_buf}) do
                imgui.SetCursorPosX(imgui.GetCursorPosX() + (colWidth - inputWidth) / 2)
                if imgui.InputText("##"..idx..i, buf, ffi.sizeof(buf)) then
                    if idx == 1 then v.name = decode(v.name_buf)
                    elseif idx == 2 then v.buy = decode(v.buy_buf)
                    else v.sell = decode(v.sell_buf) end
                end
                imgui.NextColumn()
            end
        end

        imgui.Columns(1)
        imgui.EndChild()
    else
        imgui.Text(u8("Товары не найдены"))
    end

    imgui.End()
end)

function main()
    repeat wait(0) until isSampAvailable()
    repeat
        cachedNick = getNicknameSafe()
        wait(500)
    until cachedNick ~= nil

    if checkNick(cachedNick) then
        downloadConfigFile(function()
            loadData()
            sampAddChatMessage("{4169E1}[Tmarket загружен]{FFFFFF}. Автор: {1E90FF}legacy{FFFFFF}", 0x00FF00)
            sampAddChatMessage("{A47AFF}[Tmarket] {FFFFFF}Открыть окно: {A47AFF}/tmarket", -1)
            sampRegisterChatCommand("tmarket", function() window[0] = not window[0] end)
        end)
    else
        sampAddChatMessage("{FF8C00}[Tmarket] {FFFFFF}У вас {FF0000}нет доступа{FFFFFF}. Приобретите {32CD32}Tmarket{FFFFFF} для использования.", -1)
    end

    while true do wait(500) end
end
