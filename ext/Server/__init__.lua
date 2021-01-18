local materialGrid = nil
local materialContainer = nil
local DamageCheckerConfig = {
	['ShowDebug'] = false,
	['ShowDebugOnMisMatch'] = false,
	['WarnOnMisMatch'] = true,
	['FixDoubleDamage'] = true,
	['WarnOnDoubleDamage'] = true,
	['WarnOnWrongPellets'] = true,
	['EnforceExpectedDamage'] = false,
	['DamageTolerance'] = 1.0,
}

for conVar, conValue in pairs(DamageCheckerConfig) do
	RCON:RegisterCommand('vu-mvdamagechecker.'..conVar, RemoteCommandFlag.RequiresLogin, function(command, args, loggedIn)
		local varName = command:split('.')[2]
		
		if (args ~= nil and args[1] ~= nil) then
			if (varName == 'DamageTolerance') then
				DamageCheckerConfig[varName] = tonumber(args[1]) or 1.0
			else
				DamageCheckerConfig[varName] = (args[1] == '1' or args[1]:lower() == 'true')
			end
		end

		return {'OK', tostring(DamageCheckerConfig[varName])}
	end)
end

Hooks:Install('Soldier:Damage', 1, function(hook, soldier, info, giverInfo)
	if giverInfo == nil or giverInfo.weaponFiring == nil or giverInfo.giver == nil then
		return
	end
	if giverInfo.assist ~= nil then 
		return 
	end
	if info.isBulletDamage == false then
		return
	end

	local currentWeapon = giverInfo.giver.soldier.weaponsComponent.currentWeapon -- SoldierWeapon
	local fireData = WeaponFiringData(currentWeapon.weaponFiring.data) or WeaponFiringData(giverInfo.weaponFiring)
	if currentWeapon.weaponModifier.weaponFiringDataModifier ~= nil and currentWeapon.weaponModifier.weaponFiringDataModifier.weaponFiring ~= nil then
		fireData = WeaponFiringData(currentWeapon.weaponModifier.weaponFiringDataModifier.weaponFiring)
	end

	-- grab number of shells from firing function, checking for a modifier first
	local weaponNumBullets = 1
	if currentWeapon.weaponModifier.weaponShotModifier ~= nil and currentWeapon.weaponModifier.weaponShotModifier.numberOfBulletsPerShell ~= nil then
		weaponNumBullets = currentWeapon.weaponModifier.weaponShotModifier.numberOfBulletsPerShell
	else
		weaponNumBullets = fireData.primaryFire.shot.numberOfBulletsPerShell
	end

	-- grab bullet instance from weapon, checking for a modifier first, then for a secondary projectile, then the standard projectile
	local bullet = nil
	if currentWeapon.weaponModifier.weaponProjectileModifier ~= nil and currentWeapon.weaponModifier.weaponProjectileModifier.projectileData ~= nil then
		bullet = BulletEntityData(currentWeapon.weaponModifier.weaponProjectileModifier.projectileData)
	elseif fireData.primaryFire.shot.secondaryProjectile ~= nil then
		bullet = BulletEntityData(fireData.primaryFire.shot.secondaryProjectile)
	else
		bullet = BulletEntityData(fireData.primaryFire.shot.projectileData)
	end

	-- get bullet material
	local bulletMaterialMapIndex = bullet.materialPair.physicsPropertyIndex
	if bulletMaterialMapIndex < 0 then
		bulletMaterialMapIndex = 256 + bulletMaterialMapIndex
	end
	local bulletMaterial = materialGrid.materialIndexMap[bulletMaterialMapIndex+1]+1

	-- get damaged material
	local damagedMaterialMapIndex = MaterialContainerPair(info.damagedMaterial).physicsPropertyIndex
	if damagedMaterialMapIndex < 0 then
		damagedMaterialMapIndex = 256 + damagedMaterialMapIndex
	end

	local protectionMultiplier = 1.0
	local penetrationMultiplier = 1.0
	local protectionThreshold = 0.0
	local materialGridItems = MaterialInteractionGridRow(materialGrid.interactionGrid[materialGrid.materialIndexMap[damagedMaterialMapIndex+1]+1]).items

	local physicsPropertyList = materialGridItems[bulletMaterial].physicsPropertyProperties
	if (#physicsPropertyList < 1) then
		return
	end
	for i=1, #physicsPropertyList do
		if (physicsPropertyList[i]:Is('MaterialRelationDamageData')) then
			local relationData = MaterialRelationDamageData(physicsPropertyList[i])
			protectionMultiplier = relationData.damageProtectionMultiplier
			penetrationMultiplier = relationData.damagePenetrationMultiplier
			protectionThreshold = relationData.damageProtectionThreshold
		end
	end
	
	local expectedActualDamage = bullet.startDamage * protectionMultiplier -- shortest range, full damage
	local shotDistance = info.position:Distance(info.origin)

	if (shotDistance >= bullet.damageFalloffEndDistance) then -- long range, full end damage

		expectedActualDamage = bullet.endDamage * protectionMultiplier

	elseif (shotDistance > bullet.damageFalloffStartDistance) then -- mid range, scaled damage

		local distanceScaleRange = (bullet.damageFalloffEndDistance - bullet.damageFalloffStartDistance)
		local damageScaleRange = (bullet.endDamage - bullet.startDamage)

		local distancePercent = (shotDistance - bullet.damageFalloffStartDistance) / distanceScaleRange
		local damageMod = damageScaleRange * distancePercent

		expectedActualDamage = (bullet.startDamage + damageMod) * protectionMultiplier
	end

	local pelletHitCount = 1
	local damageCheckAmount = info.damage

	if (weaponNumBullets > 1 and info.damage > 0) then
		pelletHitCount = info.damage / expectedActualDamage
		damageCheckAmount = info.damage / pelletHitCount
	end
	if (pelletHitCount > weaponNumBullets) then
		if (DamageCheckerConfig.WarnOnWrongPellets) then
			print('Warning! More pellets hit than gun has! Hit: '..tostring(pelletHitCount)..' | Gun Pellets: '..tostring(weaponNumBullets)..' for '..giverInfo.giver.name)
		end
	end

	if (DamageCheckerConfig.FixDoubleDamage) then
		if (math.round(damageCheckAmount) > math.round(expectedActualDamage) and math.round(damageCheckAmount/2) == math.round(expectedActualDamage)) then

			if (DamageCheckerConfig.WarnOnDoubleDamage) then
				print('Warning! Fixed Double damage for '..giverInfo.giver.name)
			end
			info.damage = info.damage / 2
		end
	end

	local damageDifference = math.round(damageCheckAmount) - math.round(expectedActualDamage)

	if (DamageCheckerConfig.ShowDebug) then
		print('==================: '..tostring(SharedUtils:GetTimeMS()))
		print('Distance: '..tostring(shotDistance))
		print(tostring(bullet.ammunitionType)..' ('..tostring(materialContainer.materialNames[bulletMaterialMapIndex+1])..' -> '..tostring(materialContainer.materialNames[damagedMaterialMapIndex+1])..')')
		print('Num Pellets: '..tostring(weaponNumBullets)..', Hit: '..tostring(pelletHitCount))
		print('protectionMultiplier  (bullet -> dmgMat): '..tostring(protectionMultiplier))
		--print('penetrationMultiplier  (bullet -> dmgMat): '..tostring(penetrationMultiplier))
		--print('protectionThreshold  (bullet -> dmgMat): '..tostring(protectionThreshold))
		print('Damage Falloff - Start: '..tostring(bullet.damageFalloffStartDistance)..', End: '..tostring(bullet.damageFalloffEndDistance)..', Range: '..tostring(bullet.damageFalloffEndDistance - bullet.damageFalloffStartDistance))
		print('Bullet Damage - Start: '..tostring(bullet.startDamage)..', End: '..tostring(bullet.endDamage)..', Range: '..tostring(bullet.endDamage - bullet.startDamage))
		print('expectedActualDamage: '..tostring(expectedActualDamage)..' round: '..math.round(expectedActualDamage))
		print('damageCheckAmount   : '..tostring(damageCheckAmount)..' round: '..math.round(damageCheckAmount))
		print('info.damage         : '..tostring(info.damage)..' round: '..math.round(info.damage))
		print('damageDifference: '..tostring(damageDifference)..' tolerance: '..tostring(DamageCheckerConfig.DamageTolerance))
		print('============================================')
	end

	if (damageDifference < (DamageCheckerConfig.DamageTolerance * -1) or damageDifference > DamageCheckerConfig.DamageTolerance) then
		-- user might have changed their damage values
		if (DamageCheckerConfig.WarnOnMisMatch) then
			print('Warning! '..giverInfo.giver.name.. ' ['..giverInfo.giver.guid:ToString('D')..'] damage exceeded tolerance! Expected: '..expectedActualDamage..', Got: '..tostring(info.damage)..')')

			if (DamageCheckerConfig.ShowDebugOnMisMatch) then
				print('==================: '..tostring(SharedUtils:GetTimeMS()))
				print('Distance: '..tostring(shotDistance))
				print(tostring(bullet.ammunitionType)..' ('..tostring(materialContainer.materialNames[bulletMaterialMapIndex+1])..' -> '..tostring(materialContainer.materialNames[damagedMaterialMapIndex+1])..')')
				print('Num Pellets: '..tostring(weaponNumBullets)..', Hit: '..tostring(pelletHitCount))
				print('protectionMultiplier  (bullet -> dmgMat): '..tostring(protectionMultiplier))
				--print('penetrationMultiplier  (bullet -> dmgMat): '..tostring(penetrationMultiplier))
				--print('protectionThreshold  (bullet -> dmgMat): '..tostring(protectionThreshold))
				print('Damage Falloff - Start: '..tostring(bullet.damageFalloffStartDistance)..', End: '..tostring(bullet.damageFalloffEndDistance)..', Range: '..tostring(bullet.damageFalloffEndDistance - bullet.damageFalloffStartDistance))
				print('Bullet Damage - Start: '..tostring(bullet.startDamage)..', End: '..tostring(bullet.endDamage)..', Range: '..tostring(bullet.endDamage - bullet.startDamage))
				print('expectedActualDamage: '..tostring(expectedActualDamage)..' round: '..math.round(expectedActualDamage))
				print('damageCheckAmount   : '..tostring(damageCheckAmount)..' round: '..math.round(damageCheckAmount))
				print('info.damage         : '..tostring(info.damage)..' round: '..math.round(info.damage))
				print('damageDifference: '..tostring(damageDifference)..' tolerance: '..tostring(DamageCheckerConfig.DamageTolerance))
				print('============================================')
			end
		end

		if (DamageCheckerConfig.EnforceExpectedDamage) then
			info.damage = (expectedActualDamage * pelletHitCount)
			hook:Pass(soldier, info, giverInfo)
		end
	end
end)

Events:Subscribe('Level:Loaded', function(levelName, gameMode, round, roundsPerMap)
	materialGrid = MaterialGridData(ResourceManager:SearchForDataContainer(SharedUtils:GetLevelName() .. "/MaterialGrid_Win32/Grid"))
	materialContainer = MaterialContainerAsset(ResourceManager:SearchForDataContainer("Materials/MaterialContainer"))
end)

Events:Subscribe('Level:Destroy', function()
	materialContainer = nil
	materialGrid = nil
end)

function string:split(sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields + 1] = c end)
    return fields
end 

function math.sign(v)
	return (v >= 0 and 1) or -1
end

function math.round(v, bracket)
	bracket = bracket or 1
	return math.floor(v/bracket + math.sign(v) * 0.5) * bracket
end