library AttackIndexer requires Table
// vJass version 1.1.0.3

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
    private constant boolean DEBUG = true

    // Attack data structure stored in TableArray[0-11]
    private constant integer TARGET_INDEX   = -1
    private constant integer RESOLVED_INDEX = -2
endglobals

private struct UnitData extends array
    TableArray tableArray
    integer points
    boolean circled
    integer attack1
    integer attack2

    method operator unit takes nothing returns unit
        return udg_UDexUnits[this]
    endmethod

    method assignAttackIndices takes nothing returns nothing
        set this.attack1 = BlzGetUnitWeaponIntegerField(/*
            */ this.unit,/*
            */ UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, /*
            */ 0 /*
        */)
        set this.attack2 = BlzGetUnitWeaponIntegerField(/*
            */ this.unit,/*
            */ UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, /*
            */ 1 /*
        */)
    endmethod

    static method onUnitAttacked takes nothing returns boolean
        local unit attackedUnit = GetTriggerUnit()
        local unit attacker = GetAttacker()
        local thistype this = GetUnitUserData(attacker)
        local TableArray tableArray = this.tableArray
        local integer point

        if tableArray == 0 then
            // There are 24 different weapon types, so to track
            // primary attack and secondary attack, we can only
            // have 12 unique simultanous attacks per attacker.
            set tableArray = TableArray[12]
            set this.tableArray = tableArray
            call this.assignAttackIndices()

            static if USE_GUI_HASH then
                if udg_AttackIndexerHash == null then
                    set udg_AttackIndexerHash = InitHashtable()
                endif
            endif
        endif

        // The hashtable will initialize point first to 0.
        set point = this.points

        if this.circled then
            static if DEBUG then
                if not tableArray[point].boolean[RESOLVED_INDEX] then
                    call BJDebugMsg("The attack " + I2S(point) + " has either missed, or the unit is attacking too quickly for Attack Indexer to keep up with.")
                endif
            endif

            // Clean old data from 12 attacks ago.
            call tableArray[point].flush()
            static if USE_GUI_HASH then
                call FlushChildHashtable(udg_AttackIndexerHash, tableArray[point])
            endif
        endif

        if point < 11 then
            set this.points = point + 1
        else
            // Wrap around so as to recycle -12th indices.
            set this.points = 0
            set this.circled = true
        endif

        // I'd like to allow the user to use the normal 'Unit is Attacked' event here.
        // Therefore, to avoid recursion issues, this variable must be attached to the
        // custom value of the attacking unit.
        set udg_AttackEventHashKey[this] = tableArray[point]

        set tableArray[point].unit[TARGET_INDEX] = attackedUnit

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
    endmethod

    static method onUnitRemoved takes nothing returns boolean
        local integer hashIndex = 0
        local thistype this = udg_UDex
        if this.tableArray != 0 then
            // Clear out data from memory
            call this.tableArray.flush()

            static if USE_GUI_HASH then
                loop
                    call FlushChildHashtable(udg_AttackIndexerHash, this.tableArray[hashIndex])
                    exitwhen hashIndex == 11
                    set hashIndex = hashIndex + 1
                endloop
            endif

            set this.tableArray = 0
            set this.points = 0
            set this.circled = false
        endif
        return false
    endmethod

    static method onUnitTransformed takes nothing returns boolean
        local thistype this = udg_UDex
        if this.tableArray > 0 then
            call this.assignAttackIndices()
        endif
        return false
    endmethod

    static method onInit takes nothing returns nothing
        local trigger trig = CreateTrigger()
        call TriggerRegisterAnyUnitEventBJ(trig, EVENT_PLAYER_UNIT_ATTACKED)
        call TriggerAddCondition(trig, Filter(function thistype.onUnitAttacked))

        set trig = CreateTrigger()
        call TriggerRegisterVariableEvent(trig, "udg_UnitIndexEvent", EQUAL, 2.00)
        call TriggerAddCondition(trig, Filter(function thistype.onUnitRemoved))

        set trig = CreateTrigger()
        call TriggerRegisterVariableEvent(trig, "udg_UnitTypeEvent", EQUAL, 1.00)
        call TriggerAddCondition(trig, Filter(function thistype.onUnitTransformed))

        set trig = null
    endmethod
endstruct

struct Attack extends array
    unit attackTarget
    boolean isPrimaryAttack

    // vJass users will have direct access to this, so they can use it with Table.
    // Main thing to consider is to avoid clashing indices, so I recommend either
    // using StringHash or a bucket of shared indices across a map's systems.
    Table attackHashKey

    // Only to be used internally by Damage Engine
    method adjustOnDamage takes nothing returns nothing
        local Damage damageData = this
        local integer point2D = GetHandleId(damageData.weaponType)
        local integer tablePoint = point2D / 2
        local integer trueWeapon
        local UnitData unitData = GetUnitUserData(damageData.sourceUnit)
        local TableArray tableArray = unitData.tableArray

        //A simple flag to notify that the attack actually hit something.
        //I feel that this is mainly useful for debugging.
        set tableArray[tablePoint].boolean[RESOLVED_INDEX] = true

        set this.attackHashKey = tableArray[tablePoint]
        set this.attackTarget = tableArray[tablePoint].unit[TARGET_INDEX]
        set this.isPrimaryAttack = tablePoint * 2 == point2D

        if this.isPrimaryAttack then
            set trueWeapon = unitData.attack1
        else
            set trueWeapon = unitData.attack2
        endif

        // Put the weapon type back to normal; this means
        // that the whole experience is un-marred despite
        // this hack.
        set damageData.weaponType = ConvertWeaponType(trueWeapon)
    endmethod
endstruct

//! textmacro ATTACK_INDEXER_ADJUSTMENTS
    call Attack(d).adjustOnDamage()
//! endtextmacro

//! textmacro ATTACK_INDEXER_GUI_VARS
    set udg_DamageEventAttackTarget = Attack(Damage.index).attackTarget
    set udg_DamageFromPrimaryAttack = Attack(Damage.index).isPrimaryAttack
    set udg_DamageHashKeyForAttack  = Attack(Damage.index).attackHashKey
//! endtextmacro

endlibrary
