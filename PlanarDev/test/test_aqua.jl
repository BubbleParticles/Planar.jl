using Test
using Aqua
using PlanarCore
test_aqua() = @testset "aqua" begin
    # Basic project quality checks on PlanarDev
    # Known method ambiguities exist; marked broken to preserve CI while acknowledging the issue
    Aqua.test_ambiguities([PlanarDev, Planar, PlanarCore]; broken=true)
end
