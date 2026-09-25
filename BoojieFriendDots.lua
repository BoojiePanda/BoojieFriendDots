local ADDON_NAME = ...
local TITLE = "Boojie Friend Dots"
local VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "0.3.9"
local DOT_TEXTURE = "Interface\\AddOns\\BoojieFriendDots\\BoojieFriendDotsMarker.tga"
local ADDON_ICON_TEXTURE = "Interface\\AddOns\\BoojieFriendDots\\BoojieFriendDotsBFDIcon.png"
local LDB_NAME = "BoojieFriendDots"
local PINK_HEX = "FFFF8DA1"
local PINK_R, PINK_G, PINK_B = 1, 0.553, 0.631
local UPDATE_INTERVAL = 0.10
local MIN_DOT_SIZE = 4
local MAX_DOT_SIZE = 40

local function GetMetadata(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(ADDON_NAME, field)
    end
    if GetAddOnMetadata then
        return GetAddOnMetadata(ADDON_NAME, field)
    end
end

local defaults = {
    useClassColors = true,
    color = { r = 0.20, g = 0.85, b = 1.00 },
    size = 14,
    chatWindow = "General",
    showMinimapButton = true,
    minimap = { minimapPos = 225 },
    settingsPosition = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    },
}

local db
local wowSnapshot = {}
local bnetSnapshot = {}
local recentNotices = {}
local minimapDots = {}
local worldMapDots = {}
local settingsFrame
local ldbIcon
local sizeSlider
local sizeEditBox
local chatEditBox
local colorSwatch

local function CopyDefaults()
    BoojieFriendDotsDB = BoojieFriendDotsDB or {}
    BoojieFriendDotsDB.color = BoojieFriendDotsDB.color or {}

    if BoojieFriendDotsDB.useClassColors == nil then
        BoojieFriendDotsDB.useClassColors = defaults.useClassColors
    end
    if type(BoojieFriendDotsDB.color.r) ~= "number" then
        BoojieFriendDotsDB.color.r = defaults.color.r
    end
    if type(BoojieFriendDotsDB.color.g) ~= "number" then
        BoojieFriendDotsDB.color.g = defaults.color.g
    end
    if type(BoojieFriendDotsDB.color.b) ~= "number" then
        BoojieFriendDotsDB.color.b = defaults.color.b
    end
    if type(BoojieFriendDotsDB.size) ~= "number" then
        BoojieFriendDotsDB.size = defaults.size
    end
    if type(BoojieFriendDotsDB.chatWindow) ~= "string" or BoojieFriendDotsDB.chatWindow == "" then
        BoojieFriendDotsDB.chatWindow = defaults.chatWindow
    end
    if BoojieFriendDotsDB.showMinimapButton == nil then
        BoojieFriendDotsDB.showMinimapButton = defaults.showMinimapButton
    end
    if type(BoojieFriendDotsDB.minimap) ~= "table" then
        BoojieFriendDotsDB.minimap = {
            minimapPos = tonumber(BoojieFriendDotsDB.minimapAngle) or defaults.minimap.minimapPos,
        }
    end
    if type(BoojieFriendDotsDB.minimap.minimapPos) ~= "number" then
        BoojieFriendDotsDB.minimap.minimapPos = defaults.minimap.minimapPos
    end
    BoojieFriendDotsDB.minimapAngle = nil

    BoojieFriendDotsDB.settingsPosition = BoojieFriendDotsDB.settingsPosition or {}
    local position = BoojieFriendDotsDB.settingsPosition
    if type(position.point) ~= "string" then
        position.point = defaults.settingsPosition.point
    end
    if type(position.relativePoint) ~= "string" then
        position.relativePoint = defaults.settingsPosition.relativePoint
    end
    if type(position.x) ~= "number" then
        position.x = defaults.settingsPosition.x
    end
    if type(position.y) ~= "number" then
        position.y = defaults.settingsPosition.y
    end

    BoojieFriendDotsDB.size = math.max(MIN_DOT_SIZE, math.min(MAX_DOT_SIZE, math.floor(BoojieFriendDotsDB.size + 0.5)))
    db = BoojieFriendDotsDB
end

local function Trim(text)
    return strtrim(text or "")
end

local function FindChatFrame(name)
    local wanted = Trim(name):lower()
    if wanted == "" then
        wanted = "general"
    end

    for i = 1, NUM_CHAT_WINDOWS do
        local windowName = GetChatWindowInfo(i)
        local normalized = Trim(windowName):lower()
        if i == 1 and normalized == "" then
            normalized = "general"
        end
        if normalized == wanted then
            return _G["ChatFrame" .. i]
        end
    end
