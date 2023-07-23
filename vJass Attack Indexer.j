library AttackIndexer initializer Init requires Table
//Version 1.0

//requires Globals: 
// - unit udg_DamageEventAttackTarget
// - boolean udg_DamageFromPrimaryAttack

globals
    private Table table

    // UnitData structure
    private integer array attack1
    private integer array attack2

    // AttackData structure
    private constant integer DATA_INDEX = 12
    private constant integer POINT_INDEX = 1
    private constant integer TARGET_INDEX = 2
endglobals

struct Attack extends array
    unit attackTarget
    boolean isPrimaryAttack
endstruct

function AttackIndexer__AdjustOnDamage takes Damage d returns nothing
    local Attack a = d
    local integer point2D = GetHandleId(d.weaponType)
    local integer tablePoint = point2D / 2
    local integer trueWeapon
    local integer id = GetUnitUserData(d.sourceUnit)
    local TableArray t = table[id]
    
    set a.attackTarget = t[tablePoint].unit[TARGET_INDEX]
    set a.isPrimaryAttack = tablePoint * 2 == point2D

    if a.isPrimaryAttack then
        set trueWeapon = attack1[id]
    else
        set trueWeapon = attack2[id]
    endif

    // Put the weapon type back to normal; this means
    // that the whole experience is un-marred despite
    // this hack.
    set d.weaponType = ConvertWeaponType(trueWeapon)
endfunction

//! textmacro ATTACK_INDEXER_ADJUSTMENTS
    call AttackIndexer__AdjustOnDamage(d)
//! endtextmacro

//! textmacro ATTACK_INDEXER_GUI_VARS
    set udg_DamageEventAttackTarget = Attack(Damage.index).attackTarget
    set udg_DamageFromPrimaryAttack = Attack(Damage.index).isPrimaryAttack
//! endtextmacro

private function AssignAttacks takes integer id returns nothing
    set attack1[id] = BlzGetUnitWeaponIntegerField(udg_UDexUnits[id], UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, 0)
    set attack2[id] = BlzGetUnitWeaponIntegerField(udg_UDexUnits[id], UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, 1)
endfunction

private function OnUnitAttacked takes nothing returns boolean
    local unit attackedUnit = GetTriggerUnit()
    local unit attacker = GetAttacker()
    local integer id = GetUnitUserData(attacker)
    local TableArray t = table[id]
    local integer point

    if t == 0 then
        // There are 24 different weapon types, so to track
        // primary attack and secondary attack, we can only
        // have 12 unique simultanous attacks per attacker.
        // The 13th slot is for general data storage.
        set t = TableArray[13]
        set table[id] = t
        call AssignAttacks(id)
    endif

    // The hashtable will initialize point first to 0.
    set point = t[DATA_INDEX][POINT_INDEX]

    // Clean any old data from the -12th attack.
    call t[point].flush()

    set t[point].unit[TARGET_INDEX] = attackedUnit

    if point > 11 then
        // Wrap around so as to recycle -12th indices.
        set point = 0
    endif

    set t[DATA_INDEX][POINT_INDEX] = point

    call BlzSetUnitWeaponIntegerField(attacker, UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, 0, point * 2)
    call BlzSetUnitWeaponIntegerField(attacker, UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, 1, point * 2 + 1)

    set attackedUnit = null
    set attacker = null
    return false
endfunction

private function OnUnitTransformed takes nothing returns boolean
    local Table t = table[udg_UDex]
    if t > 0 then
        call AssignAttacks(udg_UDex)
    endif
    return false
endfunction

private function OnUnitRemoved takes nothing returns boolean
    if table[udg_UDex] > 0 then
        // flush and destroy the TableArray
        call table[udg_UDex].flush()
        call table.remove(udg_UDex)
    endif
    return false
endfunction

private function Init takes nothing returns nothing
    local trigger t = CreateTrigger()
    call TriggerRegisterAnyUnitEventBJ(t, EVENT_PLAYER_UNIT_ATTACKED)
    call TriggerAddCondition(t, Filter(function OnUnitAttacked))

    set t = CreateTrigger()
    call TriggerRegisterVariableEvent(t, "udg_UnitIndexEvent", EQUAL, 2.00)
    call TriggerAddCondition(t, Filter(function OnUnitRemoved))

    set t = CreateTrigger()
    call TriggerRegisterVariableEvent(t, "udg_UnitTypeEvent", EQUAL, 1.00)
    call TriggerAddCondition(t, Filter(function OnUnitTransformed))

    set table = Table.create()
    set t = null
endfunction

endlibrary
