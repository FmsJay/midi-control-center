--- name: Oxygen Pro 61 - Pads (port 1)
--- realearn_version: 2.18.0
--- author: James Alexander (built with Claude, 2026-09-03)
--- description: |
---     Main compartment for the Oxygen Pro 61 pads. The pads transmit on USB port 1 ("Oxygen Pro 61"),
---     so this runs in its own ReaLearn unit: input "Oxygen Pro 61", output "MIDIOUT3 (Oxygen Pro 61)".
---     Bank 1: pads play instruments (notes 36-51 on channel 10) and light by velocity
---             (blue at rest, green / yellow / red for soft / medium / hard hits).
---     Bank 2: pads 1-8 LoopCanvas press slot 1-8, pads 9-16 LoopCanvas drop slot 1-8 (CC 36-51 on channel 2).
---     Bank 3: pads 1-8 LoopCanvas return section 1-8, pads 9-16 LoopCanvas align slot 1-8 (channel 3).
---     Bank 4: free (channel 4), pads white.
---     The bank is inferred from the channel of the last pad message, because bank buttons live on port 3.
---     Pad LED colours need the M-Audio LED unlock (oxygen_led_unlock.py) after every power-on.

--!strict

local mappings = {}
local function add(m)
    table.insert(mappings, m)
end

-- LED address of each pad (Ableton layout), pads 1-16 left to right, top row then bottom row.
local PAD_NOTE = { 40, 41, 42, 43, 48, 49, 50, 51, 36, 37, 38, 39, 44, 45, 46, 47 }

-- Colour codes measured on this keyboard (F-0016). Only these render; everything else shows off.
local C = { off = 0, red = 3, orange = 11, green = 12, chartreuse = 14, yellow = 15, rose = 35,
            aqua = 44, blue = 48, violet = 50, magenta = 51, azure = 56, cyan = 60, white = 63, blink = 64 }

local parameters = {
    { index = 0, id = "bank", name = "Keyboard bank (inferred)", value_count = 4,
      value_labels = { "Bank 1", "Bank 2", "Bank 3", "Bank 4" } },
}
for k = 1, 16 do
    table.insert(parameters, { index = k, id = "pad" .. k, name = "Pad " .. k .. " velocity" })
end

local groups = {
    { id = "control", name = "Control" },
    { id = "bank1", name = "Bank 1 pads", activation_condition = { kind = "Bank", parameter = 0, bank_index = 0 } },
    { id = "bank2", name = "Bank 2 pads", activation_condition = { kind = "Bank", parameter = 0, bank_index = 1 } },
    { id = "bank3", name = "Bank 3 pads", activation_condition = { kind = "Bank", parameter = 0, bank_index = 2 } },
    { id = "bank4", name = "Bank 4 pads", activation_condition = { kind = "Bank", parameter = 0, bank_index = 3 } },
}

local function param_target(i)
    return { kind = "CompartmentParameterValue", parameter = { address = "ById", index = i } }
end
local function cc_button(ch, n)
    return { kind = "MidiControlChangeValue", channel = ch, controller_number = n, character = "Button" }
end

-- A mapping whose only job is to paint one pad when its bank group becomes active.
local function paint(group, k, colour)
    local n = PAD_NOTE[k]
    add {
        id = string.format("%s-paint-%d", group, k), name = string.format("Paint pad %d", k),
        group = group, control_enabled = false, feedback_enabled = false,
        source = { kind = "None" },
        target = { kind = "Dummy" },
        on_activate = { send_midi_feedback = { { kind = "Raw", message = string.format("90 %02X %02X", n, colour) } } },
    }
end

-- (Measured 2026-09-03: the keyboard sends no MIDI clock on port 1 in Internal mode and the Tempo button
--  sends nothing, so tap tempo cannot come from the Tempo button. It lives on the encoder press instead,
--  handled by the Live watcher via the port-3 unit.)

-- ---- bank inference from the channel of the last pad message -----------------
-- bank 1 pads are notes on channel 10 (0-based 9); banks 2-4 are CCs on channels 2-4 (0-based 1-3)
for k = 1, 16 do
    add { id = string.format("sniff-b1-%d", k), name = "Bank sniffer", group = "control", feedback_enabled = false,
          source = { kind = "MidiNoteVelocity", channel = 9, key_number = PAD_NOTE[k] },
          glue = { button_filter = "PressOnly", target_interval = { 0, 0 } }, target = param_target(0) }
    for b = 1, 3 do
        add { id = string.format("sniff-b%d-%d", b + 1, k), name = "Bank sniffer", group = "control", feedback_enabled = false,
              source = cc_button(b, 35 + k),
              glue = { button_filter = "PressOnly", target_interval = { b / 3, b / 3 } }, target = param_target(0) }
    end
end

-- ---- BANK 1: velocity colour ------------------------------------------------
for k = 1, 16 do
    local n = PAD_NOTE[k]
    -- store the hit velocity (0 on release) in parameter k
    add { id = string.format("b1-pad-%d", k), name = string.format("Pad %d velocity", k),
          group = "control", feedback_enabled = false,
          source = { kind = "MidiNoteVelocity", channel = 9, key_number = n },
          target = param_target(k) }
    -- paint the pad from that parameter: blue at rest, green / yellow / red by velocity
    -- (ReaLearn's Luau sandbox has no table.concat; build the script with plain concatenation)
    local script = "local c = " .. C.blue .. "\n"
        .. "if y ~= nil and y > 0 then\n"
        .. "  if y < 0.34 then c = " .. C.green .. "\n"
        .. "  elseif y < 0.67 then c = " .. C.yellow .. "\n"
        .. "  else c = " .. C.red .. " end\n"
        .. "end\n"
        .. "return { address = " .. n .. ", messages = { { 0x90, " .. n .. ", c } } }"
    add { id = string.format("b1-led-%d", k), name = string.format("Pad %d colour", k),
          group = "bank1", control_enabled = false,
          source = { kind = "MidiScript", script_kind = "Lua", script = script },
          target = param_target(k) }
end

-- ---- BANK 2: LoopCanvas press / drop --------------------------------------------
for k = 1, 16 do
    local verb = (k <= 8) and ("_LOOPCANVAS_PRESS_SLOT_" .. k) or ("_LOOPCANVAS_DROP_SLOT_" .. (k - 8))
    add { id = string.format("b2-pad-%d", k), name = verb, group = "control", feedback_enabled = false,
          source = cc_button(1, 35 + k), glue = { button_filter = "PressOnly" },
          target = { kind = "ReaperAction", command = verb, invocation = "Trigger" } }
    paint("bank2", k, (k <= 8) and C.green or C.azure)
end

-- ---- BANK 3: LoopCanvas return section / align slot ------------------------------
for k = 1, 16 do
    local verb = (k <= 8) and ("_LOOPCANVAS_RETURN_SECTION_" .. k) or ("_LOOPCANVAS_ALIGN_SLOT_" .. (k - 8))
    add { id = string.format("b3-pad-%d", k), name = verb, group = "control", feedback_enabled = false,
          source = cc_button(2, 35 + k), glue = { button_filter = "PressOnly" },
          target = { kind = "ReaperAction", command = verb, invocation = "Trigger" } }
    paint("bank3", k, (k <= 8) and C.yellow or C.violet)
end

-- ---- BANK 4: free, white -------------------------------------------------------
for k = 1, 16 do
    paint("bank4", k, C.white)
end

return {
    parameters = parameters,
    groups = groups,
    mappings = mappings,
}
