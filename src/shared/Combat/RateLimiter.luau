--!strict
--[[
	RateLimiter
	Token bucket, one bucket per key (usually a Player).

	Each key holds up to `burst` tokens. Tokens refill at `ratePerSecond`.
	A request costs one token. With no token left, the request is dropped.
	This allows short bursts (a fast combo) but blocks remote spam.

	The clock is injected, so tests can control time.
]]

type Bucket = {
	tokens: number,
	updatedAt: number,
}

export type RateLimiter = {
	take: (self: RateLimiter, key: any) -> boolean,
	peek: (self: RateLimiter, key: any) -> number,
	remove: (self: RateLimiter, key: any) -> (),
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(ratePerSecond: number, burst: number, clock: (() -> number)?): RateLimiter
	assert(ratePerSecond > 0, "ratePerSecond must be positive")
	assert(burst >= 1, "burst must be at least 1")
	local self = setmetatable({
		_rate = ratePerSecond,
		_burst = burst,
		_clock = clock or os.clock,
		_buckets = {} :: { [any]: Bucket },
	}, RateLimiter)
	return self :: any
end

function RateLimiter._refill(self: any, key: any): Bucket
	local now = self._clock()
	local bucket: Bucket? = self._buckets[key]
	if bucket == nil then
		local fresh = { tokens = self._burst, updatedAt = now }
		self._buckets[key] = fresh
		return fresh
	end
	local elapsed = math.max(0, now - bucket.updatedAt)
	bucket.tokens = math.min(self._burst, bucket.tokens + elapsed * self._rate)
	bucket.updatedAt = now
	return bucket
end

-- Spends one token. Returns false when the key is over its limit.
function RateLimiter.take(self: any, key: any): boolean
	local bucket = self:_refill(key)
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- Tokens available right now (for debugging and tests).
function RateLimiter.peek(self: any, key: any): number
	return self:_refill(key).tokens
end

-- Call on PlayerRemoving so the table does not grow forever.
function RateLimiter.remove(self: any, key: any)
	self._buckets[key] = nil
end

return RateLimiter
