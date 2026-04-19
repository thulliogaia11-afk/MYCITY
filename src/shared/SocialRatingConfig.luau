local SocialRatingConfig = {}

SocialRatingConfig.TIERS = {
	{ name = "Annoying", minScore = 0 },
	{ name = "Average", minScore = 50 },
	{ name = "Likable", minScore = 120 },
	{ name = "Very Likable", minScore = 220 },
	{ name = "Famous", minScore = 360 },
	{ name = "Superstar", minScore = 600 },
}

SocialRatingConfig.DRINK_SOCIAL_POINTS = {
	water = 1,
	soda = 1,
	juice = 1,
	vodka = 2,
	whiskey = 2,
	energy_drink = 2,
	cocktails = 2,
	champagne = 3,
}

SocialRatingConfig.DRINK_WINDOW_CAP = 10
SocialRatingConfig.DRINK_WINDOW_SECONDS = 600

return SocialRatingConfig
