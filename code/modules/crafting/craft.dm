/datum/personal_crafting
	var/busy
	var/viewing_category = 1 //typical powergamer starting on the Weapons tab
	var/viewing_subcategory = 1
	var/list/categories = list(
				CAT_WEAPONRY = list(
					CAT_WEAPON,
					CAT_AMMO,
				),
				CAT_ROBOT = CAT_NONE,
				CAT_MISC = CAT_NONE,
				CAT_PRIMAL = CAT_NONE,
				CAT_FOOD = list(
					CAT_BREAD,
					CAT_BURGER,
					CAT_CAKE,
					CAT_EGG,
					CAT_MEAT,
					CAT_MISCFOOD,
					CAT_PASTRY,
					CAT_PIE,
					CAT_PIZZA,
					CAT_SALAD,
					CAT_SANDWICH,
					CAT_SOUP,
					CAT_SPAGHETTI,
				),
				CAT_DRINK = CAT_NONE,
				CAT_CLOTHING = CAT_NONE,
			)

	var/cur_category = CAT_NONE
	var/cur_subcategory = CAT_NONE
	var/datum/action/innate/crafting/button
	var/display_craftable_only = FALSE
	var/display_compact = TRUE

/*	This is what procs do:
	get_environment - gets a list of things accessable for crafting by user
	get_surroundings - takes a list of things and makes a list of key-types to values-amounts of said type in the list
	check_contents - takes a recipe and a key-type list and checks if said recipe can be done with available stuff
	check_tools - takes recipe, a key-type list, and a user and checks if there are enough tools to do the stuff, checks bugs one level deep
	construct_item - takes a recipe and a user, call all the checking procs, calls do_after, checks all the things again, calls del_reqs, creates result, calls CheckParts of said result with argument being list returned by deel_reqs
	del_reqs - takes recipe and a user, loops over the recipes reqs var and tries to find everything in the list make by get_environment and delete it/add to parts list, then returns the said list
*/

/**
  * Check that the contents of the recipe meet the requirements.
  *
  * user: The /mob that initated the crafting.
  * R: The /datum/crafting_recipe being attempted.
  * contents: List of items to search for R's reqs.
  */
/datum/personal_crafting/proc/check_contents(atom/a, datum/crafting_recipe/R, list/contents)
	var/list/item_instances = contents["instances"]
	contents = contents["other"]

	var/list/requirements_list = list()

	// Process all requirements
	for(var/requirement_path in R.reqs)
		// Check we have the appropriate amount available in the contents list
		var/needed_amount = R.reqs[requirement_path]
		for(var/content_item_path in contents)
			if(!ispath(content_item_path, requirement_path))
				continue

			needed_amount -= contents[content_item_path]
			if(needed_amount <= 0)
				break

		if(needed_amount > 0)
			return FALSE

		// Store the instances of what we will use for R.check_requirements() for requirement_path
		var/list/instances_list = list()
		for(var/instance_path in item_instances)
			if(ispath(instance_path, requirement_path))
				instances_list += item_instances[instance_path]

		requirements_list[requirement_path] = instances_list

	for(var/requirement_path in R.chem_catalysts)
		if(contents[requirement_path] < R.chem_catalysts[requirement_path])
			return FALSE

	return TRUE

/datum/personal_crafting/proc/get_environment(atom/a, radius_range = 1)
	. = list()

	if(!isturf(a.loc))
		return

	for(var/atom/movable/AM in range(radius_range, a))
		. += AM


/datum/personal_crafting/proc/get_surroundings(atom/a)
	. = list()
	.["tool_behaviour"] = list()
	.["other"] = list()
	.["instances"] = list()
	for(var/obj/item/I in get_environment(a))
		if(.["instances"][I.type])
			.["instances"][I.type] += I
		else
			.["instances"][I.type] = list(I)
		if(istype(I, /obj/item/stack))
			var/obj/item/stack/S = I
			.["other"][I.type] += S.amount
		else if(get_tool_behaviour(I))
			.["tool_behaviour"] += get_tool_behaviour(I)
			.["other"][I.type] += 1
		else
			if(istype(I, /obj/item/reagent_containers))
				var/obj/item/reagent_containers/RC = I
				for(var/datum/reagent/A in RC.reagents.reagent_list)
					.["other"][A.type] += A.volume
			.["other"][I.type] += 1

