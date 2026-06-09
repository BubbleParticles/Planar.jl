module RemoteTests

using Test
using Remote

@testset "Remote module loads" begin
    @test isdefined(Remote, :tgclient)
    @test isdefined(Remote, :tgstart!)
    @test isdefined(Remote, :tgstop!)
    @test isdefined(Remote, :tgrun)
    @test isdefined(Remote, :tgtask)
    @test isdefined(Remote, :tgcommands)
    @test isdefined(Remote, :_envvar)
    @test isdefined(Remote, :safe_delete_webhook)
end

@testset "Constants" begin
    @test Remote.TIMEOUT[] == 20
    @test isdefined(Remote, :RC)
    @test isdefined(Remote, :GC)
    @test isdefined(Remote, :YC)
    @test isdefined(Remote, :BC)
    @test isdefined(Remote, :KC)
    @test isdefined(Remote, :DA)
    @test isdefined(Remote, :UA)
    @test isdefined(Remote, :LRA)
end

@testset "_envvar" begin
    @test Remote._envvar(:tgtoken) == "TELEGRAM_BOT_TOKEN"
    @test Remote._envvar(:tgchat_id) == "TELEGRAM_BOT_CHAT_ID"
    @test Remote._envvar(:tgusername) == "TELEGRAM_BOT_USERNAME"
    @test Remote._envvar(:mykey) == "TELEGRAM_BOT_MYKEY"
end

@testset "tgcommands" begin
    cmds_json = Remote.tgcommands()
    @test cmds_json isa String
    @test startswith(cmds_json, "[")
    @test endswith(cmds_json, "]")
    @test occursin("start", cmds_json)
    @test occursin("stop", cmds_json)
    @test occursin("status", cmds_json)
    @test occursin("balance", cmds_json)
    @test occursin("set", cmds_json)
    @test occursin("get", cmds_json)
end

end
