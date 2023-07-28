library AttackIndexer initializer Init requires Table
// vJass version 1.1.0.1

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

    // Indexed to UnitUserData from UnitEvent:
    private TableArray array table
    private integer array points

    // UnitData structure
    private integer array attack1
    private integer array attack2

    // AttackData structure
    private constant integer TARGET_INDEX = -1 //stored in TableArray[0-11]
endglobals

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
    local integer id = GetUnitUserData(d.sourceUnit)
    local TableArray t = table[id]

    set a.attackHashKey = t[tablePoint]
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
    set udg_DamageHashKeyForAttack  = Attack(Damage.index).attackHashKey
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
        set t = TableArray[12]
        set table[id] = t
        call AssignAttacks(id)

        static if USE_GUI_HASH then
            if udg_AttackIndexerHash == null then
                set udg_AttackIndexerHash = InitHashtable()
            endif
        endif
    endif

    // The hashtable will initialize point first to 0.
    set point = points[id]

    // Clean any old data from the -12th attack.
    call t[point].flush()
    static if USE_GUI_HASH then
        call FlushChildHashtable(udg_AttackIndexerHash, t[point])
    endif

    // I'd like to allow the user to use the normal 'Unit is Attacked' event here.
    // Therefore, to avoid recursion issues, this variable must be attached to the
    // custom value of the attacking unit.
    set udg_AttackEventHashKey[id] = t[point]

    set t[point].unit[TARGET_INDEX] = attackedUnit

    call BlzSetUnitWeaponIntegerField(attacker, UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, 0, point * 2)
    call BlzSetUnitWeaponIntegerField(attacker, UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, 1, point * 2 + 1)

    set point = point + 1
    if point > 11 then
        // Wrap around so as to recycle -12th indices.
        set point = 0
    endif
    set points[id] = point

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
    local integer i = 0
    if table[udg_UDex] > 0 then
        // Clear out data from memory
        call table[udg_UDex].flush()

        static if USE_GUI_HASH then
            loop
                call FlushChildHashtable(udg_AttackIndexerHash, table[udg_UDex][i])
                exitwhen i == 11
                set i = i + 1
            endloop
        endif

        set table[udg_UDex] = 0
        set points[udg_UDex] = 0
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
