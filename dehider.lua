for name, stuff in pairs(tpt.el) do
	pcall(function()
		if elem.element(stuff.id) then
			if elem.property(stuff.id, "MenuSection") >= elem.SC_DECO then
				elem.property(stuff.id, "MenuSection", elem.SC_SPECIAL)
			end
			elem.property(stuff.id, "MenuVisible", 1)
		end
	end)
end