end

local function AddChatMessage(text)
    local frame = FindChatFrame(db.chatWindow)
    if not frame then
        frame = ChatFrame1
        frame:AddMessage('|cff66ccffBoojieFriendDots:|r Chat window "' .. db.chatWindow .. '" was not found. Using General.')
    end
    frame:AddMessage("|cff66ccffBoojieFriendDots:|r " .. text)
end

local function GetClassToken(className)
    className = Trim(className)
    if className == "" then
        return nil
    end

    for classToken, localizedName in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
        if localizedName == className then
            return classToken
        end
    end
    for classToken, localizedName in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
        if localizedName == className then
            return classToken
        end
    end
end

local function ColorizeName(name, classToken)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local color = classToken and colors and colors[classToken]
    if not color then
        return name
    end

    local colorCode = color.colorStr
    if not colorCode then
        colorCode = string.format(
            "ff%02x%02x%02x",
            math.floor(color.r * 255 + 0.5),
            math.floor(color.g * 255 + 0.5),
            math.floor(color.b * 255 + 0.5)
        )
    end
    return "|c" .. colorCode .. name .. "|r"
end

local function SendNotice(name, online, classToken)
    name = Trim(name)
    name = name ~= "" and Ambiguate(name, "short") or "Unknown friend"
    local key = name:lower() .. (online and ":1" or ":0")
    local now = GetTime()
    local previous = recentNotices[key]
    if previous and now - previous < 2 then
        return
    end
    recentNotices[key] = now
    AddChatMessage(ColorizeName(name, classToken) .. (online and " logged in." or " logged out."))
end

local function IsFriendUnit(unit)
    local guid = UnitGUID(unit)
    if not guid then
        return false
    end

    if C_FriendList.IsFriend(guid) then
        return true
    end

    local accountInfo = C_BattleNet.GetAccountInfoByGUID(guid)
    return accountInfo and accountInfo.isFriend or false
end

local function GetDotColor(unit)
    if db.useClassColors then
        local _, class = UnitClass(unit or "player")
        local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
        local color = class and colors and colors[class]
        if color then
            return color.r, color.g, color.b
        end
    end
    return db.color.r, db.color.g, db.color.b
end

local function CreateDot(parent)
    local dot = CreateFrame("Frame", nil, parent)
    dot:SetSize(db.size, db.size)
    dot:SetFrameLevel(parent:GetFrameLevel() + 10)
    dot:EnableMouse(false)

    local texture = dot:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetTexture(DOT_TEXTURE)
    dot.texture = texture

    return dot
end

local function StyleDot(dot, unit, size)
    local r, g, b = GetDotColor(unit)
    dot:SetSize(size or db.size, size or db.size)
    dot.texture:SetVertexColor(r, g, b, 1)
end

local function HideDots(dots, fromIndex)
    for i = fromIndex, #dots do
        dots[i]:Hide()
    end
end

local function PositionMinimapDot(dot, unit, playerY, playerX, playerInstance, radius, halfWidth, halfHeight, rotate, facing)
    local unitY, unitX, _, unitInstance = UnitPosition(unit)
    if not unitY or not unitX or unitInstance ~= playerInstance then
        return false
    end

    local xDist = playerX - unitX
    local yDist = playerY - unitY

    if rotate and facing then
        local sinFacing = math.sin(facing)
        local cosFacing = math.cos(facing)
        local x = xDist * cosFacing - yDist * sinFacing
        local y = xDist * sinFacing + yDist * cosFacing
        xDist, yDist = x, y
    end

    local dx = xDist / radius
    local dy = yDist / radius
    local edge = 0.92
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"

    if shape == "ROUND" then
        if dx * dx + dy * dy > edge * edge then
            return false
        end
    elseif math.abs(dx) > edge or math.abs(dy) > edge then
        return false
    end

    dot:ClearAllPoints()
    dot:SetPoint("CENTER", Minimap, "CENTER", dx * halfWidth, -dy * halfHeight)
    StyleDot(dot, unit)
    dot:Show()
    return true
end

