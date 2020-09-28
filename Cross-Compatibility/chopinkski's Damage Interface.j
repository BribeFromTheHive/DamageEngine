library DamageInterface requires DamageEngine
// chopinkski's Damage Interface, made fully Damage Engine compatible. Version 1.0.0.0
// This resource inspired me to build new events into GUI and integrate other built-in filters
// Original: https://www.hiveworkshop.com/threads/damage-interface-v1-3.324257/
//! textmacro DAMAGE_EVENT_USER_STRUCT_PLUGIN_01
globals
    private keyword fillCache
endglobals
struct DamageI extends array
    readonly static damagetype damageType
    readonly static attacktype attackType
    readonly static unit       source
    readonly static unit       target
    readonly static player     sourcePlayer
    readonly static player     targetPlayer
    readonly static boolean    isEnemy
    readonly static boolean    isAlly
    readonly static boolean    isMelee
    readonly static boolean    isRanged
    readonly static boolean    isAttack
    readonly static boolean    isSpell
    readonly static boolean    isPure
    readonly static boolean    isEnhanced
    readonly static boolean    sourceIsHero
    readonly static boolean    targetIsHero
    readonly static boolean    structure
    readonly static boolean    magicImmune
    readonly static real       sourceX
    readonly static real       sourceY
    readonly static real       targetX
    readonly static real       targetY
    readonly static integer    sIdx
    readonly static integer    tIdx
    readonly static integer    sId
    readonly static integer    tId
 
    static method fillCache takes nothing returns nothing
        set damageType = Damage.index.damageType
        set attackType = Damage.index.attackType
        set source     = udg_DamageEventSource
        set target     = udg_DamageEventTarget
        set isAttack   = damageType == DAMAGE_TYPE_NORMAL
        set isSpell    = attackType == ATTACK_TYPE_NORMAL
        set isPure     = damageType == DAMAGE_TYPE_UNIVERSAL
        set isEnhanced = damageType == DAMAGE_TYPE_ENHANCED
        // You can comment-out the variables you dont want to be cached
        set sourcePlayer  = GetOwningPlayer(source)
        set targetPlayer  = GetOwningPlayer(target)
        set isEnemy       = IsUnitEnemy(target, sourcePlayer)
        set isAlly        = IsUnitAlly(target, sourcePlayer)
        set isMelee       = IsUnitType(source, UNIT_TYPE_MELEE_ATTACKER)
        set isRanged      = IsUnitType(source, UNIT_TYPE_RANGED_ATTACKER)
        set sourceIsHero  = IsUnitType(source, UNIT_TYPE_HERO)
        set targetIsHero  = IsUnitType(target, UNIT_TYPE_HERO)
        set structure     = IsUnitType(target, UNIT_TYPE_STRUCTURE)
        set magicImmune   = IsUnitType(target, UNIT_TYPE_MAGIC_IMMUNE)
        set sourceX       = GetUnitX(source)
        set sourceY       = GetUnitY(source)
        set targetX       = GetUnitX(target)
        set targetY       = GetUnitY(target)
        set sIdx          = GetUnitUserData(source)
        set tIdx          = GetUnitUserData(target)
        set sId           = GetHandleId(source)
        set tId           = GetHandleId(target)
    endmethod
endstruct
//! endtextmacro
//! textmacro DAMAGE_EVENT_PRE_VARS_PLUGIN_01
    call DamageI.fillCache()
//! endtextmacro
//! textmacro DAMAGE_EVENT_VARS_PLUGIN_01
    call DamageI.fillCache()
//! endtextmacro
 
//After armor events:
 
    function RegisterAttackDamageEvent takes code c returns nothing
        call RegisterDamageEngineEx(c, "Mod", 4.00, DamageEngine_FILTER_ATTACK)
    endfunction
 
    function RegisterSpellDamageEvent takes code c returns nothing
        call RegisterDamageEngineEx(c, "Mod", 4.00, DamageEngine_FILTER_SPELL)
    endfunction
 
    function RegisterPureDamageEvent takes code c returns nothing
        local DamageTrigger dt = RegisterDamageEngine(c, "Mod", 4.00)
        set dt.damageType = GetHandleId(DAMAGE_TYPE_UNIVERSAL)
        set dt.configured = true
    endfunction
 
    function RegisterEnhancedDamageEvent takes code c returns nothing
        local DamageTrigger dt = RegisterDamageEngine(c, "Mod", 4.00)
        set dt.damageType = GetHandleId(DAMAGE_TYPE_ENHANCED)
        set dt.configured = true
    endfunction
 
    function RegisterDamageEvent takes code c returns nothing
        call RegisterDamageEngine(c, "Mod", 4.00)
    endfunction
 
//Before armor events:
 
    function RegisterAttackDamagingEvent takes code c returns nothing
        call RegisterDamageEngineEx(c, "Mod", 1.00, DamageEngine_FILTER_ATTACK)
    endfunction
 
    function RegisterSpellDamagingEvent takes code c returns nothing
        call RegisterDamageEngineEx(c, "Mod", 1.00, DamageEngine_FILTER_SPELL)
    endfunction
 
    function RegisterPureDamagingEvent takes code c returns nothing
        local DamageTrigger dt = RegisterDamageEngine(c, "Mod", 1.00)
        set dt.damageType = GetHandleId(DAMAGE_TYPE_UNIVERSAL)
        set dt.configured = true
    endfunction
 
    function RegisterEnhancedDamagingEvent takes code c returns nothing
        local DamageTrigger dt = RegisterDamageEngine(c, "Mod", 1.00)
        set dt.damageType = GetHandleId(DAMAGE_TYPE_ENHANCED)
        set dt.configured = true
    endfunction
 
    function RegisterDamagingEvent takes code c returns nothing
        call RegisterDamageEngine(c, "Mod", 1.00)
    endfunction
endlibrary