/datum/personal_crafting/proc/check_tools(atom/a, datum/crafting_recipe/R, list/contents)
	if(!R.tools.len)
		return TRUE
	var/list/possible_tools = list()
	var/list/present_qualities = list()
	present_qualities |= contents["tool_behaviour"]
	for(var/obj/item/I in a.contents)
		if(istype(I, /obj/item/storage))
			for(var/obj/item/SI in I.contents)
				possible_tools += SI.type
				if(get_tool_behaviour(SI))
					present_qualities.Add(get_tool_behaviour(SI))

		possible_tools += I.type

		if(get_tool_behaviour(I))
			present_qualities.Add(get_tool_behaviour(I))

	possible_tools |= contents["other"]

	main_loop:
		for(var/A in R.tools)
			if(A in present_qualities)
				continue
			else
				for(var/I in possible_tools)
					if(ispath(I, A))
						continue main_loop
			return FALSE
	return TRUE

/datum/personal_crafting/proc/get_tool_behaviour(var/obj/item/I)
	var/tool_behaviour
	if(istype(I, /obj/item/wrench))
		tool_behaviour = "wrench"
	else if(istype(I, /obj/item/screwdriver))
		tool_behaviour = "screwdriver"
	else if(istype(I, /obj/item/wirecutters))
		tool_behaviour = "wirecutters"
	else if(istype(I, /obj/item/weldingtool))
		tool_behaviour = "welder"
	else if(istype(I, /obj/item/crowbar))
		tool_behaviour = "crowbar"
	else
		return FALSE

	return tool_behaviour

/datum/personal_crafting/proc/construct_item(atom/a, datum/crafting_recipe/R)
	var/list/contents = get_surroundings(a)
	if(check_contents(a, R, contents))
		if(check_tools(a, R, contents))
			//If we're a mob we'll try a do_after; non mobs will instead instantly construct the item
			if(ismob(a) && !do_after(a, R.time, target = a))
				return "."
			contents = get_surroundings(a)
			if(!check_contents(a, R, contents))
				return ", missing component."
			if(!check_tools(a, R, contents))
				return ", missing tool."
			var/list/parts = del_reqs(R, a)
			var/atom/movable/I = new R.result (get_turf(a.loc))
			I.CheckParts(parts, R)
			return I //Send the item back to whatever called this proc so it can handle whatever it wants to do with the new item
		return ", missing tool."
	return ", missing component."

/datum/personal_crafting/proc/construct_item_ui(mob/user, datum/crafting_recipe/TR)
	var/atom/movable/result = construct_item(user, TR)
	if(!istext(result)) //We made an item and didn't get a fail message
		if(ismob(user) && isitem(result)) //In case the user is actually possessing a non mob like a machine
			user.put_in_hands(result)
		else
			result.forceMove(user.drop_location())
		to_chat(user, "<span class='notice'>[TR.name] constructed.</span>")
	else
		to_chat(user, "<span class='warning'>Construction failed[result]</span>")
	busy = FALSE
	SStgui.update_uis(src)