local function UpdateMinimapDots()
    local active = 0

    if IsInGroup() then
        local playerY, playerX, _, playerInstance = UnitPosition("player")
        local radius = C_Minimap.GetViewRadius()

        if playerY and playerX and playerInstance and radius and radius > 0 then
            local halfWidth = Minimap:GetWidth() * 0.5
            local halfHeight = Minimap:GetHeight() * 0.5
            local rotate = GetCVarBool("rotateMinimap")
            local facing = rotate and GetPlayerFacing() or nil

            local function TryUnit(unit)
                if UnitExists(unit) and not UnitIsUnit(unit, "player") and IsFriendUnit(unit) then
                    local dot = minimapDots[active + 1]
                    if not dot then
                        dot = CreateDot(Minimap)
                        minimapDots[active + 1] = dot
                    end
                    if PositionMinimapDot(dot, unit, playerY, playerX, playerInstance, radius, halfWidth, halfHeight, rotate, facing) then
                        active = active + 1
                    end
                end
            end

            if IsInRaid() then
                for i = 1, GetNumGroupMembers() do
                    TryUnit("raid" .. i)
                end
            else
                for i = 1, GetNumSubgroupMembers() do
                    TryUnit("party" .. i)
                end
            end
        end
    end


    HideDots(minimapDots, active + 1)
end

local function PositionWorldMapDot(dot, canvas, x, y, unit)
    local canvasScale = WorldMapFrame:GetCanvasScale()
    if not canvasScale or canvasScale <= 0 then
        canvasScale = 1
    end

    dot:SetParent(canvas)
    dot:SetFrameLevel(canvas:GetFrameLevel() + 100)
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * x, -canvas:GetHeight() * y)
    StyleDot(dot, unit, db.size / canvasScale)
    dot:Show()
end

local function UpdateWorldMapDots()
    local active = 0

    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        HideDots(worldMapDots, 1)
        return
    end

    local mapID = WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame:GetCanvas()
    if not mapID or not canvas then
        HideDots(worldMapDots, 1)
        return
    end

    local function TryUnit(unit)
        if UnitExists(unit) and not UnitIsUnit(unit, "player") and IsFriendUnit(unit) then
            local position = C_Map.GetPlayerMapPosition(mapID, unit)
            if position then
                local x, y = position:GetXY()
                if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    local dot = worldMapDots[active + 1]
                    if not dot then
                        dot = CreateDot(canvas)
                        worldMapDots[active + 1] = dot
                    end
                    active = active + 1
                    PositionWorldMapDot(dot, canvas, x, y, unit)
                end
            end
        end
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            TryUnit("raid" .. i)
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            TryUnit("party" .. i)
        end
    end


    HideDots(worldMapDots, active + 1)
end

local function RefreshDots()
    UpdateMinimapDots()
    UpdateWorldMapDots()
end

local function BuildWoWSnapshot()
    local snapshot = {}
    for i = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name then
            snapshot[info.name] = {
                online = info.connected and true or false,
                classToken = GetClassToken(info.className),
            }
        end
    end
    return snapshot
end

local function UpdateWoWFriends(notify)
    local newSnapshot = BuildWoWSnapshot()

    if notify then
        for name, state in pairs(newSnapshot) do
            local old = wowSnapshot[name]
            if old and old.online ~= state.online then
                SendNotice(name, state.online, state.classToken or old.classToken)
            end
        end
    end

    wowSnapshot = newSnapshot
end

local function BuildBNetSnapshot()
    local snapshot = {}
    local friendCount = BNGetNumFriends()

    for friendIndex = 1, friendCount do
        local account = C_BattleNet.GetFriendAccountInfo(friendIndex)
        if account and account.bnetAccountID then
            local games = {}
            local gameCount = C_BattleNet.GetFriendNumGameAccounts(friendIndex)

            for gameIndex = 1, gameCount do
                local game = C_BattleNet.GetFriendGameAccountInfo(friendIndex, gameIndex)
                if game and game.isOnline and not game.isAppearOffline then
                    local key = tostring(game.gameAccountID or game.playerGuid or gameIndex)
                    local characterName = Trim(game.characterName)
                    local accountName = Trim(account.accountName)
                    local battleTag = Trim(account.battleTag)
                    local isWoW = game.clientProgram == BNET_CLIENT_WOW
                    local displayName
                    if isWoW then
                        displayName = characterName ~= "" and characterName or accountName
                    else
                        displayName = battleTag ~= "" and battleTag or accountName
                    end
                    if displayName == "" then
                        displayName = battleTag ~= "" and battleTag or "Unknown Battle.net friend"
                    end
                    games[key] = {
                        name = displayName,
                        classToken = isWoW and GetClassToken(game.className) or nil,
                    }
                end
            end

            snapshot[tostring(account.bnetAccountID)] = games
        end
    end

    return snapshot
