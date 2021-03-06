require "lib.moonloader"
require "lib.sampfuncs"
require "vkeys"

local settings = {
    ["sending_mode"] = "send",
    ["rtag"] = "[DHDD]",
    ["src_clist"] = 0x139BECaa,
    ["dst_clist"] = 14,
    ["disable_auto_givelicense"] = true
}

local bbdir = getGameDirectory().."//moonloader//brightbinder//"
local bbdid = 9898

local currentmenutitle = ""
local currentmenu = {}
local currentpid = -1
local currentpname = nil
local currentpscore = 0

local playerid = -1

function player_id()
    local tres, tped = getPlayerChar(PLAYER_HANDLE)
    if(not tres) then return -1 end
    local tres, tid = sampGetPlayerIdByCharHandle(tped)
    if(not tres) then return -1 end
    return tid
end

function substitute(s)
    -- 1. sub target
    if(s:find("%%id") ~= nil or s:find("%%name") ~= nil) then
        if(currentpid == -1) then
            return "$target_err"
        end
        s = s:gsub("%%id", tostring(currentpid))
        s = s:gsub("%%name", currentpname)
    end
    -- 2. sub self
    if(s:find("%%myid") ~= nil or s:find("%%myname") ~= nil) then
        s = s:gsub("%%myid", tostring(player_id()))
        s = s:gsub("%%myname", sampGetPlayerNickname(player_id()))
    end
    return s
end

-- a long schlong
function file_to_menu(fname)
    -- getting line iterator
    if(fname == nil) then
        fname = ""
    end
    local input = io.open(bbdir..fname..".txt", "r")
    if(input == nil) then
        return "Не удалось открыть файл "..fname..".txt."
    end

    -- loading the file
    local newmenu = {}
    local i = 1
    for l in input:lines() do
        -- verifying the file
        l = l:gsub("\t","")
        if(l:sub(1,1) == "$") then
            local cmd, args = l:match("^%$([%w_]*)%s*([%w_]*)$")
            if(cmd == nil) then
                return "Ошибка в строке "..tostring(i)..": неверный синтаксис команды (допускаются латиница, цифры и подчёркиание)."
            -- $wait
            elseif(cmd == "wait") then
                local tmp = tonumber(args)
                if(tmp == nil) then
                    return "Ошибка в строке "..tostring(i)..": ожидалось целое число."
                elseif(tmp < 0 or tmp > 10000) then
                    return "Ошибка в строке "..tostring(i)..": длительность должна быть между 0 и 10000."
                end
            -- $showmenu, $showtext, $showtextwait
            elseif(cmd == "showmenu" or cmd == "showtext" or cmd == "showtextwait") then
                if(args == nil or args == "") then
                    return "Ошибка в строке "..tostring(i)..": ожидалось название файла."
                end
            else
                return "Ошибка в строке "..tostring(i)..": команда не найдена."
            end
        end
        newmenu[i] = l
        i = i + 1
    end

    currentmenu = newmenu
    return "OK."
end

function bblog(s)
    sampAddChatMessage("[brightbinder.lua] "..s, 0xAAAAAA)
end

function get_player_info(id)
    local connected
    if(id == -2) then
        id = sampGetPlayerIdByCharHandle(PLAYER_PED)
        connected = true
    else
        connected = sampIsPlayerConnected(id) or (id == sampGetPlayerIdByCharHandle(PLAYER_PED))
    end
    if(connected) then
        return sampGetPlayerNickname(id), sampGetPlayerScore(id)
    else
        return nil, nil
    end
end

function show_menu()
    local title
    if (currentpid ~= -1) then
        title = "Цель: "..currentpname..'['..currentpid.."] (LVL: "..currentpscore..")"
    else
        title = "Цель не выбрана"
    end
    -- selecting only titles
    local options = ""
    for i = 1, table.getn(currentmenu) do
        local tmp = currentmenu[i]:match("^@(.*)")
        if(tmp ~= nil) then
            options = options .. tmp .. "\n"
        end
    end
    -- returning selected item as a string (because fuck you)
    sampShowDialog(bbdid,title,options,"Выбрать","Отмена",DIALOG_STYLE_LIST)
    while(sampIsDialogActive(bbdid)) do wait(100) end
    local _, tbutton, tindex, _ = sampHasDialogRespond(bbdid)
    if(tbutton == 1) then
        return tindex
    else
        return -1
    end
end

function show_text(fname)
    if(fname == nil) then
        fname = "nil"
    end
    local input = io.open(getGameDirectory().."//moonloader//brightbinder//"..fname..".txt", "r")
    local res
    if(input == nil) then
        res = "Файл ".. fname .. ".txt не найден!"
    else
        res = input:read("*a")
        input:close()
    end
    sampShowDialog(bbdid,"Сообщение",res,"Ок",nil,DIALOG_STYLE_MSGBOX)
    while(sampIsDialogActive(bbdid)) do wait(100) end
end

