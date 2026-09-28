-- CobySuite: Shared library for all CobySuite addons
-- All shared utilities, UI factories, and infrastructure live here.
-- Individual addons (CobySniper, CobysLinkepedia, etc.) depend on this.

CobySuite_Recollect = CobySuite_Recollect or {}

-- Sub-namespace declarations (populated by individual modules)
CobySuite_Recollect.Utilities = CobySuite_Recollect.Utilities or {}
CobySuite_Recollect.UI        = CobySuite_Recollect.UI or {}
CobySuite_Recollect.Debug     = CobySuite_Recollect.Debug or {}
CobySuite_Recollect.Config    = CobySuite_Recollect.Config or {}
CobySuite_Recollect.EventBus  = CobySuite_Recollect.EventBus or {}
CobySuite_Recollect.Chat      = CobySuite_Recollect.Chat or {}
CobySuite_Recollect.Slash     = CobySuite_Recollect.Slash or {}
CobySuite_Recollect.Tests     = CobySuite_Recollect.Tests or {}

CobySuite_Recollect.SortDir = { ASC = "asc", DESC = "desc" }

-- Where this copy of the library comes from. The monorepo's CobySuite addon
-- leaves it as is; a standalone build embeds the library under its own name
-- and replaces it from its Build.lua with { embedded = true, host = "<addon>",
-- commit = "<short sha>", dirty = <bool> }.
CobySuite_Recollect.BuildInfo = CobySuite_Recollect.BuildInfo or { embedded = false }

-- The library version for reports: "embedded in <host> at <commit>" in a
-- standalone build, else the CobySuite addon's TOC version. The addon name
-- below is the only string literal in shared code that is exactly the
-- library's name (the standalone build checks this).
function CobySuite_Recollect.LibraryVersionText()
  local info = CobySuite_Recollect.BuildInfo
  if info and info.embedded then
    return ("embedded in %s at %s"):format(tostring(info.host or "?"), tostring(info.commit or "?"))
  end
  return C_AddOns.GetAddOnMetadata("CobySuite", "Version") or "?"
end