end

local function UpdateBNetFriends(notify)
    local newSnapshot = BuildBNetSnapshot()

    if notify then
        for accountID, newGames in pairs(newSnapshot) do
            local oldGames = bnetSnapshot[accountID]
            if oldGames then
                for gameID, oldGame in pairs(oldGames) do
                    if not newGames[gameID] then
                        SendNotice(oldGame.name, false, oldGame.classToken)
                    end
                end
                for gameID, newGame in pairs(newGames) do
                    if not oldGames[gameID] then
                        SendNotice(newGame.name, true, newGame.classToken)
                    elseif oldGames[gameID].name ~= newGame.name then
                        SendNotice(oldGames[gameID].name, false, oldGames[gameID].classToken)
                        SendNotice(newGame.name, true, newGame.classToken)
                    end
                end
            end
        end
    end

    bnetSnapshot = newSnapshot
end

local function SetCustomColor(r, g, b)
    db.color.r, db.color.g, db.color.b = r, g, b
    if colorSwatch then
        colorSwatch:SetColorTexture(r, g, b, 1)
    end
    RefreshDots()
end

local function OpenColorPicker()
    local oldR, oldG, oldB = db.color.r, db.color.g, db.color.b
    local options = {
        r = oldR,
        g = oldG,
        b = oldB,
        hasOpacity = false,
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            SetCustomColor(r, g, b)
        end,
        cancelFunc = function()
            SetCustomColor(oldR, oldG, oldB)
        end,
    }
    ColorPickerFrame:SetupColorPickerAndShow(options)
end

local function SetDotSize(value, source)
    value = tonumber(value)
    if not value then
        return
    end

    value = math.max(MIN_DOT_SIZE, math.min(MAX_DOT_SIZE, math.floor(value + 0.5)))
    db.size = value

    if sizeSlider and source ~= sizeSlider then
        sizeSlider:SetValue(value)
    end
    if sizeEditBox and source ~= sizeEditBox then
        sizeEditBox:SetText(value)
    end
    RefreshDots()
end


local function SaveChatWindow()
    local value = Trim(chatEditBox:GetText())
    if value == "" then
        value = defaults.chatWindow
    end
    db.chatWindow = value
    chatEditBox:SetText(value)
end

