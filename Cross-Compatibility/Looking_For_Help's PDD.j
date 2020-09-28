library DamageEvent requires DamageEngine
// looking_for_help's PDD (both versions), made fully Damage Engine compatible. Version 3.0.4.0
// Original GUI: https://www.hiveworkshop.com/threads/physical-damage-detection-for-gui-v1-3-0-0.231846/
// Original vJass: https://www.hiveworkshop.com/threads/system-physical-damage-detection.228456/
//Un-comment the below block if you wish to remove the vJass syntax.
///*
globals
    constant integer PHYSICAL = 0
    constant integer SPELL = 1
    constant integer CODE = 2
endglobals
struct PDDS extends array
    static method operator source takes nothing returns unit
        return udg_DamageEventSource
    endmethod
    static method operator target takes nothing returns unit
        return udg_DamageEventTarget
    endmethod
    static method operator amount takes nothing returns real
        return Damage.amount
    endmethod
    static method operator amount= takes real r returns nothing
        set Damage.amount = r
    endmethod
    static method operator damageType takes nothing returns integer
        if udg_IsDamageCode then
            return CODE
        elseif udg_IsDamageSpell then
            return SPELL
        endif
        return PHYSICAL
    endmethod
endstruct
function AddDamageHandler takes code c returns nothing
    call RegisterDamageEngine(c, "Mod", 4.00)
endfunction
function RemoveDamageHandler takes code c returns nothing
    call DamageTrigger.unregister(DamageTrigger[c], "", 1.00, true)
endfunction
function GetUnitLife takes unit u returns real
    return GetWidgetLife(u)
endfunction
function SetUnitLife takes unit u, real r returns nothing
    call SetWidgetLife(u, r)
endfunction
function GetUnitMaxLife takes unit u returns real
    return GetUnitState(u, UNIT_STATE_MAX_LIFE)
endfunction
function UnitDamageTargetEx takes unit src, unit tgt, real amt, boolean a, boolean r, attacktype at, damagetype dt, weapontype wt returns nothing
    call Damage.apply(src, tgt, amt, a, r, at, dt, wt)
endfunction
//*/
//Un-comment the above block if you wish to remove the vJass syntax.
endlibrary
//Un-comment the below block if you wish to remove the GUI syntax.
///*
//! textmacro DAMAGE_EVENT_VARS_PLUGIN_PDD
    set udg_PDD_source = udg_DamageEventSource
    set udg_PDD_target = udg_DamageEventTarget
    if udg_IsDamageCode then
        set udg_PDD_damageType = udg_PDD_CODE
    elseif udg_IsDamageSpell then
        set udg_PDD_damageType = udg_PDD_SPELL
    else
        set udg_PDD_damageType = udg_PDD_PHYSICAL
    endif
//! endtextmacro
//! textmacro DAMAGE_EVENT_FILTER_PLUGIN_PDD
    if this.eventStr == "udg_PDD_damageEventTrigger" then
        set udg_PDD_amount = udg_DamageEventAmount
    endif
//! endtextmacro
//! textmacro DAMAGE_EVENT_MOD_PLUGIN_PDD
    if this.eventStr == "udg_PDD_damageEventTrigger" then
        set udg_DamageEventAmount = udg_PDD_amount
    endif
//! endtextmacro
//! textmacro DAMAGE_EVENT_REG_PLUGIN_GDD
    if var == "udg_PDD_damageEventTrigger" then
        set root = DamageTrigger.SHIELD
        if udg_PDD_CODE == 0 then
            set udg_PDD_SPELL = 1
            set udg_PDD_CODE = 2
        endif
    endif
//! endtextmacro
//*/
//Un-comment the above block if you wish to remove the GUI syntax.
