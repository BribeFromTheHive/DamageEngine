library_once DamageEvent requires DamageEngine
// Flux's DamagePackage, made fully Damage Engine compatible. Version 1.0.0.0
// Original: https://www.hiveworkshop.com/threads/damagepackage.287101/
endlibrary
library_once DamageModify uses DamageEvent
endlibrary
globals
    constant integer DAMAGE_TYPE_PHYSICAL = 1
    constant integer DAMAGE_TYPE_MAGICAL = 2
endglobals
//! textmacro DAMAGE_EVENT_STRUCT_PLUGIN_DMGPKG
static method operator type takes nothing returns integer
    if udg_IsDamageSpell then
        return DAMAGE_TYPE_MAGICAL
    endif
    return DAMAGE_TYPE_PHYSICAL
endmethod
static method registerTrigger takes trigger t returns nothing
    call DamageTrigger.registerTrigger(t, "", 1.00)
endmethod
static method unregisterTrigger takes trigger t returns nothing
    call DamageTrigger.unregister(t, "", 1.00, true)
endmethod
static method register takes code c returns nothing
    call registerTrigger(DamageTrigger[c])
endmethod
static method registerModifierTrigger takes trigger t returns nothing
    call DamageTrigger.registerTrigger(t, "Mod", 4.00)
endmethod
static method unregisterModifierTrigger takes trigger t returns nothing
    call DamageTrigger.unregister(t, "Mod", 4.00, true)
endmethod
static method registerModifier takes code c returns nothing
    call registerModifierTrigger(DamageTrigger[c])
endmethod
static method lockAmount takes nothing returns nothing
    set udg_DamageEventOverride = true
endmethod
//! endtextmacro
 
