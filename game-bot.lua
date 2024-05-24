LatestGameState = {}
InAction = false
Game = ""
Colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

local function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

local function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local minHealthPlayer = nil
    local minHealth = 100
    -- Find the opponent with the lowest health
    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id then
            if state.health <= minHealth then
                minHealth = state.health
                minHealthPlayer = state
            end
        end
    end
    -- Check the distance to the opponent with the lowest health
    print("Position of enemy with the lowest health: " .. minHealthPlayer.x .. minHealthPlayer.y)
    if inRange(player.x, player.y, minHealthPlayer.x, minHealthPlayer.y) then
        -- Distance is within range
        if player.energy > 10 then
            -- Energy is sufficient
            print("Attacking enemy, consuming energy: " .. player.energy)
            ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(player.energy) })
        end
    else
        -- Distance is not enough, move towards them
        if player.x - minHealthPlayer.x > 0 then
            print(colors.blue .. "Moving left" .. colors.reset)
            ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = "Left"})
        elseif player.x - minHealthPlayer.x < 0 then
            print(colors.blue .. "Moving right" .. colors.reset)
            ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = "Right"})
        elseif player.y - minHealthPlayer.y > 0 then
            print(colors.blue .. "Moving down" .. colors.reset)
            ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = "Down"})
        elseif player.y - minHealthPlayer.y < 0 then
            print(colors.blue .. "Moving up" .. colors.reset)
            ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = "Up"})
        end
    end
    InAction = false
end

local function handleEvent(msg)
    if msg.Event == "Started-Waiting-Period" then
        ao.send({ Target = ao.id, Action = "AutoPay" })
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
        InAction = true
        ao.send({ Target = Game, Action = "GetGameState" })
    elseif InAction then
        print("Previous action still in progress. Skipping.")
    end
    print(Colors.green .. msg.Event .. ": " .. msg.Data .. Colors.reset)
end

local function handleTick()
    if not InAction then
        InAction = true
        print(Colors.gray .. "Getting game state..." .. Colors.reset)
        ao.send({ Target = Game, Action = "GetGameState" })
    else
        print("Previous action still in progress. Skipping.")
    end
end

local function handleAutoPay()
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
end

local function handleUpdateGameState(msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({ Target = ao.id, Action = "UpdatedGameState" })
    print("Game state updated. Print 'LatestGameState' for detailed view.")
end

local function handleDecideNextAction()
    if LatestGameState.GameMode ~= "Playing" then
        InAction = false
        return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({ Target = ao.id, Action = "Tick" })
end

local function handleReturnAttack(msg)
    if not InAction then
        InAction = true
        local playerEnergy = LatestGameState.Players[ao.id].energy
        if playerEnergy == nil then
            print(Colors.red .. "Unable to read energy." .. Colors.reset)
            ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
        elseif playerEnergy == 0 then
            print(Colors.red .. "Player has insufficient energy." .. Colors.reset)
            ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
        else
            print(Colors.red .. "Returning attack." .. Colors.reset)
            ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy) })
        end
        InAction = false
        ao.send({ Target = ao.id, Action = "Tick" })
    else
        print("Previous action still in progress. Skipping.")
    end
end

Handlers.add("PrintAnnouncements", Handlers.utils.hasMatchingTag("Action", "Announcement"), handleEvent)
Handlers.add("AutoPay", Handlers.utils.hasMatchingTag("Action", "AutoPay"), handleAutoPay)
Handlers.add("GetTickEval", Handlers.utils.hasMatchingTag("Action", "Tick"), handleTick)
Handlers.add("UpdateGameState", Handlers.utils.hasMatchingTag("Action", "GameState"), handleUpdateGameState)
Handlers.add("decideNextAction", Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"), handleDecideNextAction)
Handlers.add("ReturnAttack", Handlers.utils.hasMatchingTag("Action", "Hit"), handleReturnAttack)