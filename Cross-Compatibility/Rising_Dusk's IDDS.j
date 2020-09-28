library IntuitiveDamageSystem requires DamageEngine
// Rising_Dusk's IDDS - made fully Damage Engine compatible. Version 1.0.0.1
// Original: http://www.wc3c.net/showthread.php?t=100618
globals
    private  integer       DamageTypeCount     = 4
    constant integer       DAMAGE_TYPE_ATTACK  = 100
    constant integer       DAMAGE_TYPE_IGNORED = 101
    constant integer       DAMAGE_TYPE_SPELL   = 102
    constant integer       DAMAGE_TYPE_EXTRA   = 103
endglobals
    function RegisterDamageType takes nothing returns integer
        local integer i = DamageTypeCount
        set DamageTypeCount = DamageTypeCount + 1
        return 100 + i
    endfunction
    function IgnoreHigherPriority takes nothing returns nothing
        set udg_DamageEventOverride = true
    endfunction
    function SetDamage takes real dmg returns nothing
        set Damage.amount = dmg //Unlike with IDDS this WILL actually change the damage dealt
    endfunction
    function SetDamageType takes integer t returns nothing
        set Damage.index.userType = t
    endfunction
    function GetTriggerDamageSource takes nothing returns unit
        return udg_DamageEventSource
    endfunction
    function GetTriggerDamageTarget takes nothing returns unit
        return udg_DamageEventTarget
    endfunction
    function GetTriggerDamageBase takes nothing returns real
        return udg_DamageEventPrevAmt
    endfunction
    function GetTriggerDamage takes nothing returns real
        return Damage.amount
    endfunction
    function GetTriggerDamageType takes nothing returns integer
        return udg_DamageEventType
    endfunction
 
    function GetTriggerPriority takes trigger t returns integer
        local DamageTrigger index = DamageTrigger.getIndex(t, "Mod", 4.00)
        if index == 0 then
            return -1
        endif
        return R2I(index.weight - 4.00)
    endfunction
 
    function TriggerRegisterDamageEvent takes trigger t, integer priority returns nothing
        call TriggerRegisterDamageEngine(t, "Mod", 4.00 + priority)
    endfunction
 
    function TriggerUnregisterDamageEvent takes trigger t returns nothing
        call DamageTrigger.unregister(t, "Mod", 4.00, true)
    endfunction
 
    function TriggerSetPriority takes trigger t, integer priority returns nothing
        call DamageTrigger.unregister(t, "Mod", 4.00, false)
        call TriggerRegisterDamageEvent(t, priority)
    endfunction
 
    //The below function will actually use both DamageEngine's defined types as well as those of IDDS itself.
    function UnitDamageTargetEx takes unit s, unit t, real d, attacktype at, integer dt, boolean ca returns nothing
        if dt == DAMAGE_TYPE_ATTACK then
            set udg_NextDamageIsAttack = true
        endif
        set udg_NextDamageType = dt
        set Damage.enabled = dt != DAMAGE_TYPE_IGNORED
        if ca then
            call Damage.apply(s, t, d, udg_NextDamageIsAttack, false, at, DAMAGE_TYPE_NORMAL, null)
        else
            call Damage.apply(s, t, d, udg_NextDamageIsAttack, false, at, DAMAGE_TYPE_UNIVERSAL, null)
        endif
        set Damage.enabled = true
    endfunction
endlibrary
