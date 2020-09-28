//Physical Damage Detection plugin for Damage Engine 5.0 and prior.
//
//A few important notes:
//- Spell reduction is handled multiplicatively in DamageEngine, instead of additively like in PDD.
//- Just like in PDD, make sure you've modified the Runed Bracers item to remove the Spell Damage Reduction ability
//- Move any UnitDamageTargetEx calls to an "AfterDamageEvent Equal to 1.00" trigger
//- You do not need custom Get/Set-Unit(Max)Life functions, but I included them for ease of import.
//
//I will add more disclaimers, tips or fixes if anyone runs into issues!

function GetUnitLife takes unit u returns real
    return GetWidgetLife(u)
endfunction
function SetUnitLife takes unit u, real r returns nothing
    call SetWidgetLife(u, r)
endfunction
function GetUnitMaxLife takes unit u returns real
    return GetUnitState(u, UNIT_STATE_MAX_LIFE)
endfunction
function UnitDamageTargetEx takes unit source, unit target, boolean b, real amount, boolean attack, boolean ranged, attacktype a, damagetype d, weapontype w returns boolean
    local integer ptype = udg_PDD_damageType
    //To keep this functioning EXACTLY the same as it does in PDD, you need to move it
    //to an AfterDamageEvent Equal to 1.00 trigger. It's up to you.
    if ptype != udg_PDD_CODE then
        set udg_PDD_damageType = udg_PDD_CODE
        call UnitDamageTarget(source, target, amount, attack, ranged, a, d, w)
        call TriggerEvaluate(udg_ClearDamageEvent)
        set udg_PDD_damageType = ptype
        return true
    endif
    return false
endfunction
function PDD_OnDamage takes nothing returns boolean
    //cache previously-stored values in the event of recursion.
    local unit source = udg_PDD_source
    local unit target = udg_PDD_target
    local real amount = udg_PDD_amount
    local integer typ = udg_PDD_damageType
    //set variables to their event values.
    set udg_PDD_source = udg_DamageEventSource
    set udg_PDD_target = udg_DamageEventTarget
    set udg_PDD_amount = udg_DamageEventAmount
    //Extract the damage type from what we already have to work with.
    if udg_IsDamageSpell then
        set udg_PDD_damageType = udg_PDD_SPELL
    elseif udg_PDD_damageType != udg_PDD_CODE then
        set udg_PDD_damageType = udg_PDD_PHYSICAL
    endif
    //Fire PDD event.
    set udg_PDD_damageEventTrigger = 0.00
    set udg_PDD_damageEventTrigger = 1.00
    //Hey, this works and I'm really happy about that!
    set udg_DamageEventAmount = udg_PDD_amount
    //reset things just in case of a recursive event.
    set udg_PDD_damageEventTrigger = 0.00
    set udg_PDD_source = source
    set udg_PDD_target = target
    set udg_PDD_amount = amount
    set udg_PDD_damageType = typ
    set source = null
    set target = null
    return false
endfunction
function InitTrig_DamageEvent takes nothing returns nothing
    set udg_PDD_PHYSICAL = 0
    set udg_PDD_SPELL = 1
    set udg_PDD_CODE = 2
    set udg_PDD_damageEvent = CreateTrigger()
    call TriggerRegisterVariableEvent(udg_PDD_damageEvent, "udg_DamageModifierEvent", EQUAL, 1.00)
    call TriggerAddCondition(udg_PDD_damageEvent, Filter(function PDD_OnDamage))
endfunction
