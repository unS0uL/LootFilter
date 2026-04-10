LootFilterVars = {}

LootFilter = {
	VERSION = "2.0.0",
	LOOT_TIMEOUT = 20,
	LOOT_PARSE_DELAY = 1,
	RETRY_DELAY = 0.5,
	MAX_RETRIES = 3,
	REALMPLAYER = "",
	nampowerAvailable = false,

	qualities = {
		[1] = "Crap (Grey)",
		[2] = "Common (White)",
		[3] = "Uncommon (Green)",
		[4] = "Rare (Blue)",
		[5] = "Epic (Purple)",
		[6] = "Legendary (Orange)",
		[7] = "Artifact (Red)",
		[8] = "Quest",
	},
	timerArr = {},
	itemValueSupport = 0,
	hasFocus = 0,
}

-- Utility Functions

function LootFilter.print(value)
	if value == nil then
		value = ""
	end
	DEFAULT_CHAT_FRAME:AddMessage("Loot Filter - " .. value, 1.0, 1.0, 1.0)
end

function LootFilter.schedule(delay, func, ...)
	table.insert(LootFilter.timerArr, { time = time() + delay, func = func, args = arg })
end

function LootFilter.processTimers()
	local count = table.getn(LootFilter.timerArr)
	if count == 0 then
		return
	end
	local currentTime = time()
	local i = 1
	while i <= count do
		local timer = LootFilter.timerArr[i]
		if currentTime >= timer.time then
			table.remove(LootFilter.timerArr, i)
			count = count - 1
			timer.func(unpack(timer.args))
		else
			i = i + 1
		end
	end
end

