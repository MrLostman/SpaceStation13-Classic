/atom/var/CanAtmosPass = ATMOS_PASS_YES
/atom/var/CanAtmosPassVertical = ATMOS_PASS_YES

/atom/proc/CanAtmosPass(turf/T)
	switch (CanAtmosPass)
		if (ATMOS_PASS_PROC)
			return ATMOS_PASS_YES
		if (ATMOS_PASS_DENSITY)
			return !density
		else
			return CanAtmosPass

/turf/CanAtmosPass = ATMOS_PASS_NO
/turf/CanAtmosPassVertical = ATMOS_PASS_NO

/turf/open/CanAtmosPass = ATMOS_PASS_PROC
/turf/open/CanAtmosPassVertical = ATMOS_PASS_PROC

/turf/open/CanAtmosPass(turf/T)
	. = TRUE
	if(blocks_air || T.blocks_air)
		. = FALSE
	if (T == src)
		return .
	for(var/obj/O in contents+T.contents)
		var/turf/other = (O.loc == src ? T : src)
		if(!(CANATMOSPASS(O, other)))
			. = FALSE

/turf/proc/update_conductivity(turf/T)
	var/dir = get_dir(src, T)
	var/opp = REVERSE_DIR(dir)

	if(T == src)
		return

	//all these must be above zero for auxmos to even consider them
	if(!thermal_conductivity || !heat_capacity || !T.thermal_conductivity || !T.heat_capacity)
		conductivity_blocked_directions |= dir
		T.conductivity_blocked_directions |= opp
		return

	for(var/obj/O in contents+T.contents)
		if(O.BlockThermalConductivity(opp)) 	//the direction and open/closed are already checked on CanAtmosPass() so there are no arguments
			conductivity_blocked_directions |= dir
			T.conductivity_blocked_directions |= opp

/atom/movable/proc/BlockThermalConductivity() // Objects that don't let heat through.
	return FALSE

/turf/proc/CalculateAdjacentTurfs()
	var/canpass = CANATMOSPASS(src, src)
	conductivity_blocked_directions = 0

	var/src_contains_firelock = 1
	if(locate(/obj/machinery/door/firedoor) in src)
		src_contains_firelock |= 2

	for(var/direction in GLOB.cardinals)
		var/turf/T = get_step(src, direction)
		if(!istype(T))
			conductivity_blocked_directions |= direction
			continue

		var/other_contains_firelock = 1
		if(locate(/obj/machinery/door/firedoor) in T)
			other_contains_firelock |= 2

		update_conductivity(T)

		if(isopenturf(T) && !(blocks_air || T.blocks_air) && (canpass && CANATMOSPASS(T, src)))
			LAZYINITLIST(atmos_adjacent_turfs)
			LAZYINITLIST(T.atmos_adjacent_turfs)
			atmos_adjacent_turfs[T] = other_contains_firelock | src_contains_firelock
			T.atmos_adjacent_turfs[src] = src_contains_firelock
		else
			if (atmos_adjacent_turfs)
				atmos_adjacent_turfs -= T
			if (T.atmos_adjacent_turfs)
				T.atmos_adjacent_turfs -= src
			UNSETEMPTY(T.atmos_adjacent_turfs)
		T.__update_auxtools_turf_adjacency_info(isspaceturf(T.baseturf))
	UNSETEMPTY(atmos_adjacent_turfs)
	src.atmos_adjacent_turfs = atmos_adjacent_turfs
	__update_auxtools_turf_adjacency_info(isspaceturf(baseturf))

/turf/proc/set_sleeping(should_sleep)

/turf/proc/__update_auxtools_turf_adjacency_info()

//returns a list of adjacent turfs that can share air with this one.
//alldir includes adjacent diagonal tiles that can share
//	air with both of the related adjacent cardinal tiles
/turf/proc/GetAtmosAdjacentTurfs(alldir = 0)
	var/adjacent_turfs
	if (atmos_adjacent_turfs)
		adjacent_turfs = atmos_adjacent_turfs.Copy()
	else
		adjacent_turfs = list()

	if (!alldir)
		return adjacent_turfs

	var/turf/curloc = src

	for (var/direction in GLOB.diagonals)
		var/matchingDirections = 0
		var/turf/S = get_step(curloc, direction)
		if(!S)
			continue

		for (var/checkDirection in GLOB.cardinals)
			var/turf/checkTurf = get_step(S, checkDirection)
			if(!S.atmos_adjacent_turfs || !S.atmos_adjacent_turfs[checkTurf])
				continue

			if (adjacent_turfs[checkTurf])
				matchingDirections++

			if (matchingDirections >= 2)
				adjacent_turfs += S
				break

	return adjacent_turfs

/atom/proc/air_update_turf()
	if(!isturf(loc))
		return
	var/turf/T = get_turf(loc)
	T.air_update_turf()

/turf/air_update_turf()
	CalculateAdjacentTurfs()

/atom/movable/proc/move_update_air(turf/T)
    if(isturf(T))
        T.air_update_turf()
    air_update_turf()

/atom/proc/atmos_spawn_air(text) //because a lot of people loves to copy paste awful code lets just make an easy proc to spawn your plasma fires
	var/turf/open/T = get_turf(src)
	if(!istype(T))
		return
	T.atmos_spawn_air(text)

/turf/open/atmos_spawn_air(text)
	if(!text || !air)
		return

	var/datum/gas_mixture/G = new
	G.parse_gas_string(text)
	assume_air(G)