function process_menu_selection(item)
    if(item == -1) then return false end
    local cindex = -1
    for k,v in ipairs(currentmenu) do
        -- ignoring lines with spaces/tabs only
        -- TODO!
        -- making sure we're within the selected item
        if(v:sub(1,1) == "@") then
            cindex = cindex + 1
            if(cindex > item) then
                break
            end
        elseif(cindex == item) then
            -- processing the lines
            if(v == "") then
            elseif(v:sub(1,1) == "$") then
                local cmd, args = v:match("^%$([%w_]*)%s*([%w_]*)$")
                if(cmd == "wait") then
                    wait(tonumber(args))
                elseif(cmd == "showmenu") then
                    lua_thread.create(function() call_menu(args) end)
                elseif(cmd == "showtext") then
                    lua_thread.create(function() show_text(args) end)
                elseif(cmd == "showtextwait") then
                    show_text(args)
                else
                    bblog("Команда не распознана.")
                end
            else
                v = substitute(v)
                if(v == "$target_err") then
                    bblog("Ошибка: не указана цель.")
                elseif(settings["sending_mode"] == "send") then
                    sampSendChat(v)
                elseif(settings["sending_mode"] == "process") then
                    sampProcessChatInput(v)
                else
                    bblog("[РЕЖИМ ОТЛАДКИ] "..v)
                end
            end
        end
    end
end

function call_menu(fname)
    local errmsg = "OK."
    errmsg = file_to_menu(fname)
    if(errmsg ~= "OK.") then
        bblog(errmsg)
        return false
    end

    local selecteditem = show_menu()
    process_menu_selection(selecteditem)
end

function on_script_call()
    -- getting aim target
    local _, aimped = getCharPlayerIsTargeting(PLAYER_HANDLE)
    local _, aimid = sampGetPlayerIdByCharHandle(aimped)
    if(aimid ~= -1) then
        currentpid = aimid
        currentpname, currentpscore = get_player_info(currentpid)
    else
        currentpid = -1
        currentpname = nil
        currentpscore = 0
    end
    -- getting player id
    playerid = sampGetPlayerIdByCharHandle(PLAYER_PED)

    call_menu("default")
end

function main()
    -- obligatory samp checks
    if not isSampfuncsLoaded() or not isSampLoaded() then return end
    while not isSampAvailable() do wait(100) end
    -- hey, we've compiled and are running (except load_settings outputs anyway)
    load_settings()
    sampRegisterChatCommand("bbload",load_settings)
    while true do
        wait(10)
        if (wasKeyPressed(0x12) and (isKeyDown(0x02))) then
            lua_thread.create(on_script_call)
        end
    end
end

-- post-main section: the good stuff

local se = require "lib.samp.events"

local givelicenserequested = false

function se.onSendCommand(s)
    -- accepting the next /givelicense dialog
    if(settings["disable_auto_givelicense"] and s:sub(1,12) == "/givelicense") then
        givelicenserequested = true
    end

    -- inserting r-tag
    if(settings["rtag"] == "") then return {s} end
    if(s:sub(1,3) == "/r " or s:sub(1,3) == "/f ") then
        s = s:sub(1,2).." "..settings["rtag"]..s:sub(3,s:len())
    end
    return {s}
end

function se.onSetPlayerColor(pid, color)
    if(color == settings["src_clist"] and pid == player_id()) then
        sampSendChat("/clist "..tostring(settings["dst_clist"]))
    end
end

function se.onSendClickPlayer(pid, src)
    givelicenserequested = true
end

function se.onShowDialog(did, style, title, button1, button2, text)
    if(text:sub(1,16) == "Урок по вождению") then
        if(givelicenserequested) then
            givelicenserequested = false
        else
            return false
        end
    end
end

-- settings system
function load_settings()
    fname = getGameDirectory().."//moonloader//brightbinder.cfg"
    local input = io.open(fname, "r")
    if(input == nil) then
        bblog("Ошибка при загрузке настроек: файл brightbinder.cfg не найден в папке moonloader.")
        return
    end

    local newsettings = {}
    
    for l in input:lines() do
        l = l:gsub("\t","")
        l = l:gsub("^%s*","")
        l = l:gsub("%s*$","")
        local key,val = l:match("^([%w_]+)=(.+)$")
        local parsedval
        if(settings[key] ~= nil) then
            if(type(settings[key]) == "number") then
                parsedval = tonumber(settings[key])
                if(parsedval ~= nil) then
                    newsettings[key] = parsedval
                else
                    bblog("Ошибка при загрузке настроек: после "..key.." ожидалось число, встречено "..val..".")
                    return
                end
            elseif(type(settings[key]) == "boolean") then
                if(val == "true") then
                    newsettings[key] = true
                elseif(val == "false") then
                    newsettings[key] = false
                else
                    bblog("Ошибка при загрузке настроек: после "..key.." ожидалось true/false, встречено "..val..".")
                    return
                end
            else
                newsettings[key] = val
            end
        end
    end

    input:close()

    local settingcount = 0
    for k,v in pairs(newsettings) do
        settings[k] = v
        
        settingcount = settingcount + 1
    end

    bblog("Настройки успешно загружены.")
end