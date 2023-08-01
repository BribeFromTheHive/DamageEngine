library AttackIndexer initializer Init requires Table
// vJass version 1.1.0.2

//requires Globals:
// - unit udg_DamageEventAttackTarget
// - boolean udg_DamageFromPrimaryAttack

//These are unique integers per-attack which can be used as parent keys in a GUI hashtable:
// - integer udg_DamageHashKeyForAttack
// - integer array udg_AttackEventHashKey --indexed by the Attacking Unit's Custom Value

//Optional - only needed if USE_GUI_HASH is true:
// - hashtable udg_AttackIndexerHash

globals
    private constant boolean USE_GUI_HASH = true

    // Attack data structure stored in TableArray[0-11]
    private constant integer TARGET_INDEX   = -1
    private constant integer RESOLVED_INDEX = -2
endglobals

private struct UnitData extends array
    TableArray table
    integer points
    boolean circled
    integer attack1
    integer attack2

    method operator unit takes nothing returns unit
        return udg_UDexUnits[this]
    endmethod
endstruct

struct Attack extends array
    unit attackTarget
    boolean isPrimaryAttack

    // vJass users will have direct access to this, so they can use it with Table.
    // Main thing to consider is to avoid clashing indices, so I recommend either
    // using StringHash or a bucket of shared indices across a map's systems.
    Table attackHashKey
endstruct

function AttackIndexer__AdjustOnDamage takes Damage d returns nothing
    local Attack a = d
    local integer point2D = GetHandleId(d.weaponType)
    local integer tablePoint = point2D / 2
    local integer trueWeapon
    local UnitData id = GetUnitUserData(d.sourceUnit)
    local TableArray t = id.table

    //A simple flag to notify that the attack actually hit something.
    set t[tablePoint].boolean[RESOLVED_INDEX] = true

    set a.attackHashKey = t[tablePoint]
    set a.attackTarget = t[tablePoint].unit[TARGET_INDEX]
    set a.isPrimaryAttack = tablePoint * 2 == point2D

    if a.isPrimaryAttack then
        set trueWeapon = id.attack1
    else
        set trueWeapon = id.attack2
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
    set udg_DamageHashKeyForAttack  = Attack(Damage.index).attackHashKey
//! endtextmacro

private function AssignAttacks takes UnitData id returns nothing
    set id.attack1 = BlzGetUnitWeaponIntegerField(/*
        */ id.unit,/*
        */ UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, /*
        */ 0 /*
    */)
    set id.attack2 = BlzGetUnitWeaponIntegerField(/*
        */ id.unit,/*
        */ UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, /*
        */ 1 /*
    */)
endfunction

private function OnUnitAttacked takes nothing returns boolean
    local unit attackedUnit = GetTriggerUnit()
    local unit attacker = GetAttacker()
    local UnitData id = GetUnitUserData(attacker)
    local TableArray t = id.table
    local integer point

    if t == 0 then
        // There are 24 different weapon types, so to track
        // primary attack and secondary attack, we can only
        // have 12 unique simultanous attacks per attacker.
        set t = TableArray[12]
        set id.table = t
        call AssignAttacks(id)

        static if USE_GUI_HASH then
            if udg_AttackIndexerHash == null then
                set udg_AttackIndexerHash = InitHashtable()
            endif
        endif
    endif

    // The hashtable will initialize point first to 0.
    set point = id.points

    if id.circled then
        if not t[point].boolean[RESOLVED_INDEX] then
            call BJDebugMsg("The attack " + I2S(point) + " has either missed, or the unit is attacking too quickly for Attack Indexer to keep up with.")
        endif

        // Clean old data from 12 attacks ago.
        call t[point].flush()
        static if USE_GUI_HASH then
            call FlushChildHashtable(udg_AttackIndexerHash, t[point])
        endif
    endif

    if point < 11 then
        set id.points = point + 1
    else
        // Wrap around so as to recycle -12th indices.
        set id.points = 0
        set id.circled = true
    endif

    // I'd like to allow the user to use the normal 'Unit is Attacked' event here.
    // Therefore, to avoid recursion issues, this variable must be attached to the
    // custom value of the attacking unit.
    set udg_AttackEventHashKey[id] = t[point]

    set t[point].unit[TARGET_INDEX] = attackedUnit

    call BlzSetUnitWeaponIntegerField(/*
        */ attacker, /*
        */ UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, /*
        */ 0, /*
        */ point * 2 /*
    */)
    call BlzSetUnitWeaponIntegerField(/*
        */ attacker, /*
        */ UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, /*
        */ 1, /*
        */ point * 2 + 1 /*
    */)

    set attackedUnit = null
    set attacker = null
    return false
endfunction

private function OnUnitTransformed takes nothing returns boolean
    local UnitData id = udg_UDex
    local Table t = id.table
    if t > 0 then
        call AssignAttacks(id)
    endif
    return false
endfunction

private function OnUnitRemoved takes nothing returns boolean
    local integer i = 0
    local UnitData id = udg_UDex
    if id.table > 0 then
        // Clear out data from memory
        call id.table.flush()

        static if USE_GUI_HASH then
            loop
                call FlushChildHashtable(udg_AttackIndexerHash, id.table[i])
                exitwhen i == 11
                set i = i + 1
            endloop
        endif

        set id.table = 0
        set id.points = 0
        set id.circled = false
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

    set t = null
endfunction

endlibrary
