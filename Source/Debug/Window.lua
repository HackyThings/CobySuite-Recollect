-------------------------------------------------------------------------------
-- Recollect Debug Window: thin wrapper around CobySuite.Debug.NewWindow
-------------------------------------------------------------------------------

Recollect.DebugWindow = CobySuite_Recollect.Debug.NewWindow({
  windowName = "RecollectDebugWindow",
  title = "Recollect Debug Log",
  icon = Recollect.ICON,
  logger = Recollect.Debug,
})
