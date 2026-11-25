-- Push-to-talk dictation with whisper.cpp.
--   Hold RIGHT Option  -> English
--   Hold RIGHT Command -> Hinglish (romanized: "main keh raha tha")
-- Release to transcribe and paste into the focused field.
-- A tap shorter than MIN_HOLD, or pressing another key while holding, cancels.

local M = {}

local HOME    = os.getenv("HOME")
local REC     = "/opt/homebrew/bin/rec"
local SOX     = "/opt/homebrew/bin/sox"
local WHISPER = "/opt/homebrew/bin/whisper-cli"
local RAW     = HOME .. "/.whisper/dictation_raw.wav"
local WAV     = HOME .. "/.whisper/dictation.wav"
local MIN_HOLD  = 0.35   -- seconds; shorter taps are ignored
local TAIL_PAD  = 0.30   -- keep recording this long after release so the last word isn't clipped

-- Words Whisper should spell your way (names, products, jargon). Edit freely.
local VOCAB = "Claude, GitHub, Kubernetes, Hammerspoon."

local MODES = {
  [61] = { -- right Option
    name  = "English",
    model = HOME .. "/.whisper/models/ggml-large-v3-q5_0.bin",
    args  = { "-l", "en", "--prompt", "Hello. " .. VOCAB },
  },
  [54] = { -- right Command
    name  = "Hinglish",
    model = HOME .. "/.whisper/models/ggml-hinglish-apex-q8_0.bin",
    args  = { "-l", "en", "--prompt", "Haan, main keh raha tha ki " .. VOCAB },
  },
}

local recTask, alertId, pressedAt, cancelled, mode = nil, nil, nil, false, nil
local busy, heldKey = false, nil

local function showAlert(msg)
  if alertId then hs.alert.closeSpecific(alertId) end
  alertId = hs.alert.show(msg, { textSize = 16, radius = 8, fadeInDuration = 0.05 }, hs.screen.mainScreen(), 120)
end

local function hideAlert()
  if alertId then hs.alert.closeSpecific(alertId); alertId = nil end
end

local JUNK = { [""] = true, ["[BLANK_AUDIO]"] = true, ["(silence)"] = true, ["[Music]"] = true,
               ["Thank you."] = true, ["Thanks for watching!"] = true, ["you"] = true }

local function paste(text)
  local saved = hs.pasteboard.readAllData()
  hs.pasteboard.setContents(text)
  hs.eventtap.keyStroke({ "cmd" }, "v", 0)
  hs.timer.doAfter(0.4, function() if saved then hs.pasteboard.writeAllData(saved) end end)
end

local function finish()
  busy = false
  hideAlert()
end

local function runWhisper(m)
  local args = { "-m", m.model, "-f", WAV, "-nt", "-np", "-sns" }
  for _, a in ipairs(m.args) do table.insert(args, a) end
  hs.task.new(WHISPER, function(code, out, err)
    finish()
    if code ~= 0 then
      hs.alert.show("Whisper failed (" .. tostring(code) .. ")")
      print("whisper stderr: " .. (err or ""))
      return
    end
    local text = (out or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if JUNK[text] then return end
    paste(text)
  end, args):start()
end

local function transcribe(m)
  busy = true
  showAlert("✍️ Transcribing (" .. m.name .. ")…")
  -- Clean up audio: cut rumble, normalise level, add a little silence at both ends.
  hs.task.new(SOX, function(code, _, err)
    if code ~= 0 then finish(); print("sox: " .. (err or "")); return end
    runWhisper(m)
  end, { RAW, WAV, "highpass", "80", "norm", "-1", "pad", "0.2", "0.3" }):start()
end

local function startRec(key)
  if busy or recTask then return end
  mode = MODES[key]
  os.remove(RAW); os.remove(WAV)
  cancelled = false
  pressedAt = hs.timer.secondsSinceEpoch()
  recTask = hs.task.new(REC, function()
    recTask = nil
    if cancelled then hideAlert(); return end
    transcribe(mode)
  end, { "-q", "-c", "1", "-r", "16000", "-b", "16", RAW })
  recTask:start()
  showAlert("🎙 " .. mode.name .. "…")
end

local function stopRec(cancel)
  if not recTask then return end
  local held = hs.timer.secondsSinceEpoch() - (pressedAt or 0)
  cancelled = cancel or held < MIN_HOLD
  local t = recTask
  if cancelled then t:interrupt(); return end
  hs.timer.doAfter(TAIL_PAD, function() if t:isRunning() then t:interrupt() end end)  -- SIGINT finalises the WAV
end

local FLAG = { [61] = "alt", [54] = "cmd" }

M.flagsTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(e)
  local key = e:getKeyCode()
  if not MODES[key] then return false end
  local down = e:getFlags()[FLAG[key]] == true
  if down and not heldKey then
    heldKey = key
    startRec(key)
  elseif not down and heldKey == key then
    heldKey = nil
    stopRec(false)
  end
  return false
end)

-- Any normal key pressed while holding = user is typing a shortcut; cancel.
M.keyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function()
  if heldKey and recTask then stopRec(true) end
  return false
end)

M.flagsTap:start()
M.keyTap:start()

-- macOS disables event taps that time out; keep them alive.
M.watchdog = hs.timer.doEvery(5, function()
  if not M.flagsTap:isEnabled() then M.flagsTap:start() end
  if not M.keyTap:isEnabled() then M.keyTap:start() end
end)

return M
