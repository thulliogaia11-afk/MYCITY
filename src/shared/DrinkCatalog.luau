local DrinkCatalog = {}

export type DrinkDefinition = {
	id: string,
	displayName: string,
	price: number,
}

local DRINK_DEFINITIONS: { [string]: DrinkDefinition } = {
	water = { id = "water", displayName = "Água", price = 5 },
	soda = { id = "soda", displayName = "Refri", price = 8 },
	juice = { id = "juice", displayName = "Suco", price = 10 },
	vodka = { id = "vodka", displayName = "Vodka", price = 20 },
	whiskey = { id = "whiskey", displayName = "Whiskey", price = 35 },
	champagne = { id = "champagne", displayName = "Champagne", price = 60 },
	energy_drink = { id = "energy_drink", displayName = "Energético", price = 15 },
	cocktails = { id = "cocktails", displayName = "Coquetéis", price = 25 },
}

local CLUB_DRINKS: { [string]: { string } } = {
	Club_Bronze = { "water", "soda", "vodka" },
	Club_Silver = { "water", "soda", "juice", "vodka" },
	Club_Gold = { "water", "soda", "vodka", "juice", "whiskey" },
	Club_Diamond = { "water", "soda", "juice", "vodka", "whiskey", "champagne", "energy_drink", "cocktails" },
}

function DrinkCatalog.GetDrinkDefinition(drinkId: string): DrinkDefinition?
	return DRINK_DEFINITIONS[drinkId]
end

function DrinkCatalog.GetAllowedDrinkIds(clubName: string): { string }
	local ids = CLUB_DRINKS[clubName]
	if not ids then
		return {}
	end
	return table.clone(ids)
end

function DrinkCatalog.IsDrinkAllowed(clubName: string, drinkId: string): boolean
	for _, allowedId in DrinkCatalog.GetAllowedDrinkIds(clubName) do
		if allowedId == drinkId then
			return true
		end
	end
	return false
end

function DrinkCatalog.BuildMenuRows(clubName: string): { { id: string, name: string, price: number } }
	local rows = {}
	for _, drinkId in DrinkCatalog.GetAllowedDrinkIds(clubName) do
		local def = DRINK_DEFINITIONS[drinkId]
		if def then
			table.insert(rows, {
				id = def.id,
				name = def.displayName,
				price = def.price,
			})
		end
	end
	return rows
end

return DrinkCatalog
