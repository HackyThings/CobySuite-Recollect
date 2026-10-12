-------------------------------------------------------------------------------
-- Recollect Debug Window: thin wrapper around CobySuite.Debug.NewWindow
-------------------------------------------------------------------------------

Recollect.DebugWindow = CobySuite_Recollect.Debug.NewWindow({
  windowName = "RecollectDebugWindow",
  title = CobySuite_Recollect.Utilities.WrapColor(Recollect.BRAND_COLOR, "Recollect") .. " debug log",
  icon = Recollect.ICON,
  logger = Recollect.Debug,
})
