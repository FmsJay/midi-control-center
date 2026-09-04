-- >>> Oxygen Pro 61 LED unlock (added 2026-09-03) >>>
-- The keyboard's fader-button LEDs ignore Mackie feedback until it gets
-- M-Audio's "LED mode = software" sysex. Fire the sender once per REAPER
-- start, no wait. Safe if the keyboard is absent (the script just exits).
-- Re-run manually with
-- Scripts/MIDI Control Center/Oxygen Pro - LED unlock.lua after re-plugging it.
--
do
  -- Pure-ReaScript watcher: puts the keyboard into Live mode + software LEDs now and after
  -- every power-on, then asks ReaLearn to repaint. Runs as a defer loop inside REAPER.
  local watcher = reaper.GetResourcePath() .. "/Scripts/MIDI Control Center/Oxygen Pro - Live watcher.lua"
  local ok, err = pcall(dofile, watcher)
  if not ok then reaper.ShowConsoleMsg("[oxygen] watcher failed: " .. tostring(err) .. "\n") end
end
-- <<< Oxygen Pro 61 LED unlock <<<