local function CreateLabel(parent, text, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetTextColor(PINK_R, PINK_G, PINK_B)
    label:SetText(text)
    return label
end

local BACKDROP = {
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function ApplyBackdrop(frame, alpha)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, alpha or 1)
    frame:SetBackdropBorderColor(PINK_R, PINK_G, PINK_B, 1)
end

local function SkinButton(button)
    ApplyBackdrop(button, 1)
    button:SetNormalFontObject("GameFontHighlight")
    button:SetHighlightTexture("Interface/Buttons/WHITE8X8")
    button:GetHighlightTexture():SetVertexColor(PINK_R, PINK_G, PINK_B, 0.22)
    button:SetPushedTexture("Interface/Buttons/WHITE8X8")
    button:GetPushedTexture():SetVertexColor(PINK_R, PINK_G, PINK_B, 0.35)
end

local function SkinEditBox(editBox)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetTextInsets(8, 8, 0, 0)
    ApplyBackdrop(editBox, 1)
end

local function SaveSettingsPosition()
    if not settingsFrame then
        return
    end

    local point, _, relativePoint, x, y = settingsFrame:GetPoint(1)
    if point then
        db.settingsPosition.point = point
        db.settingsPosition.relativePoint = relativePoint or point
        db.settingsPosition.x = math.floor((x or 0) + 0.5)
        db.settingsPosition.y = math.floor((y or 0) + 0.5)
    end
end

local function UpdateMinimapButtonVisibility()
    if not ldbIcon or not db then
        return
    end

    db.minimap.hide = not db.showMinimapButton
    if db.showMinimapButton then
        ldbIcon:Show(LDB_NAME)
    else
        ldbIcon:Hide(LDB_NAME)
    end
end

local function CreateSettingsFrame()
    local frame = CreateFrame("Frame", "BoojieFriendDotsSettingsFrame", UIParent, "BackdropTemplate")
    UISpecialFrames[#UISpecialFrames + 1] = "BoojieFriendDotsSettingsFrame"
    frame:SetSize(430, 350)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnShow", function(self)
        self:Raise()
    end)
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveSettingsPosition()
    end)
    ApplyBackdrop(frame, 0.98)

    frame:ClearAllPoints()
    frame:SetPoint(
        db.settingsPosition.point,
        UIParent,
        db.settingsPosition.relativePoint,
        db.settingsPosition.x,
        db.settingsPosition.y
    )

    frame:Hide()
    settingsFrame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -17)
    title:SetText("|c" .. PINK_HEX .. TITLE .. "|r  |cffaaaaaav" .. VERSION .. "|r")

    local closeButton = CreateFrame("Button", nil, frame, "BackdropTemplate")
    closeButton:SetSize(24, 24)
    closeButton:SetPoint("TOPRIGHT", -10, -10)
    closeButton:SetText("X")
    SkinButton(closeButton)
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    local commandLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    commandLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
    commandLabel:SetText("Open this window: |c" .. PINK_HEX .. "/bfd|r")

    local classCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    classCheck:SetPoint("TOPLEFT", 14, -73)
    classCheck:SetChecked(db.useClassColors)
    local classLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    classLabel:SetPoint("LEFT", classCheck, "RIGHT", 3, 0)
    classLabel:SetText("Use class colors")
    classCheck:SetScript("OnClick", function(self)
        db.useClassColors = self:GetChecked() and true or false
        RefreshDots()
    end)

    CreateLabel(frame, "Custom color", 22, -112)
    local colorButton = CreateFrame("Button", nil, frame, "BackdropTemplate")
    colorButton:SetSize(28, 22)
    colorButton:SetPoint("TOPLEFT", 126, -105)
    ApplyBackdrop(colorButton, 1)
    local swatch = colorButton:CreateTexture(nil, "ARTWORK")
    swatch:SetAllPoints()
    swatch:SetColorTexture(db.color.r, db.color.g, db.color.b, 1)
    colorButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    colorButton:SetScript("OnClick", OpenColorPicker)
    colorSwatch = swatch

    CreateLabel(frame, "Dot size", 22, -152)
    local slider = CreateFrame("Slider", "BoojieFriendDotsSizeSlider", frame, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 88, -146)
    slider:SetWidth(220)
    slider:SetMinMaxValues(MIN_DOT_SIZE, MAX_DOT_SIZE)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(db.size)
    _G[slider:GetName() .. "Low"]:SetText(MIN_DOT_SIZE)
    _G[slider:GetName() .. "High"]:SetText(MAX_DOT_SIZE)
    _G[slider:GetName() .. "Text"]:SetText("")
    slider:SetScript("OnValueChanged", function(self, value)
        SetDotSize(value, self)
    end)
    sizeSlider = slider

    local sizeBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    sizeBox:SetSize(48, 24)
    sizeBox:SetPoint("LEFT", slider, "RIGHT", 18, 0)
    sizeBox:SetAutoFocus(false)
    sizeBox:SetNumeric(true)
    sizeBox:SetMaxLetters(2)
    sizeBox:SetJustifyH("CENTER")
    SkinEditBox(sizeBox)
    sizeBox:SetText(db.size)
    sizeBox:SetScript("OnEnterPressed", function(self)
        SetDotSize(self:GetText(), self)
        self:SetText(db.size)
        self:ClearFocus()
    end)
    sizeBox:SetScript("OnEditFocusLost", function(self)
        SetDotSize(self:GetText(), self)
        self:SetText(db.size)
    end)
    sizeEditBox = sizeBox

    CreateLabel(frame, "Notification chat window", 22, -205)
    local chatBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    chatBox:SetSize(220, 24)
    chatBox:SetPoint("TOPLEFT", 190, -197)
    chatBox:SetAutoFocus(false)
    chatBox:SetMaxLetters(30)
    SkinEditBox(chatBox)
    chatBox:SetText(db.chatWindow)
    chatBox:SetScript("OnEnterPressed", function(self)
        SaveChatWindow()
        self:ClearFocus()
    end)
    chatBox:SetScript("OnEditFocusLost", SaveChatWindow)
    chatEditBox = chatBox

    local minimapCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    minimapCheck:SetPoint("TOPLEFT", 14, -246)
    minimapCheck:SetChecked(db.showMinimapButton)
    local minimapLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    minimapLabel:SetPoint("LEFT", minimapCheck, "RIGHT", 3, 0)
    minimapLabel:SetText("Show minimap icon")
    minimapCheck:SetScript("OnClick", function(self)
        db.showMinimapButton = self:GetChecked() and true or false
        UpdateMinimapButtonVisibility()
    end)

    local help = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 22, -294)
    help:SetText("Friends appear as dots on your minimap and world map while grouped.")
end

