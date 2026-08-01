# Interactive mode setup for PlanarOptim.
# Replaces PlanarInteractive's role of providing a full interactive
# environment with Watchers, Scrapers, and WGLMakie rendering.

using Planar
using PlanarCore.Watchers
using Scrapers

# Re-export key modules so they're available in the user's scope
# when PlanarOptim is used as the active project (like PlanarInteractive was).
export Plotting, PlanarOptim, Watchers, Scrapers
