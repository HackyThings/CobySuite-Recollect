-------------------------------------------------------------------------------
-- Recollect Debug Logger: thin wrapper around CobySuite.Debug.NewLogger
-------------------------------------------------------------------------------

Recollect.Debug = CobySuite_Recollect.Debug.NewLogger({
  addonName = "Recollect",
  categories = {
    "INIT", "CONFIG", "INVENTORY", "PURPOSE", "UI", "LAB", "CURATOR", "DIAG",
  },
  savedVariable = "RECOLLECT_DEBUG_LOG",
  sessionHeader = function(lines)
    CobySuite_Recollect.Debug.AppendConfigSnapshot(lines, "RECOLLECT_CONFIG")
  end,
})
