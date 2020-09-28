-[[
===========================================================================
 Lua Version
 Damage Engine lets you detect, amplify, block or nullify damage. It even
 lets you detect if the damage was physical or from a spell. Just reference
 DamageEventAmount/Source/Target or the boolean IsDamageSpell, to get the
 necessary damage event data.

 - Detect damage (after it was dealt to the unit): use the event "DamageEvent Equal to 1.00"
 - To change damage before it is dealt: use the event "DamageModifierEvent Equal to 1.00"
 - Detect spell damage: use the condition "IsDamageSpell Equal to True"
 - Detect zero-damage: use the event "DamageEvent Equal to 2.00"

 You can specify the DamageEventType before dealing triggered damage:
 - Set NextDamageType = DamageTypeWhatever
 - Unit - Cause...

 You can modify the DamageEventAmount and the DamageEventType from a "DamageModifierEvent Equal to 1.00" trigger.
 - If the amount is modified to negative, it will count as a heal.
 - If the amount is set to 0, no damage will be dealt.

 If you need to reference the original in-game damage, use the variable "DamageEventPrevAmt".
GUI Vars:

   Retained from 3.8 and prior:
   ----------------------------
   unit           udg_DamageEventSource
   unit           udg_DamageEventTarget
   unit           udg_EnhancedDamageTarget
   group          udg_DamageEventAOEGroup
   integer        udg_DamageEventAOE
   integer        udg_DamageEventLevel
   real           udg_DamageModifierEvent
   real           udg_DamageEvent
   real           udg_AfterDamageEvent
   real           udg_DamageEventAmount
   real           udg_DamageEventPrevAmt
   real           udg_AOEDamageEvent
   boolean        udg_DamageEventOverride
   boolean        udg_NextDamageType
   boolean        udg_DamageEventType
   boolean        udg_IsDamageSpell

   Added in 5.0:
   boolean        udg_IsDamageMelee
   boolean        udg_IsDamageRanged
   unit           udg_AOEDamageSource
   real           udg_LethalDamageEvent
   real           udg_LethalDamageHP
   real           udg_DamageScalingWC3
   integer        udg_DamageEventAttackT
   integer        udg_DamageEventDamageT
   integer        udg_DamageEventWeaponT

   Added in 5.1:
   boolean        udg_IsDamageCode

   Added in 5.2:
   integer        udg_DamageEventArmorT
   integer        udg_DamageEventDefenseT

   Addded in 5.3:
   real           DamageEventArmorPierced
   real           udg_DamageScalingUser

   Added in 5.4.2 to allow GUI users to re-issue the exact same attack and damage type at the attacker.
   attacktype array udg_CONVERTED_ATTACK_TYPE
   damagetype array udg_CONVERTED_DAMAGE_TYPE

=============================================================================
--]]
do
   local alarm       = CreateTimer()
   local alarmSet    = false

   --Values to track the original pre-spirit Link/defensive damage values
   local canKick     = true
   local totem       = false
   local armorType   = 0
   local defenseType = 0
   local prev        = {}

   --Stuff to track recursive UnitDamageTarget calls.
   local eventsRun   = false
   local kicking     = false
   local stack       = {}

   --Added in 5.4 to silently eliminate infinite recursion.
   local userTrigs   = 9
   local eventTrig   = 0
   local nextTrig    = {}
   local userTrig    = {}
   local trigFrozen  = {}

   --Added/re-tooled in 5.4.1 to allow forced recursion (for advanced users only).
   local levelsDeep     = {}   --How deep the user recursion currently is.
   local LIMBO          = 16   --Recursion will never go deeper than LIMBO.
   DamageEngine_inception= false --You must set DamageEngine_inception = true before dealing damage to utlize this.
                          --When true, it allows your trigger to potentially go recursive up to LIMBO.
   local dreaming       = false
   local fischerMorrow  = {} --track targets of recursion
   local inceptionTrig  = {}   --Added in 5.4.2 to simplify the inception variable for very complex DamageEvent trigger.
   local proclusGlobal  = {} --track sources of recursion
   local sleepLevel     = 0

   --Improves readability in the code to have these as named constants.
   local event = {
      mod      = 1,
      shield   = 4,
      damage   = 5,
      zero     = 6,
      after    = 7,
      lethal   = 8,
      aoe      = 9
   }

   local function runTrigs(i)
      local cat = i
      dreaming = true
      --print("Running " .. cat)
      while (true) do
         i = nextTrig[i]
         if (i == 0)
           or (cat == event.mod and (udg_DamageEventOverride or udg_DamageEventType*udg_DamageEventType == 4))
           or (cat == event.shield and udg_DamageEventAmount <= 0.00)
           or (cat == event.lethal and udg_LethalDamageHP > 0.405) then
            break
         end
         if not trigFrozen[i] then
            eventTrig = i
            if RunTrigger then --Added 10 July 2019 to enable FastTriggers mode.
               RunTrigger(userTrig[i])
            elseif IsTriggerEnabled(userTrig[i])
              and TriggerEvaluate(userTrig[i]) then
               TriggerExecute(userTrig[i])
            end
            --print("Ran " .. i)
         end
      end
      --print("Ran")
      dreaming = false
   end

   local function onAOEEnd()
      if udg_DamageEventAOE > 1 then
         runTrigs(event.aoe)
         udg_DamageEventAOE   = 1
      end
      udg_DamageEventLevel    = 1
      udg_EnhancedDamageTarget= nil
      udg_AOEDamageSource     = nil
      GroupClear(udg_DamageEventAOEGroup)
   end

   local function afterDamage()
      if udg_DamageEventPrevAmt ~= 0.00 and udg_DamageEventDamageT ~= udg_DAMAGE_TYPE_UNKNOWN then
         runTrigs(event.after)
      end
   end

   local oldUDT = UnitDamageTarget

   local function finish()
      if eventsRun then
         --print "events ran"
         eventsRun = false
         afterDamage()
      end
      if canKick and not kicking then
         local n = #stack
         if n > 0 then
            kicking = true
            --print("Clearing Recursion: " .. n)
            local i = 0
            local open
            repeat
               sleepLevel = sleepLevel + 1
               repeat
                  i = i + 1 --Need to loop bottom to top to make sure damage order is preserved.
                  open = stack[i]
                  udg_NextDamageType = open.type
                  --print("Stacking on " .. open.amount)
                  oldUDT(open.source, open.target, open.amount, true, false, open.attack, open.damage, open.weapon)
                  afterDamage()
               until (i == n)
               --print("Exit at: " .. i)
               n = #stack
            until (i == n)
            --print("Terminate at: " .. i)
            sleepLevel = 0
            repeat
               open = stack[i].trig
               stack[i] = nil
               proclusGlobal[open] = nil
               fischerMorrow[open] = nil
               trigFrozen[open] = false -- Only re-enable recursive triggers AFTER all damage is dealt.
               levelsDeep[open] = 0 --Reset this stuff if the user tried some nonsense
               --print("unfreezing " .. open)
               i = i - 1
            until (i == 0)
            kicking = false
         end
      end
   end

   function UnitDamageTarget(src, tgt, amt, a, r, at, dt, wt)
      if udg_NextDamageType == 0 then
         udg_NextDamageType = udg_DamageTypeCode
      end
      local b = false
      if dreaming then
         if amt ~= 0.00 then
            -- Store triggered, recursive damage into a stack.
            -- This damage will be fired after the current damage instance has wrapped up its events.
            stack[#stack + 1] = {
               type     = udg_NextDamageType,
               source   = src,
               target   = tgt,
               amount   = amt,
               attack   = at,
               damage   = dt,
               weapon   = wt,
               trig     = eventTrig
            }
            --print("increasing damage stack: " .. #stack)
 
            -- Next block added in 5.4.1 to allow *some* control over whether recursion should kick
            -- in. Also it's important to track whether the source and target were both involved at
            -- some earlier point, so this is a more accurate and lenient method than before.
            DamageEngine_inception = DamageEngine_inception or inceptionTrig[eventTrig]
 
            local sg = proclusGlobal[eventTrig]
            if not sg then
               sg = {}
               proclusGlobal[eventTrig] = sg
            end
            sg[udg_DamageEventSource] = true
 
            local tg = fischerMorrow[eventTrig]
            if not tg then
               tg = {}
               fischerMorrow[eventTrig] = tg
            end
            tg[udg_DamageEventTarget] = true
 
            if kicking and sg[src] and tg[tgt] then
               if DamageEngine_inception and not trigFrozen[eventTrig] then
                  inceptionTrig[eventTrig] = true
                  if levelsDeep[eventTrig] < sleepLevel then
                     levelsDeep[eventTrig] = levelsDeep[eventTrig] + 1
                     if levelsDeep[eventTrig] >= LIMBO then
                        --print("freezing inception trig: " .. eventTrig)
                        trigFrozen[eventTrig] = true
                     end
                  end
               else
                  --print("freezing standard trig: " .. eventTrig)
                  trigFrozen[eventTrig] = true
               end
            end
         end
      else
         b = oldUDT(src, tgt, amt, a, r, at, dt, wt)
      end
      --print("setting inception to false")
      DamageEngine_inception = false
      udg_NextDamageType = 0
      if b and not dreaming then
         finish() -- Wrap up the outstanding damage instance right away.
      end
      return b
   end

   local function resetArmor()
      if udg_DamageEventArmorPierced ~= 0.00 then
         BlzSetUnitArmor(udg_DamageEventTarget, BlzGetUnitArmor(udg_DamageEventTarget) + udg_DamageEventArmorPierced)
      end
      if armorType ~= udg_DamageEventArmorT then
         BlzSetUnitIntegerField(udg_DamageEventTarget, UNIT_IF_ARMOR_TYPE, armorType) --revert changes made to the damage instance
      end
      if defenseType ~= udg_DamageEventDefenseT then
         BlzSetUnitIntegerField(udg_DamageEventTarget, UNIT_IF_DEFENSE_TYPE, defenseType)
      end
   end

   local function failsafeClear()
      --print("Damage from " .. GetUnitName(udg_DamageEventSource) .. " to " .. GetUnitName(udg_DamageEventTarget) .. " has been messing up Damage Engine.")
      --print(udg_DamageEventAmount .. " " .. " " .. udg_DamageEventPrevAmt .. " " .. udg_AttackTypeDebugStr[udg_DamageEventAttackT] .. " " .. udg_DamageTypeDebugStr[udg_DamageEventDamageT])
      resetArmor()
      canKick = true
      totem = false
      udg_DamageEventAmount = 0.00
      udg_DamageScalingWC3  = 0.00
      if udg_DamageEventDamageT ~= udg_DAMAGE_TYPE_UNKNOWN then
         runTrigs(event.damage) --Run the normal on-damage event based on this failure.
         eventsRun = true --Run the normal after-damage event based on this failure.
      end
      finish()
   end

   local function calibrateMR()
      udg_IsDamageMelee         = false
      udg_IsDamageRanged        = false
      udg_IsDamageSpell         = udg_DamageEventAttackT == 0 --In Patch 1.31, one can just check the attack type to find out if it's a spell.
      if udg_DamageEventDamageT == udg_DAMAGE_TYPE_NORMAL and not udg_IsDamageSpell then --This damage type is the only one that can get reduced by armor.
         udg_IsDamageMelee      = IsUnitType(udg_DamageEventSource, UNIT_TYPE_MELEE_ATTACKER)
         udg_IsDamageRanged     = IsUnitType(udg_DamageEventSource, UNIT_TYPE_RANGED_ATTACKER)
         if udg_IsDamageMelee and udg_IsDamageRanged then
            udg_IsDamageMelee   = udg_DamageEventWeaponT > 0-- Melee units play a sound when damaging
            udg_IsDamageRanged  = not udg_IsDamageMelee    -- In the case where a unit is both ranged and melee, the ranged attack plays no sound.
         end                                       -- The Huntress has a melee sound for her ranged projectile, however it is only an issue
      end                                          --if she also had a melee attack, because by default she is only UNIT_TYPE_RANGED_ATTACKER.
   end

   local t1 = CreateTrigger()
   TriggerRegisterAnyUnitEventBJ(t1, EVENT_PLAYER_UNIT_DAMAGING)
   TriggerAddCondition(t1, Filter(function()
      local src = GetEventDamageSource()
      local tgt = BlzGetEventDamageTarget()
      local amt = GetEventDamage()
      local at = BlzGetEventAttackType()
      local dt = BlzGetEventDamageType()
      local wt = BlzGetEventWeaponType()

      --print "First damage event running"

      if not kicking then
         if alarmSet then
            if totem then
               if dt ~= DAMAGE_TYPE_SPIRIT_LINK and dt ~= DAMAGE_TYPE_DEFENSIVE and dt ~= DAMAGE_TYPE_PLANT then
                  -- if 'totem' is still set and it's not due to spirit link distribution or defense retaliation,
                  -- the next function must be called as a debug. This reverts an issue I created in patch 5.1.3.
                  failsafeClear()
               else
                  totem       = false
                  canKick     = false
                  prev.type   = udg_DamageEventType      -- also store the damage type.
                  prev.amount = udg_DamageEventAmount
                  prev.preAmt = udg_DamageEventPrevAmt   -- Store the actual pre-armor value.
                  prev.pierce = udg_DamageEventArmorPierced
                  prev.armor  = udg_DamageEventArmorT
                  prev.preArm = armorType
                  prev.defense= udg_DamageEventDefenseT
                  prev.preDef = defenseType
                  prev.code   = udg_IsDamageCode        -- store this as well.
               end
            end
            if src ~= udg_AOEDamageSource then -- Source has damaged more than once
               onAOEEnd() -- New damage source - unflag everything
               udg_AOEDamageSource = src
            elseif tgt == udg_EnhancedDamageTarget then
               udg_DamageEventLevel= udg_DamageEventLevel + 1  -- The number of times the same unit was hit.
            elseif not IsUnitInGroup(tgt, udg_DamageEventAOEGroup) then
               udg_DamageEventAOE  = udg_DamageEventAOE + 1   -- Multiple targets hit by this source - flag as AOE
            end
         else
            TimerStart(alarm, 0.00, false, function()
               alarmSet = false --The timer has expired. Flag off to allow it to be restarted when needed.
               finish() --Wrap up any outstanding damage instance
               onAOEEnd() --Reset things so they don't perpetuate for AoE/Level target detection
            end)
            alarmSet                = true
            udg_AOEDamageSource     = src
            udg_EnhancedDamageTarget= tgt
         end
         GroupAddUnit(udg_DamageEventAOEGroup, tgt)
      end
      udg_DamageEventType           = udg_NextDamageType
      udg_IsDamageCode              = udg_NextDamageType ~= 0
      udg_DamageEventOverride       = dt == nil -- Got rid of NextDamageOverride in 5.1 for simplicity
      udg_DamageEventPrevAmt        = amt
      udg_DamageEventSource         = src
      udg_DamageEventTarget         = tgt
      udg_DamageEventAmount         = amt
      udg_DamageEventAttackT        = GetHandleId(at)
      udg_DamageEventDamageT        = GetHandleId(dt)
      udg_DamageEventWeaponT        = GetHandleId(wt)

      calibrateMR() -- Set Melee and Ranged settings.

      udg_DamageEventArmorT         = BlzGetUnitIntegerField(udg_DamageEventTarget, UNIT_IF_ARMOR_TYPE) -- Introduced in Damage Engine 5.2.0.0
      udg_DamageEventDefenseT       = BlzGetUnitIntegerField(udg_DamageEventTarget, UNIT_IF_DEFENSE_TYPE)
      armorType                     = udg_DamageEventArmorT
      defenseType                   = udg_DamageEventDefenseT
      udg_DamageEventArmorPierced   = 0.00
      udg_DamageScalingUser         = 1.00
      udg_DamageScalingWC3          = 1.00

      if amt ~= 0.00 then
         if not udg_DamageEventOverride then
            runTrigs(event.mod)
 
            -- All events have run and the pre-damage amount is finalized.
            BlzSetEventAttackType(ConvertAttackType(udg_DamageEventAttackT))
            BlzSetEventDamageType(ConvertDamageType(udg_DamageEventDamageT))
            BlzSetEventWeaponType(ConvertWeaponType(udg_DamageEventWeaponT))
            if udg_DamageEventArmorPierced ~= 0.00 then
               BlzSetUnitArmor(udg_DamageEventTarget, BlzGetUnitArmor(udg_DamageEventTarget) - udg_DamageEventArmorPierced)
            end
            if armorType ~= udg_DamageEventArmorT then
               BlzSetUnitIntegerField(udg_DamageEventTarget, UNIT_IF_ARMOR_TYPE, udg_DamageEventArmorT) -- Introduced in Damage Engine 5.2.0.0
            end
            if defenseType ~= udg_DamageEventDefenseT then
               BlzSetUnitIntegerField(udg_DamageEventTarget, UNIT_IF_DEFENSE_TYPE, udg_DamageEventDefenseT) -- Introduced in Damage Engine 5.2.0.0
            end
            BlzSetEventDamage(udg_DamageEventAmount)
         end
         totem = true
         -- print("Ready to deal " .. udg_DamageEventAmount)
      else
         runTrigs(event.zero)
         canKick = true
         finish()
      end
      return false
   end))

   local t2 = CreateTrigger()
   TriggerRegisterAnyUnitEventBJ(t2, EVENT_PLAYER_UNIT_DAMAGED)
   TriggerAddCondition(t2, Filter(function()
      if udg_DamageEventPrevAmt == 0.00 then
         return false
      end
      --print "Second event running"
      if totem then
         totem = false   --This should be the case in almost all circumstances
      else
         afterDamage() --Wrap up the outstanding damage instance
         canKick                = true
         --Unfortunately, Spirit Link and Thorns Aura/Spiked Carapace fire the DAMAGED event out of sequence with the DAMAGING event,
         --so I have to re-generate a buncha stuff here.
         udg_DamageEventSource      = GetEventDamageSource()
         udg_DamageEventTarget      = GetTriggerUnit()
         udg_DamageEventAmount      = prev.amount
         udg_DamageEventPrevAmt     = prev.preAmt
         udg_DamageEventAttackT     = GetHandleId(BlzGetEventAttackType())
         udg_DamageEventDamageT     = GetHandleId(BlzGetEventDamageType())
         udg_DamageEventWeaponT     = GetHandleId(BlzGetEventWeaponType())
         udg_DamageEventType        = prev.type
         udg_IsDamageCode           = prev.code
         udg_DamageEventArmorT      = prev.armor
         udg_DamageEventDefenseT    = prev.defense
         udg_DamageEventArmorPierced= prev.pierce
         armorType                  = prev.preArm
         defenseType                = prev.preDef
         calibrateMR() --Apply melee/ranged settings once again.
      end
      resetArmor()
      local r = GetEventDamage()
      if udg_DamageEventAmount ~= 0.00 and r ~= 0.00 then
         udg_DamageScalingWC3 = r/udg_DamageEventAmount
      else
         if udg_DamageEventAmount > 0.00 then
            udg_DamageScalingWC3 = 0.00
         else
            udg_DamageScalingWC3 = 1.00
         end
         udg_DamageScalingUser = udg_DamageEventAmount/udg_DamageEventPrevAmt
      end
      udg_DamageEventAmount = udg_DamageEventAmount*udg_DamageScalingWC3

      if udg_DamageEventAmount > 0.00 then
         --This event is used for custom shields which have a limited hit point value
         --The shield here kicks in after armor, so it acts like extra hit points.
         runTrigs(event.shield)
         udg_LethalDamageHP = GetWidgetLife(udg_DamageEventTarget) - udg_DamageEventAmount
         if udg_LethalDamageHP <= 0.405 then
            runTrigs(event.lethal) -- added 10 May 2019 to detect and potentially prevent lethal damage. Instead of
            -- modifying the damage, you need to modify LethalDamageHP instead (the final HP of the unit).
 
            udg_DamageEventAmount = GetWidgetLife(udg_DamageEventTarget) - udg_LethalDamageHP
            if udg_DamageEventType < 0 and udg_LethalDamageHP <= 0.405 then
               SetUnitExploded(udg_DamageEventTarget, true)   --Explosive damage types should blow up the target.
            end
         end
         udg_DamageScalingUser = udg_DamageEventAmount/udg_DamageEventPrevAmt/udg_DamageScalingWC3
      end
      BlzSetEventDamage(udg_DamageEventAmount)   --Apply the final damage amount.
      if udg_DamageEventDamageT ~= udg_DAMAGE_TYPE_UNKNOWN then
         runTrigs(event.damage)
      end
      eventsRun = true
      --print(canKick)
      if udg_DamageEventAmount == 0.00 then
         finish()
      end
      return false
   end))

   onGlobalInit(function()
      local i
      for i = 0, 6 do udg_CONVERTED_ATTACK_TYPE[i] = ConvertAttackType(i) end
      for i = 0, 26 do udg_CONVERTED_DAMAGE_TYPE[i] = ConvertDamageType(i) end

      udg_AttackTypeDebugStr[0] = "SPELLS"   -- ATTACK_TYPE_NORMAL in JASS
      udg_AttackTypeDebugStr[1] = "NORMAL"   -- ATTACK_TYPE_MELEE in JASS
      udg_AttackTypeDebugStr[2] = "PIERCE"
      udg_AttackTypeDebugStr[3] = "SIEGE"
      udg_AttackTypeDebugStr[4] = "MAGIC"
      udg_AttackTypeDebugStr[5] = "CHAOS"
      udg_AttackTypeDebugStr[6] = "HERO"

      udg_DamageTypeDebugStr[0]  = "UNKNOWN"
      udg_DamageTypeDebugStr[4]  = "NORMAL"
      udg_DamageTypeDebugStr[5]  = "ENHANCED"
      udg_DamageTypeDebugStr[8]  = "FIRE"
      udg_DamageTypeDebugStr[9]  = "COLD"
      udg_DamageTypeDebugStr[10] = "LIGHTNING"
      udg_DamageTypeDebugStr[11] = "POISON"
      udg_DamageTypeDebugStr[12] = "DISEASE"
      udg_DamageTypeDebugStr[13] = "DIVINE"
      udg_DamageTypeDebugStr[14] = "MAGIC"
      udg_DamageTypeDebugStr[15] = "SONIC"
      udg_DamageTypeDebugStr[16] = "ACID"
      udg_DamageTypeDebugStr[17] = "FORCE"
      udg_DamageTypeDebugStr[18] = "DEATH"
      udg_DamageTypeDebugStr[19] = "MIND"
      udg_DamageTypeDebugStr[20] = "PLANT"
      udg_DamageTypeDebugStr[21] = "DEFENSIVE"
      udg_DamageTypeDebugStr[22] = "DEMOLITION"
      udg_DamageTypeDebugStr[23] = "SLOW_POISON"
      udg_DamageTypeDebugStr[24] = "SPIRIT_LINK"
      udg_DamageTypeDebugStr[25] = "SHADOW_STRIKE"
      udg_DamageTypeDebugStr[26] = "UNIVERSAL"

      udg_WeaponTypeDebugStr[0]  = "NONE"    -- WEAPON_TYPE_WHOKNOWS in JASS
      udg_WeaponTypeDebugStr[1]  = "METAL_LIGHT_CHOP"
      udg_WeaponTypeDebugStr[2]  = "METAL_MEDIUM_CHOP"
      udg_WeaponTypeDebugStr[3]  = "METAL_HEAVY_CHOP"
      udg_WeaponTypeDebugStr[4]  = "METAL_LIGHT_SLICE"
      udg_WeaponTypeDebugStr[5]  = "METAL_MEDIUM_SLICE"
      udg_WeaponTypeDebugStr[6]  = "METAL_HEAVY_SLICE"
      udg_WeaponTypeDebugStr[7]  = "METAL_MEDIUM_BASH"
      udg_WeaponTypeDebugStr[8]  = "METAL_HEAVY_BASH"
      udg_WeaponTypeDebugStr[9]  = "METAL_MEDIUM_STAB"
      udg_WeaponTypeDebugStr[10] = "METAL_HEAVY_STAB"
      udg_WeaponTypeDebugStr[11] = "WOOD_LIGHT_SLICE"
      udg_WeaponTypeDebugStr[12] = "WOOD_MEDIUM_SLICE"
      udg_WeaponTypeDebugStr[13] = "WOOD_HEAVY_SLICE"
      udg_WeaponTypeDebugStr[14] = "WOOD_LIGHT_BASH"
      udg_WeaponTypeDebugStr[15] = "WOOD_MEDIUM_BASH"
      udg_WeaponTypeDebugStr[16] = "WOOD_HEAVY_BASH"
      udg_WeaponTypeDebugStr[17] = "WOOD_LIGHT_STAB"
      udg_WeaponTypeDebugStr[18] = "WOOD_MEDIUM_STAB"
      udg_WeaponTypeDebugStr[19] = "CLAW_LIGHT_SLICE"
      udg_WeaponTypeDebugStr[20] = "CLAW_MEDIUM_SLICE"
      udg_WeaponTypeDebugStr[21] = "CLAW_HEAVY_SLICE"
      udg_WeaponTypeDebugStr[22] = "AXE_MEDIUM_CHOP"
      udg_WeaponTypeDebugStr[23] = "ROCK_HEAVY_BASH"

      udg_DefenseTypeDebugStr[0] = "LIGHT"
      udg_DefenseTypeDebugStr[1] = "MEDIUM"
      udg_DefenseTypeDebugStr[2] = "HEAVY"
      udg_DefenseTypeDebugStr[3] = "FORTIFIED"
      udg_DefenseTypeDebugStr[4] = "NORMAL"
      udg_DefenseTypeDebugStr[5] = "HERO"
      udg_DefenseTypeDebugStr[6] = "DIVINE"
      udg_DefenseTypeDebugStr[7] = "UNARMORED"

      udg_ArmorTypeDebugStr[0] = "NONE"
      udg_ArmorTypeDebugStr[1] = "FLESH"
      udg_ArmorTypeDebugStr[2] = "METAL"
      udg_ArmorTypeDebugStr[3] = "WOOD"
      udg_ArmorTypeDebugStr[4] = "ETHEREAL"
      udg_ArmorTypeDebugStr[5] = "STONE"
   end)

   function DamageEngine_SetupEvent(whichTrig, var, val)
      --print("Setup event: " .. var)
      local mx = 1
      local off = 0
      local ex = 0
      if var == "udg_DamageModifierEvent" then --event.mod 1-4 -> Events 1-4
         if (val < 3) then
            ex = val + 1
         end
         mx = 4
      elseif var == "udg_DamageEvent" then --event.damage 1,2 -> Events 5,6
         mx = 2
         off = 4
      elseif var == "udg_AfterDamageEvent" then --event.after -> Event 7
         off = 6
      elseif var == "udg_LethalDamageEvent" then --event.lethal -> Event 8
         off = 7
      elseif var == "udg_AOEDamageEvent" then --event.aoe -> Event 9
         off = 8
      else
         return false
      end
      local i
      if userTrigs == 9 then
         nextTrig[1] = 2
         nextTrig[2] = 3
         trigFrozen[2] = true
         trigFrozen[3] = true
         for i = 3, 9 do nextTrig[i] = 0 end
      end
      i = math.max(math.min(val, mx), 1) + off
      --print("Root index: " .. i .. " nextTrig: " .. nextTrig[i] .. " exit: " .. ex)
      repeat
         val = i
         i = nextTrig[i]
      until (i == ex)
      userTrigs = userTrigs + 1   --User list runs from index 10 and up
      nextTrig[val] = userTrigs
      nextTrig[userTrigs] = ex
      userTrig[userTrigs] = whichTrig
      levelsDeep[userTrigs] = 0
      trigFrozen[userTrigs] = false
      inceptionTrig[userTrigs] = false
      --print("Registered " .. userTrigs .. " to " .. val)
      return true
   end

   onRegisterVar(function(trig, var, val)
      DamageEngine_SetupEvent(trig, var, math.floor(val))
   end)
end
