--!strict
--[[
	NumberFormat
	Short, readable numbers for idle-game UI.
		999        -> "999"
		1234       -> "1.23K"
		45600000   -> "45.6M"
		1.5e15     -> "1.5Qa"
	Always 3 significant digits after the first suffix, trailing zeros removed.
]]

local NumberFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trimZeros(text: string): string
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

function NumberFormat.abbreviate(n: number): string
	if n ~= n then
		return "NaN"
	end
	if n == math.huge then
		return "∞"
	end
	if n == -math.huge then
		return "-∞"
	end
	if n < 0 then
		return "-" .. NumberFormat.abbreviate(-n)
	end
	if n < 1000 then
		return tostring(math.floor(n))
	end

	local tier = math.floor(math.log(n, 10) / 3)
	if tier >= #SUFFIXES then
		-- Past the suffix list: fall back to scientific notation.
		return string.format("%.2e", n)
	end

	-- Values are truncated, never rounded up, so the UI never shows more cash
	-- than the player has. Float error in the log can still leave scaled at
	-- 1000 (for n = 1e6, say); move to the next suffix then.
	local scaled = n / 10 ^ (tier * 3)
	local decimals = if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2
	local factor = 10 ^ decimals
	-- The tiny epsilon stops 1.23 * 100 = 122.9999... from truncating to 1.22.
	local rounded = math.floor(scaled * factor + 1e-9) / factor
	if rounded >= 1000 and tier + 1 < #SUFFIXES then
		tier += 1
		rounded = rounded / 1000
		decimals = 2
	end
	return trimZeros(string.format(`%.{decimals}f`, rounded)) .. SUFFIXES[tier + 1]
end

-- "1,234,567" style, for exact values in tooltips.
function NumberFormat.commas(n: number): string
	local whole = tostring(math.floor(math.abs(n)))
	local formatted = string.reverse((string.gsub(string.reverse(whole), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return (if n < 0 then "-" else "") .. formatted
end

-- "2h 05m", "45m 10s", "12s" for durations.
function NumberFormat.duration(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	local secs = total % 60
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %02ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

return NumberFormat
