--!strict
-- Test EZ / Unit Test specification for MatchmakingCoordinator

local MatchmakingCoordinator = require(script.Parent.MatchmakingCoordinator)

return function()
	describe("MatchmakingCoordinator", function()
		it("should deterministically shard user IDs across available shards", function()
			local shard1 = MatchmakingCoordinator.GetShardIndex(1001)
			local shard2 = MatchmakingCoordinator.GetShardIndex(1001)
			expect(shard1).to.equal(shard2)

			local shardA = MatchmakingCoordinator.GetShardIndex(1000)
			local shardB = MatchmakingCoordinator.GetShardIndex(1004)
			-- With 4 shards (0,1,2,3), 1000 % 4 == 0 and 1004 % 4 == 0
			expect(shardA).to.equal(0)
			expect(shardB).to.equal(0)
		end)

		it("should correctly form balanced 5v5 lobbies from 10 tickets", function()
			local tickets = {}
			for i = 1, 10 do
				table.insert(tickets, {
					userId = i,
					mmr = 1000 + (i * 50),
					joinTime = os.time() - i,
					partySize = 1,
					partyMembers = { i },
					selectedMode = "Standard5v5",
				})
			end

			local lobbies = MatchmakingCoordinator.FormLobbies(tickets)
			expect(#lobbies).to.equal(1)
			expect(#lobbies[1].teamA).to.equal(5)
			expect(#lobbies[1].teamB).to.equal(5)
		end)
	end)
end
