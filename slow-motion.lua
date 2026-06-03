if slowmotion then
	pcall(event.unregister, event.tick, slowmotion.tick)
end
slowmotion = setmetatable({}, {
	__call = function(self, down_factor)
		if self.tick then
			event.unregister(event.tick, self.tick)
		end
		self.tick = nil
		if not down_factor then
			if self.old_pause then
				tpt.set_pause(self.old_pause)
				self.old_pause = nil
			end
			return
		end
		self.old_pause = tpt.set_pause()
		tpt.set_pause(1)
		local counter = 0
		self.tick = function()
			counter = counter + 1
			if counter >= down_factor then
				sim.framerender(1)
				counter = 0
			end
		end
		event.register(event.tick, self.tick)
	end,
})