/*Del reqs works like this:

	Loop over reqs var of the recipe
	Set var amt to the value current cycle req is pointing to, its amount of type we need to delete
	Get var/surroundings list of things accessable to crafting by get_environment()
	Check the type of the current cycle req
		If its reagent then do a while loop, inside it try to locate() reagent containers, inside such containers try to locate needed reagent, if there isn't remove thing from surroundings
			If there is enough reagent in the search result then delete the needed amount, create the same type of reagent with the same data var and put it into deletion list
			If there isn't enough take all of that reagent from the container, put into deletion list, substract the amt var by the volume of reagent, remove the container from surroundings list and keep searching
			While doing above stuff check deletion list if it already has such reagnet, if yes merge instead of adding second one
		If its stack check if it has enough amount
			If yes create new stack with the needed amount and put in into deletion list, substract taken amount from the stack
			If no put all of the stack in the deletion list, substract its amount from amt and keep searching
			While doing above stuff check deletion list if it already has such stack type, if yes try to merge them instead of adding new one
		If its anything else just locate() in in the list in a while loop, each find --s the amt var and puts the found stuff in deletion loop

	Then do a loop over parts var of the recipe
		Do similar stuff to what we have done above, but now in deletion list, until the parts conditions are satisfied keep taking from the deletion list and putting it into parts list for return

	After its done loop over deletion list and delete all the shit that wasn't taken by parts loop

	del_reqs return the list of parts resulting object will receive as argument of CheckParts proc, on the atom level it will add them all to the contents, on all other levels it calls ..() and does whatever is needed afterwards but from contents list already
*/

/datum/personal_crafting/proc/del_reqs(datum/crafting_recipe/R, atom/a)
	var/list/surroundings
	var/list/Deletion = list()
	. = list()
	var/data
	var/amt
	main_loop:
		for(var/A in R.reqs)
			amt = R.reqs[A]
			surroundings = get_environment(a)
			surroundings -= Deletion
			if(ispath(A, /datum/reagent))
				var/datum/reagent/RG = new A
				var/datum/reagent/RGNT
				while(amt > 0)
					var/obj/item/reagent_containers/RC = locate() in surroundings
					RG = RC.reagents.get_reagent(A)
					if(RG)
						if(!locate(RG.type) in Deletion)
							Deletion += new RG.type()
						if(RG.volume > amt)
							RG.volume -= amt
							data = RG.data
							RC.reagents.conditional_update(RC)
							RG = locate(RG.type) in Deletion
							RG.volume = amt
							RG.data += data
							continue main_loop
						else
							surroundings -= RC
							amt -= RG.volume
							RC.reagents.reagent_list -= RG
							RC.reagents.conditional_update(RC)
							RGNT = locate(RG.type) in Deletion
							RGNT.volume += RG.volume
							RGNT.data += RG.data
							qdel(RG)
						RC.on_reagent_change()
					else
						surroundings -= RC
			else if(ispath(A, /obj/item/stack))
				var/obj/item/stack/S
				var/obj/item/stack/SD
				while(amt > 0)
					S = locate(A) in surroundings
					if(S.amount >= amt)
						if(!locate(S.type) in Deletion)
							SD = new S.type()
							Deletion += SD
						S.use(amt)
						SD = locate(S.type) in Deletion
						SD.amount += amt
						continue main_loop
					else
						amt -= S.amount
						if(!locate(S.type) in Deletion)
							Deletion += S
						else
							data = S.amount
							S = locate(S.type) in Deletion
							S.add(data)
						surroundings -= S
			else
				var/atom/movable/I
				while(amt > 0)
					I = locate(A) in surroundings
					Deletion += I
					surroundings -= I
					amt--
	var/list/partlist = list(R.parts.len)
	for(var/M in R.parts)
		partlist[M] = R.parts[M]
	for(var/A in R.parts)
		if(istype(A, /datum/reagent))
			var/datum/reagent/RG = locate(A) in Deletion
			if(RG.volume > partlist[A])
				RG.volume = partlist[A]
			. += RG
			Deletion -= RG
			continue
		else if(istype(A, /obj/item/stack))
			var/obj/item/stack/ST = locate(A) in Deletion
			if(ST.amount > partlist[A])
				ST.amount = partlist[A]
			. += ST
			Deletion -= ST
			continue
		else
			while(partlist[A] > 0)
				var/atom/movable/AM = locate(A) in Deletion
				. += AM
				Deletion -= AM
				partlist[A] -= 1
	while(Deletion.len)
		var/DL = Deletion[Deletion.len]
		Deletion.Cut(Deletion.len)
		qdel(DL)

