-- pid = Xb8pn8D9fg89nHfqkjYJ3DCCgf3E51rWWQaJL2hmYI4
-- 初始化全局变量来存储最新的游戏状态和游戏主机进程。
LatestGameState = LatestGameState or nil
InAction = InAction or false -- 防止代理同时采取多个操作。
local Game = "0rVZYFxvfJpO__EfOz0_PUQ3GFE9kEaES0GkUDNXjvE"

Logs = Logs or {}

local colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function AddLog(msg, text) -- 函数定义注释用于性能，可用于调试
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- 3 * 3之内都可以攻击
function IsCanAttack(my, other)
  return math.abs(my.x - other.x) <= 3 and math.abs(my.y - other.y) <= 3
end

-- 根据玩家的距离和能量决定下一步行动。
-- 如果有玩家在范围内，则发起攻击； 否则，随机移动。
function DecideNextAction()
  -- 增加判空
  if LatestGameState == nil or LatestGameState.Players == nil then
    print("Game state or players data is not available")
    return
  end
  local my = LatestGameState.Players[ao.id]
  local targetInRange = false
  for target, other in pairs(LatestGameState.Players) do
    if target ~= ao.id and IsCanAttack(my, other) then
      targetInRange = true
      break
    end
  end

  if my.energy > 10 and targetInRange then
    print("开始攻击")
    ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(my.energy)})
  else
    print("距离不够，随机移动")
    local directionMap = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
    local randomIndex = math.random(#directionMap)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionMap[randomIndex]})
  end
  InAction = false --释放锁
end

-- 打印游戏公告并触发游戏状态更新的handler。
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    -- 增加判空
    if msg == nil or msg.Event == nil then
      return
    end
    if msg.Event == "Started-Waiting-Period" then
      -- 自动支付
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true -- 加锁
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then --  InAction 逻辑添加
      print("等待最新响应，跳过")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- 触发游戏状态更新的handler。
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then -- InAction 逻辑添加
      InAction = true -- InAction 逻辑添加
      print(colors.gray .. "获取游戏最新状态" .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("锁状态")
    end
  end
)

-- 等待期开始时自动付款确认的handler。
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("自动付款")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
  end
)

-- 接收游戏状态信息后更新游戏状态的handler。
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("以获取最新状态")
    print(LatestGameState)
  end
)

-- 根据游戏最新状态往下走
Handlers.add(
  "DecideNextAction",

  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then
      InAction = false -- InAction 逻辑添加
      return
    end
    DecideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- 被其他玩家击中时自动攻击的handler。
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then --  InAction 逻辑添加
      InAction = true --  InAction 逻辑添加
      local myEnergy = LatestGameState.Players[ao.id].energy
      if myEnergy == nil or myEnergy == undefined then
        print(colors.red .. "错误" .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif myEnergy == 0 then
        print(colors.red .. "没能量了，速速移动" .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
        local directionMap = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
        local randomIndex = math.random(#directionMap)
        ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionMap[randomIndex]})
      else
        print(colors.red .. "开始攻击" .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(myEnergy)})
        print(colors.red .. "消耗能量" .. myEnergy .. colors.reset)
      end
      InAction = false --  InAction 逻辑添加
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("锁状态")
    end
  end
)