local function ShowSettings()
    if not settingsFrame then
        CreateSettingsFrame()
    end
    settingsFrame:Show()
end

local function ToggleSettings()
    if not settingsFrame then
        CreateSettingsFrame()
    end

    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        settingsFrame:Show()
    end
end

local function RegisterBlizzardSettings()
    if not Settings or not Settings.RegisterCanvasLayoutCategory or not Settings.RegisterAddOnCategory then
        return
    end

    local panel = CreateFrame("Frame")

    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(128, 128)
    icon:SetPoint("TOP", 0, -28)
    icon:SetTexture(ADDON_ICON_TEXTURE)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -12)
    title:SetText("|c" .. PINK_HEX .. TITLE .. "|r  |cffaaaaaav" .. VERSION .. "|r")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    description:SetPoint("TOP", title, "BOTTOM", 0, -10)
    description:SetText("Open Boojie Friend Dots from any chat window with /boojiefrienddots.")

    local button = CreateFrame("Button", nil, panel, "BackdropTemplate")
    button:SetSize(190, 26)
    button:SetPoint("TOP", description, "BOTTOM", 0, -16)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    button:SetBackdropColor(0.055, 0.055, 0.065, 0.96)
    button:SetBackdropBorderColor(PINK_R, PINK_G, PINK_B, 1)
    local buttonText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buttonText:SetPoint("CENTER")
    buttonText:SetText("Open Boojie Friend Dots")
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.10, 0.10, 0.12, 1)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.055, 0.055, 0.065, 0.96)
    end)
    button:SetScript("OnClick", ShowSettings)

    local addonDescription = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    addonDescription:SetPoint("TOP", button, "BOTTOM", 0, -24)
    addonDescription:SetWidth(420)
    addonDescription:SetJustifyH("CENTER")
    addonDescription:SetText(GetMetadata("Notes") or "")

    local author = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    author:SetPoint("BOTTOM", 0, 24)
    author:SetText("by " .. (GetMetadata("Author") or "SilverRavyn"))

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Boojie Friend Dots")
    Settings.RegisterAddOnCategory(category)
end

local function CreateMinimapButton()
    ldbIcon = LibStub("LibDBIcon-1.0")
    local launcher = LibStub("LibDataBroker-1.1"):NewDataObject(LDB_NAME, {
        type = "launcher",
        label = TITLE,
        text = TITLE,
        icon = ADDON_ICON_TEXTURE,
        OnClick = ToggleSettings,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(TITLE, PINK_R, PINK_G, PINK_B)
            tooltip:AddLine("Click to open or close.", 1, 1, 1)
        end,
    })

    db.minimap.hide = not db.showMinimapButton
    ldbIcon:Register(LDB_NAME, launcher, db.minimap)
end

SLASH_BOOJIEFRIENDDOTS1 = "/boojiefrienddots"
SLASH_BOOJIEFRIENDDOTS2 = "/bfd"
SlashCmdList.BOOJIEFRIENDDOTS = ShowSettings

SLASH_BOOJIERELOAD1 = SLASH_BOOJIERELOAD1 or "/rl"
SlashCmdList.BOOJIERELOAD = SlashCmdList.BOOJIERELOAD or ReloadUI

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("FRIENDLIST_UPDATE")
eventFrame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
eventFrame:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
eventFrame:RegisterEvent("BN_FRIEND_ACCOUNT_OFFLINE")
eventFrame:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

local elapsed = 0
local function DotUpdate(_, delta)
    if not db then return end
    elapsed = elapsed + delta
    if elapsed >= UPDATE_INTERVAL then
        elapsed = 0
        RefreshDots()
    end
end

local function UpdatePolling()
    if not db then return end
    elapsed = 0
    eventFrame:SetScript("OnUpdate", IsInGroup() and DotUpdate or nil)
    if not IsInGroup() then RefreshDots() end
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            CopyDefaults()
            eventFrame:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        if not db then
            CopyDefaults()
        end
        wowSnapshot = BuildWoWSnapshot()
        bnetSnapshot = BuildBNetSnapshot()
        CreateMinimapButton()
        RegisterBlizzardSettings()
        UpdatePolling()
    elseif event == "GROUP_ROSTER_UPDATE" then
        UpdatePolling()
    elseif event == "FRIENDLIST_UPDATE" then
        UpdateWoWFriends(true)
    elseif event == "BN_FRIEND_LIST_SIZE_CHANGED" then
        UpdateBNetFriends(false)
    else
        UpdateBNetFriends(true)
    end
end)