/datum/personal_crafting/ui_state(mob/user)
	return GLOB.not_incapacitated_turf_state

//For the UI related things we're going to assume the user is a mob rather than typesetting it to an atom as the UI isn't generated if the parent is an atom
/datum/personal_crafting/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		cur_category = categories[1]
		if(islist(categories[cur_category]))
			var/list/subcats = categories[cur_category]
			cur_subcategory = subcats[1]
		else
			cur_subcategory = CAT_NONE
		ui = new(user, src, "PersonalCrafting")
		ui.open()

/datum/personal_crafting/ui_data(mob/user)
	var/list/data = list()
	data["busy"] = busy
	data["category"] = cur_category
	data["subcategory"] = cur_subcategory
	data["display_craftable_only"] = display_craftable_only
	data["display_compact"] = display_compact

	var/list/surroundings = get_surroundings(user)
	var/list/craftability = list()
	for(var/rec in GLOB.crafting_recipes)
		var/datum/crafting_recipe/R = rec

		if((R.category != cur_category))
			continue

		craftability["[REF(R)]"] = check_contents(user, R, surroundings)

	data["craftability"] = craftability
	return data

/datum/personal_crafting/ui_static_data(mob/user)
	var/list/data = list()

	var/list/crafting_recipes = list()
	for(var/rec in GLOB.crafting_recipes)
		var/datum/crafting_recipe/R = rec

		if(R.name == "" || R.category == CAT_NONE) //This is one of the invalid parents that sneaks in
			continue

		if(isnull(crafting_recipes[R.category]))
			crafting_recipes[R.category] = list()

		crafting_recipes[R.category] += list(build_recipe_data(R))

	data["crafting_recipes"] = crafting_recipes
	return data

/datum/personal_crafting/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("make")
			if(busy) // Prevent potentially crafting multiple things at once
				return
			var/mob/user = usr
			var/datum/crafting_recipe/TR = locate(params["recipe"]) in GLOB.crafting_recipes
			if(!TR)
				return
			busy = TRUE
			. = TRUE
			INVOKE_ASYNC(src, .proc/construct_item_ui, user, TR)
		if("toggle_recipes")
			display_craftable_only = !display_craftable_only
			. = TRUE
		if("toggle_compact")
			display_compact = !display_compact
			. = TRUE
		if("set_category")
			cur_category = params["category"]
			cur_subcategory = params["subcategory"] || ""
			. = TRUE

/datum/personal_crafting/proc/build_recipe_data(datum/crafting_recipe/R)
	var/list/data = list()
	data["name"] = R.name
	data["ref"] = "[REF(R)]"
	var/req_text = ""
	var/tool_text = ""
	var/catalyst_text = ""

	for(var/a in R.reqs)
		//We just need the name, so cheat-typecast to /atom for speed (even tho Reagents are /datum they DO have a "name" var)
		//Also these are typepaths so sadly we can't just do "[a]"
		var/atom/A = a
		req_text += " [R.reqs[A]] [initial(A.name)],"
	req_text = replacetext(req_text,",","",-1)
	data["req_text"] = req_text

	for(var/a in R.chem_catalysts)
		var/atom/A = a //cheat-typecast
		catalyst_text += " [R.chem_catalysts[A]] [initial(A.name)],"
	catalyst_text = replacetext(catalyst_text,",","",-1)
	data["catalyst_text"] = catalyst_text

	for(var/a in R.tools)
		if(ispath(a, /obj/item))
			var/obj/item/b = a
			tool_text += " [initial(b.name)],"
		else
			tool_text += " [a],"
	tool_text = replacetext(tool_text,",","",-1)
	data["tool_text"] = tool_text

	return data
