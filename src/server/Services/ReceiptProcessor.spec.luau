--!strict
-- Test EZ / Unit Test specification for ReceiptProcessor

local ReceiptProcessor = require(script.Parent.ReceiptProcessor)

return function()
	describe("ReceiptProcessor", function()
		it("should defer processing if player is not online", function()
			local dummyReceipt = {
				PlayerId = 99999999,
				PlaceIdWherePurchased = 123456,
				PurchaseId = "test_purchase_id_123",
				ProductId = 5555,
				CurrencySpent = 100,
				CurrencyType = Enum.CurrencyType.Robux,
			}

			local result = ReceiptProcessor.ProcessReceipt(dummyReceipt)
			expect(result).to.equal(Enum.ProductPurchaseDecision.NotProcessedYet)
		end)
	end)
end
