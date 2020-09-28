//GDD Compatibility for Damage Engine 5.0 and prior
//globals
//    real udg_GDD_Event = 0
//    real udg_GDD_Damage = 0
//    unit udg_GDD_DamagedUnit = null
//    unit udg_GDD_DamageSource = null
//endglobals
//===========================================================================
function GDD_Event takes nothing returns boolean
    local unit s = udg_GDD_DamageSource
    local unit t = udg_GDD_DamagedUnit
    local real v = udg_GDD_Damage
    set udg_GDD_DamageSource = udg_DamageEventSource
    set udg_GDD_DamagedUnit = udg_DamageEventTarget
    set udg_GDD_Damage = udg_DamageEventAmount
    set udg_GDD_Event = 1
    set udg_GDD_Event = 0
    set udg_GDD_DamageSource = s
    set udg_GDD_DamagedUnit = t
    set udg_GDD_Damage = v
    set s = null
    set t = null
    return false
endfunction
//===========================================================================
function InitTrig_GUI_Friendly_Damage_Detection takes nothing returns nothing
    local trigger t = CreateTrigger()
    call TriggerRegisterVariableEvent(t, "udg_DamageEvent", EQUAL, 1)
    call TriggerRegisterVariableEvent(t, "udg_DamageEvent", EQUAL, 2)
    call TriggerAddCondition(t, Filter(function GDD_Event))
    set t = null
endfunction
