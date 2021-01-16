# VU-MVDamageChecker
An admin tool for Battlefield 3: Venice Unleashed that checks player damage against EBX values and warns if they do not match

This mod performs some of the same functions as [FlashHits' damageCheck](https://github.com/FlashHit/VU-Mods/tree/master/damageCheck) mod but with changes of my own.

## Description
This mod cross-checks the damage players are giving via guns to help ctach cheaters who are boosting their damage. **No action is taken** when such an event occurs, rather a warning message in the server's console is issued. *It is still up to an admin to review these warnings and determine if they are malicious or not.*

An additional attempt to fix one version of the duplicate hits bug has been included

## Configuration
The following variables are available via RCON:

### `vu-mvdamagechecker.WarnOnMisMatch <boolean>`
Default value: `true`
prints a warning message with player name and guid when a damage mismatch occurs outside the tolerance level

### `vu-mvdamagechecker.DamageTolerance <float>`
Default value: `1.0`
When a damage mismatch occurs this is the range from 0 that is ignored. If the damage dealt is higher or lower than the expected damage by this amount, a warning is issued. Due to Lua's float precision and rounding errors, `1.0` is the default value.

### `vu-mvdamagechecker.EnforceExpectedDamage <boolean>`
Default value: `false`
The damage calc is pretty accurate, but not perfect. This setting will enforce the expected damage if there is a damage mismatch.

### `vu-mvdamagechecker.FixDoubleDamage <boolean>`
Default value: `true`
In current builds of the game, there is a known issue where sometimes a bullet deals two hits or double damage. This setting attempts to rectify the latter event. If the damage dealt is exactly double the damage expected, this will try to correct that amount.

### `vu-mvdamagechecker.WarnOnDoubleDamage <boolean>`
Default value: `true`
If a double damage event is found, this will print a warning message in the console.

### `vu-mvdamagechecker.ShowDebug <boolean>`
Default value: `false`
Prints full debug data on every bullet hit. For testing only.