-- Match item name against search pattern
-- itemName: actual item name from GetItemInfo
-- searchName: pattern to match (use #prefix for partial match)
function LootFilter.matches(itemName, searchName)
	if itemName == nil or searchName == nil then
		return false
	end

	-- Check for partial match prefix (#)
	if string.find(searchName, "#", 1, true) == 1 then
		local pattern = string.lower(string.sub(searchName, 2))
		return string.find(string.lower(itemName), pattern, 1, true) ~= nil
	end

	-- Exact match (case-insensitive) - use single lower conversion
	local itemLower = string.lower(itemName)
	local searchLower = string.lower(searchName)
	return itemLower == searchLower
end

-- Get player vars helper
function LootFilter.getPlayerVars()
	return LootFilterVars[LootFilter.REALMPLAYER]
end

-- Pre-filter items BEFORE adding to itemStack
-- Returns true if item should be processed for deletion
function LootFilter.shouldProcessItem(name, quality)
	local playerVars = LootFilter.getPlayerVars()
	if not playerVars then
		return false
	end

	-- Priority 1: Keep list - don't process
	local namesCount = table.getn(playerVars.names)
	for i = 1, namesCount do
		if LootFilter.matches(name, playerVars.names[i]) then
			return false
		end
	end

	-- Priority 2: Delete list - definitely process
	local deleteCount = table.getn(playerVars.namesdelete)
	for i = 1, deleteCount do
		if LootFilter.matches(name, playerVars.namesdelete[i]) then
			return true
		end
	end

	-- Priority 3: Quality filter
	-- qualities[quality+1] = false means "Filtered" (DELETE)
	if quality and quality >= 0 and quality <= 7 then
		if not playerVars.qualities[quality + 1] then
			return true
		end
	end

	-- Default: Don't process (no reason to delete)
	return false
end

-- Optimized bag iteration using NAMPOWER GetBagItems if available
function LootFilter.iterateBags(callback)
	if LootFilter.nampowerAvailable and GetBagItems then
		-- Use NAMPOWER GetBagItems for faster iteration
		for bagIndex = 0, 4 do
			local bagItems = GetBagItems(bagIndex)
			if bagItems then
				for slotIndex, itemInfo in pairs(bagItems) do
					if callback(bagIndex, slotIndex, itemInfo) then
						return true
					end
				end
			end
		end
	else
		-- Fallback to standard API
		for bagIndex = 0, 4 do
			local bagSize = GetContainerNumSlots(bagIndex)
			for slotIndex = 1, bagSize do
				local texture = GetContainerItemInfo(bagIndex, slotIndex)
				local itemInfo = { texture = texture }
				if callback(bagIndex, slotIndex, itemInfo) then
					return true
				end
			end
		end
	end
	return false
end

-- Core Deletion Logic

function LootFilter.deleteItemFromInventory(stackItem)
	local playerVars = LootFilter.getPlayerVars()
	if not playerVars then
		return false
	end

	local debugMode = playerVars.debugMode
	local notify = playerVars.notifydelete

	-- Stack item is now a table
	if type(stackItem) ~= "table" then
		if debugMode then
			LootFilter.print("[DEBUG] ERROR: stackItem is not a table: " .. type(stackItem))
		end
		return false
	end

	local searchItemTexture = stackItem.texture
	local searchItemName = stackItem.name

	if debugMode then
		LootFilter.print(
			"[DEBUG] Searching: " .. tostring(searchItemName) .. " (texture: " .. tostring(searchItemTexture) .. ")"
		)
	end

	-- Iterate through all bags
	for bagIndex = 0, 4 do
		local bagSize = GetContainerNumSlots(bagIndex)
		for slotIndex = 1, bagSize do
			local itemTexture = GetContainerItemInfo(bagIndex, slotIndex)

			-- First match: texture from loot window
			if LootFilter.matches(itemTexture, searchItemTexture) then
				if debugMode then
					LootFilter.print("[DEBUG] Texture MATCH at bag " .. bagIndex .. " slot " .. slotIndex)
				end

				local itemlink = GetContainerItemLink(bagIndex, slotIndex)
				if itemlink ~= nil then
					-- Extract item ID from link - optimized for WoW itemlink format: |Hitem:ID:...
					local _, _, itemid = string.find(itemlink, "|Hitem:(%d+):")
					itemid = tonumber(itemid)
					if itemid and itemid >= 1 then
						local itemName, _, itemRarity, _, itemType, _, itemStackCount = GetItemInfo(itemid)

						-- RETRY MECHANISM: Check if GetItemInfo returned nil
						if not itemName then
							if debugMode then
								LootFilter.print(
									"[DEBUG] GetItemInfo nil, retry "
										.. tostring(stackItem.retries + 1)
										.. "/"
										.. LootFilter.MAX_RETRIES
								)
							end
							stackItem.retries = stackItem.retries + 1
							if stackItem.retries < LootFilter.MAX_RETRIES then
								if debugMode then
									LootFilter.print(
										"[DEBUG] Retry "
											.. stackItem.retries
											.. "/"
											.. LootFilter.MAX_RETRIES
											.. " scheduled"
									)
								end
								-- Schedule retry
								LootFilter.schedule(
									LootFilter.RETRY_DELAY,
									LootFilter.findItems,
									time() + LootFilter.LOOT_TIMEOUT
								)
								return false
							else
								if debugMode then
									LootFilter.print("[DEBUG] Max retries reached, skipping item")
								end
								return false
							end
						end

						-- Second match: actual item name
						if LootFilter.matches(itemName, searchItemName) then
							if debugMode then
								LootFilter.print("[DEBUG] Name MATCH: " .. tostring(itemName))
							end

							local shouldDelete = false

							-- Priority 1: Delete list (already pre-filtered, re-check for runtime changes)
							local deleteCount = table.getn(playerVars.namesdelete)
							for k = 1, deleteCount do
								if LootFilter.matches(itemName, playerVars.namesdelete[k]) then
									shouldDelete = true
									break
								end
							end

							-- Priority 2: Quality filter (already pre-filtered, re-check for runtime changes)
							if not shouldDelete and not playerVars.qualities[itemRarity + 1] then
								shouldDelete = true
							end

							-- Priority 3: Quest items
							if not shouldDelete and not playerVars.qualities[8] and itemType == "Quest" then
								shouldDelete = true
							end

							-- Priority 4: Item value filter (can't pre-filter, needs GetItemInfo)
							if not shouldDelete and playerVars.filterItemValue and LootFilter.itemValueSupport > 0 then
								local value = -1

								if LootFilter.itemValueSupport == 1 then
									local itemData = Informant.GetItem(itemid)
									if itemData and itemData.sell then
										value = tonumber(itemData.sell)
									end
								elseif LootFilter.itemValueSupport == 2 and ItemLinks then
									if ItemLinks[itemName] then
										value = tonumber(ItemLinks[itemName].p)
									end
								elseif LootFilter.itemValueSupport == 3 and SellValues then
									local shortName = InvList_ShortenItemName(itemName)
									if SellValues[shortName] then
										value = tonumber(SellValues[shortName])
									end
								elseif LootFilter.itemValueSupport == 4 and PackRatDB and PackRatDB.items then
									if PackRatDB.items[tostring(itemid)] then
										value = tonumber(PackRatDB.items[tostring(itemid)].p)
									end
								end

								if value == -1 then
									shouldDelete = true
								elseif value > 0 then
									if itemStackCount and itemStackCount > 1 then
										value = value * itemStackCount
									end
									local valueInGold = value / 10000
									local threshold = tonumber(playerVars.itemValue) or 0
									if valueInGold > threshold then
										shouldDelete = true
									end
								end
							end

							-- Execute deletion
							if shouldDelete then
								if debugMode then
									LootFilter.print("[DEBUG] DELETE: " .. tostring(itemlink))
									table.remove(playerVars.itemStack, 1)
									return true
								else
									PickupContainerItem(bagIndex, slotIndex)
									if CursorHasItem() then
										DeleteCursorItem()
										table.remove(playerVars.itemStack, 1)
										if playerVars.notifydelete then
											LootFilter.print(itemlink .. " was deleted")
										end
										return true
									end
								end
							else
								-- Item found but filters changed since loot, remove from stack
								if debugMode then
									LootFilter.print("[DEBUG] NOT DELETED - keeping: " .. tostring(itemlink))
								end
								table.remove(playerVars.itemStack, 1)
								return true
							end
						else
							if debugMode then
								LootFilter.print(
									"[DEBUG] Name MISMATCH: expected '"
										.. tostring(searchItemName)
										.. "' got '"
										.. tostring(itemName)
										.. "'"
								)
							end
						end
					end
				end
			end
		end
	end

	if debugMode then
		LootFilter.print("[DEBUG] Item NOT FOUND in inventory")
	end
	return false
end

-- Find and process items from stack
function LootFilter.findItems(maxtime)
	local playerVars = LootFilter.getPlayerVars()
	if not playerVars or not playerVars.itemStack then
		return
	end

	local numitems = table.getn(playerVars.itemStack)
	if numitems == 0 then
		return
	end

	-- Timeout check
	if time() > maxtime then
		table.remove(playerVars.itemStack, 1)
		LootFilter.schedule(1, LootFilter.findItems, time() + LootFilter.LOOT_TIMEOUT)
		return
	end

	-- Try to delete first item
	if LootFilter.deleteItemFromInventory(playerVars.itemStack[1]) then
		LootFilter.schedule(1, LootFilter.findItems, time() + LootFilter.LOOT_TIMEOUT)
	else
		LootFilter.schedule(1, LootFilter.findItems, maxtime)
	end
end

-- UI Functions

function LootFilter.setTitle()
	LootFilterFrameTitleText:SetText("Loot Filter v" .. LootFilter.VERSION)
end

function LootFilter.getNames()
	local playerVars = LootFilter.getPlayerVars()
	if not playerVars or not playerVars.names then
		return
	end

	local result = ""
	for i = 1, table.getn(playerVars.names) do
		result = result .. playerVars.names[i] .. "\n"
	end
	this:SetText(result)
end

function LootFilter.getNamesDelete()
	local playerVars = LootFilter.getPlayerVars()
	if not playerVars or not playerVars.namesdelete then
		return
	end

	local result = ""
	for i = 1, table.getn(playerVars.namesdelete) do
		result = result .. playerVars.namesdelete[i] .. "\n"
	end
	this:SetText(result)
end

function LootFilter.setNames()
	local playerVars = LootFilter.getPlayerVars()
	if not playerVars then
		return
	end

	playerVars.names = {}
	local result = LootFilterEditBox1:GetText() .. "\n"

	for w in string.gfind(result, "[^\n]+\n") do
		w = string.gsub(w, "\n", "")
		table.insert(playerVars.names, w)
	end
end

function LootFilter.setNamesDelete()
	local playerVars = LootFilter.getPlayerVars()
	if not playerVars then
		return
	end

	playerVars.namesdelete = {}
	local result = LootFilterEditBox2:GetText() .. "\n"

	for w in string.gfind(result, "[^\n]+\n") do
		w = string.gsub(w, "\n", "")
		table.insert(playerVars.namesdelete, w)
	end
end

function LootFilter.setItemValue()
	local playerVars = LootFilter.getPlayerVars()
	if not playerVars then
		return
	end

	local value = tonumber(LootFilterEditBox3:GetText())
	if (value == nil) or (value == 0) then
		value = ""
		LootFilterCheckboxItemValue:SetChecked(false)
		playerVars.filterItemValue = false
	end
	playerVars.itemValue = value
end

function LootFilter.getItemValue()
	local playerVars = LootFilter.getPlayerVars()
	if not playerVars then
		return
	end

	local value
	if (playerVars.itemValue == nil) or (playerVars.itemValue == "") then
		value = ""
		LootFilterCheckboxItemValue:SetChecked(false)
		playerVars.filterItemValue = false
	else
		value = playerVars.itemValue
	end
	this:SetText(value)
end

function LootFilter.updateFocus(num, value)
	if value then
		this:SetFocus()
		LootFilter.hasFocus = num
	else
		this:ClearFocus()
		LootFilter.hasFocus = 0
	end
end

function LootFilter.findItemWithLock()
	for j = 0, 4 do
		local bagSize = GetContainerNumSlots(j)
		for i = 1, bagSize do
			local _, _, locked = GetContainerItemInfo(j, i)
			if locked then
				local itemlink = GetContainerItemLink(j, i)
				if itemlink ~= nil then
					for _, itemid in string.gfind(itemlink, "([^:]+):(%w+)") do
						itemid = tonumber(itemid)
						if itemid >= 1 then
							return GetItemInfo(itemid) or ""
						end
					end
				end
			end
		end
	end
	return ""
end

-- Event Handler

function LootFilter.OnEvent()
	if event == "LOOT_OPENED" then
		local playerVars = LootFilter.getPlayerVars()
		if not (playerVars and playerVars.enabled) then
			return
		end

		local numitems = GetNumLootItems()
		for i = 1, numitems do
			if not LootSlotIsCoin(i) then
				local icon, name, _, quality = GetLootSlotInfo(i)
				if icon ~= nil then
					-- Pre-filter: only add items that should be processed for deletion
					if LootFilter.shouldProcessItem(name, quality) then
						table.insert(playerVars.itemStack, { texture = icon, name = name, retries = 0 })
						if playerVars.debugMode then
							LootFilter.print("[DEBUG] +Item: " .. tostring(name) .. " (q:" .. tostring(quality) .. ")")
						end
					end
				end
			end
		end
		return
	end

	if event == "LOOT_CLOSED" then
		local playerVars = LootFilter.getPlayerVars()
		if playerVars and playerVars.enabled and table.getn(playerVars.itemStack) > 0 then
			LootFilter.schedule(LootFilter.LOOT_PARSE_DELAY, LootFilter.findItems, time() + LootFilter.LOOT_TIMEOUT)
		end
		return
	end

	if event == "ITEM_LOCK_CHANGED" then
		if LootFilter.hasFocus > 0 then
			local itemName = LootFilter.findItemWithLock()
			if (itemName ~= nil) and (itemName ~= "") then
				if LootFilter.hasFocus == 1 then
					LootFilterEditBox1:SetText(LootFilterEditBox1:GetText() .. itemName .. "\\n")
				elseif LootFilter.hasFocus == 2 then
					LootFilterEditBox2:SetText(LootFilterEditBox2:GetText() .. itemName .. "\\n")
				end
			end
		end
		return
	end

	-- Fallback for standard event
	if event == "UNIT_INVENTORY_CHANGED" then
		-- No action needed, LOOT_CLOSED handles scheduling
		return
	end

	if event == "ADDON_LOADED" then
		if arg1 == "LootFilter" then
			LootFilter.REALMPLAYER = GetCVar("realmName") .. UnitName("player")

			if LootFilterVars[LootFilter.REALMPLAYER] == nil then
				LootFilterVars[LootFilter.REALMPLAYER] = {}
			end

			local playerVars = LootFilterVars[LootFilter.REALMPLAYER]

			-- Migrate legacy global vars
			if playerVars.qualities == nil then
				if LootFilterVars.qualities then
					playerVars.qualities = LootFilterVars.qualities
					LootFilterVars.qualities = nil
				else
					playerVars.qualities = {}
				end
			end

			if playerVars.names == nil then
				if LootFilterVars.names then
					playerVars.names = LootFilterVars.names
					LootFilterVars.names = nil
				else
					playerVars.names = {}
				end
			end

			if playerVars.namesdelete == nil then
				playerVars.namesdelete = {}
			end

			if playerVars.itemStack == nil then
				if LootFilterVars.itemStack then
					playerVars.itemStack = LootFilterVars.itemStack
					LootFilterVars.itemStack = nil
				else
					playerVars.itemStack = {}
				end
			else
				-- CLEAR legacy itemStack (old string format is incompatible with new table format)
				-- itemStack should NOT persist between sessions (loot window closes on logout)
				local oldCount = table.getn(playerVars.itemStack)
				playerVars.itemStack = {}
				if oldCount > 0 then
					LootFilter.print("[DEBUG] Cleared " .. oldCount .. " legacy items from itemStack (old format)")
				end
			end

			if playerVars.enabled == nil then
				if LootFilterVars.enabled then
					playerVars.enabled = LootFilterVars.enabled
					LootFilterVars.enabled = nil
				else
					playerVars.enabled = true
				end
			end

			if playerVars.notifydelete == nil then
				playerVars.notifydelete = true
			end

			if playerVars.filterItemValue == nil then
				playerVars.filterItemValue = false
			end

			if playerVars.itemValue == nil then
				playerVars.itemValue = ""
			end

if playerVars.debugMode == nil then
 playerVars.debugMode = false
 end

			-- Initialize quality defaults
			for i = 1, 8 do
				if playerVars.qualities[i] == nil then
					playerVars.qualities[i] = true
				end
			end
		end

		LootFilter.checkDependencies()
		return
	end
end

-- Dependencies Check

function LootFilter.checkDependencies()
	-- Check for NAMPOWER
	if GetBagItems then
		LootFilter.nampowerAvailable = true
	end

	if IsAddOnLoaded("Informant") then
		LootFilter.itemValueSupport = 1
	elseif IsAddOnLoaded("LootLink") then
		LootFilter.itemValueSupport = 2
	elseif IsAddOnLoaded("SellValue") then
		LootFilter.itemValueSupport = 3
	elseif IsAddOnLoaded("PackRat") then
		LootFilter.itemValueSupport = 4
	end

	if LootFilter.itemValueSupport ~= 0 then
		LootFilterCheckboxItemValue:Show()
		LootFilterEditBox3:Show()
		LootFilterTextBackground3:Show()
	end
end

-- UI Options

function LootFilter.getOption(num)
	local playerVars = LootFilter.getPlayerVars()
	if not playerVars then
		return
	end

	local labelString = getglobal(this:GetName() .. "Text")
	local label = ""

	if num == 99 then
		this:SetChecked(playerVars.enabled)
		label = "Enable Loot Filter"
	elseif num == 199 then
		this:SetChecked(playerVars.notifydelete)
		label = "Notify on delete"
	elseif num == 299 then
		this:SetChecked(playerVars.filterItemValue)
		label = "Item value (Gold):"
	elseif playerVars.qualities[num] ~= nil then
		this:SetChecked(not playerVars.qualities[num])
		label = LootFilter.qualities[num] .. " items"
	end

	labelString:SetText(label)
end

function LootFilter.setOption(num)
	local playerVars = LootFilter.getPlayerVars()
	if not playerVars then
		return
	end

	local check = this:GetChecked() and true or false

	if num == 99 then
		playerVars.enabled = check
	elseif num == 199 then
		playerVars.notifydelete = check
	elseif num == 299 then
		playerVars.filterItemValue = check
	elseif playerVars.qualities[num] ~= nil then
		playerVars.qualities[num] = not check
	end
end

-- Slash Commands

function LootFilter.showHelp()
	LootFilter.print("Loot Filter v" .. LootFilter.VERSION .. " usage:")
	LootFilter.print("/lf on/off - Turn filtering on or off")
	LootFilter.print("/lf notify - Toggle notification on delete")
	LootFilter.print("/lf debug - Toggle debug mode")
	LootFilter.print("/lf status - Show current settings")
	LootFilter.print("/lf item <name> - Add item to keep list")
	LootFilter.print("/lf item <number> - Remove from keep list")
	LootFilter.print("/lf itemd <name> - Add to delete list")
	LootFilter.print("/lf itemd <number> - Remove from delete list")
	LootFilter.print("/lf quality <1-8> - Toggle quality filter")
end

function LootFilter.command(cmd)
	local args = {}
	local i = 1

	for w in string.gfind(cmd or "", "%w+") do
		args[i] = w
		i = i + 1
	end

	local playerVars = LootFilter.getPlayerVars()
	if not playerVars then
		return
	end

	if table.getn(args) == 0 then
		table.sort(playerVars.namesdelete)
		table.sort(playerVars.names)

		if LootFilterOptions:IsShown() then
			LootFilterOptions:Hide()
		else
			LootFilterOptions:Show()
		end
		return
	end

	if args[1] == "on" then
		playerVars.enabled = true
		LootFilter.print("Loot Filter turned on.")
		return
	end

	if args[1] == "off" then
		playerVars.enabled = false
		LootFilter.print("Loot Filter turned off.")
		return
	end

	if args[1] == "notify" then
		playerVars.notifydelete = not playerVars.notifydelete
		LootFilter.print("Notify on delete " .. (playerVars.notifydelete and "enabled" or "disabled"))
		return
	end

	if args[1] == "debug" then
		playerVars.debugMode = not playerVars.debugMode
		if playerVars.debugMode then
			LootFilter.print("|cFF00FF00Debug mode ENABLED|r - items will NOT be deleted")
		else
			LootFilter.print("|cFFFF0000Debug mode DISABLED|r - items WILL be deleted")
		end
		return
	end

	if args[1] == "status" then
		LootFilter.print("Version " .. LootFilter.VERSION .. " is " .. (playerVars.enabled and "ON" or "OFF"))
		LootFilter.print("Notify: " .. (playerVars.notifydelete and "ON" or "OFF"))
		LootFilter.print("Debug: " .. (playerVars.debugMode and "ON" or "OFF"))

		for i = 1, 8 do
			local status = playerVars.qualities[i] and "[Not filtered]" or "[Filtered]"
			LootFilter.print(i .. ". " .. LootFilter.qualities[i] .. " " .. status)
		end

		if table.getn(playerVars.names) > 0 then
			LootFilter.print("Keep list:")
			for i = 1, table.getn(playerVars.names) do
				LootFilter.print("  " .. i .. ". " .. playerVars.names[i])
			end
		end

		if table.getn(playerVars.namesdelete) > 0 then
			LootFilter.print("Delete list:")
			for i = 1, table.getn(playerVars.namesdelete) do
				LootFilter.print("  " .. i .. ". " .. playerVars.namesdelete[i])
			end
		end
		return
	end

	if args[1] == "quality" and args[2] then
		local num = tonumber(args[2])
		if num and num >= 1 and num <= 8 and playerVars.qualities[num] ~= nil then
			playerVars.qualities[num] = not playerVars.qualities[num]
			LootFilter.print(
				LootFilter.qualities[num]
					.. " set to "
					.. (playerVars.qualities[num] and "[Not filtered]" or "[Filtered]")
			)
		end
		return
	end

	if args[1] == "item" and args[2] then
		local num = tonumber(args[2])
		if args[2] == tostring(num) then
			if playerVars.names[num] then
				LootFilter.print("Removed: " .. playerVars.names[num])
				table.remove(playerVars.names, num)
			end
		else
			local name = ""
			for i = 2, table.getn(args) do
				name = name .. (i > 2 and " " or "") .. args[i]
			end
			table.insert(playerVars.names, name)
			LootFilter.print("Added to keep list: " .. name)
		end
		return
	end

	if args[1] == "itemd" and args[2] then
		local num = tonumber(args[2])
		if args[2] == tostring(num) then
			if playerVars.namesdelete[num] then
				LootFilter.print("Removed: " .. playerVars.namesdelete[num])
				table.remove(playerVars.namesdelete, num)
			end
		else
			local name = ""
			for i = 2, table.getn(args) do
				name = name .. (i > 2 and " " or "") .. args[i]
			end
			table.insert(playerVars.namesdelete, name)
			LootFilter.print("Added to delete list: " .. name)
		end
		return
	end

	LootFilter.showHelp()
end

-- OnLoad

-- Tab completion for slash commands
function LootFilter.RegisterTabCompletion()
	if not ChatFrame_EditBox then
		return
	end

	-- Hook tab key for autocompletion
	local originalChatEdit_CustomTabCompleted = ChatEdit_CustomTabCompleted
	ChatEdit_CustomTabCompleted = function(self, ...)
		local text = self:GetText()
		local firstWord = strlower(strmatch(text, "^%s*(%S+)") or "")

		-- Check if it's our command
		if firstWord == "/lootf" or firstWord == "/lootfilter" then
			local spaceIdx = strfind(text, " ")
			if spaceIdx then
				-- Get the second word (command parameter)
				local afterCmd = strsub(text, spaceIdx + 1)
				local param = strlower(strmatch(afterCmd, "^(%S*)") or "")

				-- Autocomplete command parameters
				local params = {
					"on", "off", "debug", "status", "notify",
					"item", "itemd", "quality", "help"
				}

				for _, p in ipairs(params) do
					if strfind(strlower(p), "^" .. param) then
						self:SetText("/lootf " .. p .. " ")
						return
					end
				end
			else
				-- No space yet, add one
				self:SetText("/lootf ")
				return
			end
		end

		-- Call original function for other commands
		if originalChatEdit_CustomTabCompleted then
			return originalChatEdit_CustomTabCompleted(self, ...)
		end
	end
end

function LootFilter.OnLoad()
	SLASH_LOOTFILTER1 = "/lootf"
	SLASH_LOOTFILTER2 = "/lootfilter"
	SlashCmdList["LOOTFILTER"] = LootFilter.command

	-- Register tab completion
	LootFilter.RegisterTabCompletion()

	this:RegisterEvent("LOOT_OPENED")
	this:RegisterEvent("LOOT_CLOSED")
	this:RegisterEvent("ADDON_LOADED")
	this:RegisterEvent("ITEM_LOCK_CHANGED")

	-- Register inventory change event
	this:RegisterEvent("UNIT_INVENTORY_CHANGED")

	-- Create timer frame for processing scheduled functions
	LootFilter.timerFrame = CreateFrame("Frame", "LootFilterTimerFrame", UIParent)
	LootFilter.timerFrame:SetScript("OnUpdate", LootFilter.processTimers)
	LootFilter.print("[DEBUG] LootFilter loaded, timer frame created")
end

-- Clear item stack on logout
function LootFilter.OnLogout()
	local playerVars = LootFilter.getPlayerVars()
	if playerVars and playerVars.itemStack then
		playerVars.itemStack = {}
	end
end
