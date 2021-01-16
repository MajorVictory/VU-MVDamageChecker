local materialGrid = nil
local materialContainer = nil
local DamageCheckerConfig = {
	['ShowDebug'] = false,
	['WarnOnMisMatch'] = true,
	['FixDoubleDamage'] = true,
	['WarnOnDoubleDamage'] = true,
	['EnforceExpectedDamage'] = true,
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
	if (info.boneIndex >= 0 and info.boneIndex <= 5) then

		local bullet = nil
		if giverInfo.giver.soldier.weaponsComponent.currentWeapon.weaponModifier.weaponProjectileModifier ~= nil and giverInfo.giver.soldier.weaponsComponent.currentWeapon.weaponModifier.weaponProjectileModifier.projectileData ~= nil then
			bullet = BulletEntityData(giverInfo.giver.soldier.weaponsComponent.currentWeapon.weaponModifier.weaponProjectileModifier.projectileData)
		else
			bullet = BulletEntityData(WeaponFiringData(giverInfo.weaponFiring).primaryFire.shot.projectileData)
		end

		local bulletMaterialMapIndex = bullet.materialPair.physicsPropertyIndex
		if bulletMaterialMapIndex < 0 then
			bulletMaterialMapIndex = 256 + bulletMaterialMapIndex
		end
		local bulletMaterial = materialGrid.materialIndexMap[bulletMaterialMapIndex+1]+1

		local damagedMaterialMapIndex = MaterialContainerPair(info.damagedMaterial).physicsPropertyIndex
		if damagedMaterialMapIndex < 0 then
			damagedMaterialMapIndex = 256 + damagedMaterialMapIndex
		end

		local materialGridItems = MaterialInteractionGridRow(materialGrid.interactionGrid[materialGrid.materialIndexMap[damagedMaterialMapIndex+1]+1]).items
		local multiplier = MaterialRelationDamageData(materialGridItems[bulletMaterial].physicsPropertyProperties[1]).damageProtectionMultiplier
		
		local expectedActualDamage = bullet.startDamage * multiplier -- shortest range, full damage

		local shotDistance = info.position:Distance(info.origin)

		if (shotDistance >= bullet.damageFalloffEndDistance) then -- long range, full end damage

			expectedActualDamage = bullet.endDamage * multiplier

		elseif (shotDistance > bullet.damageFalloffStartDistance) then -- mid range, scaled damage

			local distanceScaleRange = (bullet.damageFalloffEndDistance - bullet.damageFalloffStartDistance)
			local damageScaleRange = (bullet.endDamage - bullet.startDamage)

			local distancePercent = (shotDistance - bullet.damageFalloffStartDistance) / distanceScaleRange
			local damageMod = damageScaleRange * distancePercent

			expectedActualDamage = (bullet.startDamage + damageMod) * multiplier
		end

		if (DamageCheckerConfig.FixDoubleDamage) then
			if (math.floor(info.damage) > math.floor(expectedActualDamage) and math.floor(info.damage/2) == math.floor(expectedActualDamage)) then

				if (DamageCheckerConfig.WarnOnDoubleDamage) then
					print('Warning! Fixed Double damage for '..giverInfo.giver.name)
				end
				info.damage = info.damage / 2
			end
		end

		local damageDifference = math.floor(info.damage) - math.floor(expectedActualDamage)

		if (DamageCheckerConfig.ShowDebug) then
			print('==================: '..tostring(SharedUtils:GetTimeMS()))
			print('Distance: '..tostring(shotDistance))
			print('bulletMaterialMapIndex: '..tostring(materialContainer.materialNames[bulletMaterialMapIndex+1]))
			print('damagedMaterialMapIndex: '..tostring(materialContainer.materialNames[damagedMaterialMapIndex+1]))
			print('multiplier (bullet -> bone): '..tostring(multiplier))
			print('damageFalloffStartDistance: '..tostring(bullet.damageFalloffStartDistance))
			print('damageFalloffEndDistance: '..tostring(bullet.damageFalloffEndDistance))
			print('bullet.startDamage: '..tostring(bullet.startDamage))
			print('bullet.endDamage: '..tostring(bullet.endDamage))
			print('expectedActualDamage: '..tostring(expectedActualDamage)..' floor: '..math.floor(expectedActualDamage))
			print('info.damage: '..tostring(info.damage)..' floor: '..math.floor(info.damage))
			print('damageDifference: '..tostring(damageDifference)..' tolerance: '..tostring(DamageCheckerConfig.DamageTolerance))
			print('============================================')
		end

		if (damageDifference < (DamageCheckerConfig.DamageTolerance * -1) or damageDifference > DamageCheckerConfig.DamageTolerance) then
			-- user might have changed their damage values
			if (DamageCheckerConfig.WarnOnMisMatch) then
				print('Warning! '..giverInfo.giver.name.. ' ['..giverInfo.giver.guid:ToString('D')..'] damage exceeded tolerance! Expected: '..expectedActualDamage..', Got: '..tostring(info.damage)..')')
			end

			if (DamageCheckerConfig.EnforceExpectedDamage) then
				info.damage = expectedActualDamage
				hook:Pass(soldier, info, giverInfo)
			end
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