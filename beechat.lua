-- beechat.lua  ->  install to /home/lib/beechat.lua
-- Chat notifications via a Computronics Chat Box. Optional: every
-- function is a safe no-op if no chat box is attached, and a chat
-- failure can never crash the breeding loop.
--
-- Tip: rename the Chat Box in an anvil to change its [ChatBox]
-- chat prefix to something like [BeeBreeder].

local component = require("component")

local chat = { available = component.isAvailable("chat_box") }
local box = chat.available and component.chat_box or nil

function chat.say(msg)
  if not chat.available then return end
  pcall(box.say, msg)
end

-- For events that need a human: prefixed so they stand out in chat
function chat.alert(msg)
  chat.say("(!) " .. msg)
end

return chat
