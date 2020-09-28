// Weep's GDD, made fully Damage Engine compatible. Version 2.1.1.0
// Original: https://www.hiveworkshop.com/threads/gui-friendly-damage-detection-v1-2-1.149098/
//! textmacro DAMAGE_EVENT_VARS_PLUGIN_GDD
    set udg_GDD_DamageSource = udg_DamageEventSource
    set udg_GDD_DamagedUnit = udg_DamageEventTarget
    set udg_GDD_Damage = udg_DamageEventAmount
//! endtextmacro
//! textmacro DAMAGE_EVENT_REG_PLUGIN_GDD
    if var == "udg_GDD_Event" then
        set root = DamageTrigger.DAMAGE
    endif
//! endtextmacro
