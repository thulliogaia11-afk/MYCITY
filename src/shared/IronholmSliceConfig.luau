local IronholmSliceConfig = {}

IronholmSliceConfig.Slice = {
	cityId = "ironholm",
	displayName = "Ironholm",
	theme = "Power, money, ambition",
}

IronholmSliceConfig.Aspiration = {
	id = "first_apartment_ironholm",
	title = "First Apartment in Ironholm",
	targetCost = 1200,
	description = "Secure your first apartment in Ironholm and stop feeling like a visitor in a city built for winners.",
	progressCopy = "Keep stacking cash and close the gap to your first apartment.",
	completionCopy = "You can afford your first apartment in Ironholm. Time to claim your place in the city.",
}

IronholmSliceConfig.StarterFlow = {
	starterJobId = "courier",
	starterMissionId = "courier_pickup_delivery_01",
	starterDailyIds = {
		"daily_complete_any_two",
		"daily_earn_250",
		"daily_complete_one_perfect_run",
	},
	defaultObjectiveText = "Ironholm rewards motion. Open your mission panel, take the courier run, and start building real momentum.",
}

IronholmSliceConfig.JobOrder = {
	"courier",
	"corporate_assistant",
	"property_sales_trainee",
}

IronholmSliceConfig.Jobs = {
	courier = {
		id = "courier",
		displayName = "Courier",
		shortDescription = "Handle fast deliveries across Ironholm and prove you can move on time under pressure.",
		category = "logistics",
		unlockOrder = 1,
		starterObjectiveText = "Pick up your first delivery and get it across Ironholm without wasting time.",
		incomeBand = "entry",
	},
	corporate_assistant = {
		id = "corporate_assistant",
		displayName = "Corporate Assistant",
		shortDescription = "Support Ironholm's office floor with quick runs, polished timing, and zero mistakes.",
		category = "corporate",
		unlockOrder = 2,
		starterObjectiveText = "Step into the office, keep leadership moving, and finish support tasks cleanly.",
		incomeBand = "entry_plus",
	},
	property_sales_trainee = {
		id = "property_sales_trainee",
		displayName = "Property Sales Trainee",
		shortDescription = "Learn the city's property game by guiding visits and helping close starter listings.",
		category = "property",
		unlockOrder = 3,
		starterObjectiveText = "Show a listing, speak with confidence, and turn your first property lead into progress.",
		incomeBand = "aspirational_entry",
	},
}

IronholmSliceConfig.Missions = {
	courier_pickup_delivery_01 = {
		id = "courier_pickup_delivery_01",
		jobId = "courier",
		title = "Pickup and Delivery Run",
		shortDescription = "Collect a parcel from the commerce desk and deliver it to a client in Ironholm.",
		objectiveText = "Pick up the parcel at the commerce desk and deliver it to the Riverside client.",
		rewardMoney = 45,
		rewardLabel = "$45 payout",
		missionType = "pickup_delivery",
		order = 1,
		earlyGameWeight = 10,
		suitableForStarter = true,
	},
	courier_priority_drop_01 = {
		id = "courier_priority_drop_01",
		jobId = "courier",
		title = "Priority Drop",
		shortDescription = "Handle a time-sensitive envelope for an office contact before the window closes.",
		objectiveText = "Grab the priority envelope and make the downtown drop before the client leaves.",
		rewardMoney = 60,
		rewardLabel = "$60 priority payout",
		missionType = "priority_delivery",
		order = 2,
		earlyGameWeight = 8,
		suitableForStarter = true,
	},
	assistant_file_run_01 = {
		id = "assistant_file_run_01",
		jobId = "corporate_assistant",
		title = "Executive File Run",
		shortDescription = "Move signed files from reception to the executive office without delays.",
		objectiveText = "Collect the signed file packet at reception and deliver it to the executive office upstairs.",
		rewardMoney = 55,
		rewardLabel = "$55 office payout",
		missionType = "office_run",
		order = 1,
		earlyGameWeight = 10,
		suitableForStarter = true,
	},
	assistant_boardroom_support_01 = {
		id = "assistant_boardroom_support_01",
		jobId = "corporate_assistant",
		title = "Boardroom Support",
		shortDescription = "Set up the boardroom and finalize a last-minute support request before the meeting starts.",
		objectiveText = "Prepare the boardroom materials and confirm the room is ready for the executive meeting.",
		rewardMoney = 70,
		rewardLabel = "$70 support payout",
		missionType = "meeting_support",
		order = 2,
		earlyGameWeight = 7,
		suitableForStarter = true,
	},
	property_listing_visit_01 = {
		id = "property_listing_visit_01",
		jobId = "property_sales_trainee",
		title = "Starter Listing Visit",
		shortDescription = "Guide a client through a starter apartment and keep the showing on script.",
		objectiveText = "Meet the client at the listing and walk them through the apartment with confidence.",
		rewardMoney = 80,
		rewardLabel = "$80 trainee payout",
		missionType = "listing_visit",
		order = 1,
		earlyGameWeight = 9,
		suitableForStarter = true,
	},
	property_intro_close_01 = {
		id = "property_intro_close_01",
		jobId = "property_sales_trainee",
		title = "Intro Close",
		shortDescription = "Follow up on a warm lead and secure an introductory property close for the office.",
		objectiveText = "Present the starter property terms and close the introductory deal for the agency.",
		rewardMoney = 110,
		rewardLabel = "$110 close bonus",
		missionType = "intro_close",
		order = 2,
		earlyGameWeight = 6,
		suitableForStarter = true,
	},
}

IronholmSliceConfig.Dailies = {
	{
		id = "daily_complete_any_two",
		title = "Momentum Builder",
		shortDescription = "Complete any 2 jobs in Ironholm today.",
		objectiveText = "Finish 2 Ironholm jobs today.",
		rewardMoney = 90,
		rewardLabel = "$90 daily bonus",
		trackedStat = "jobs_completed",
		goal = 2,
		order = 1,
	},
	{
		id = "daily_earn_250",
		title = "Cash Flow",
		shortDescription = "Earn your first serious chunk of money in the city.",
		objectiveText = "Earn $250 from work today.",
		rewardMoney = 120,
		rewardLabel = "$120 daily bonus",
		trackedStat = "money_earned",
		goal = 250,
		order = 2,
	},
	{
		id = "daily_complete_one_perfect_run",
		title = "Clean Execution",
		shortDescription = "Finish one mission without backing out or failing the task.",
		objectiveText = "Complete 1 mission cleanly today.",
		rewardMoney = 75,
		rewardLabel = "$75 daily bonus",
		trackedStat = "clean_missions_completed",
		goal = 1,
		order = 3,
	},
}

IronholmSliceConfig.ObjectiveText = {
	activeMissionLabel = "Active mission",
	dailyMissionsLabel = "Daily missions",
	aspirationLabel = "Next ambition",
	noActiveMissionFallback = "No active mission. Open the mission panel and pick your next move.",
	missionProgressPrefix = "Current objective:",
	dailyProgressPrefix = "Daily progress:",
	aspirationProgressPrefix = "Apartment goal:",
}

return IronholmSliceConfig
