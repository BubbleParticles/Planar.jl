# Interactive mode setup for PlanarOptim.
# Replaces PlanarInteractive's role of providing a full interactive
# environment with Watchers, PlanarDownloadTool, and WGLMakie rendering.

using Planar
using Planar.Watchers
using PlanarDownloadTool

# Re-export key modules so they're available in the user's scope
# when PlanarOptim is used as the active project (like PlanarInteractive was).
export Plotting, PlanarOptim, Watchers, PlanarDownloadTool
