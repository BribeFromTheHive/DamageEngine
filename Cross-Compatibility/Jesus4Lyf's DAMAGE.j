library Damage requires DamageEngine
// Jesus4Lyf's DAMAGE library, made fully Damage Engine compatible. Version 1.0.0.0
// Original: https://www.thehelper.net/threads/damage.117041/
    public function RegisterEvent takes trigger whichTrigger returns nothing
        call TriggerRegisterDamageEngine(whichTrigger, "Mod", 4.00)
    endfunction
    public function RegisterZeroEvent takes trigger whichTrigger returns nothing
        call TriggerRegisterDamageEngine(whichTrigger, "", 0.00)
    endfunction
    public function GetType takes nothing returns damagetype
        return Damage.index.damageType
    endfunction
    public function IsAttack takes nothing returns boolean
        return udg_IsDamageAttack
    endfunction
    public function Block takes real value returns nothing
        set Damage.amount = Damage.amount - value
    endfunction
    public function BlockAll takes nothing returns nothing
        set Damage.amount = 0.00
        set udg_DamageEventOverride = true
    endfunction
    public function EnableEvent takes boolean b returns nothing
        set Damage.enabled = b
    endfunction
 
    function UnitDamageTargetEx takes unit src, unit tgt, real amt, boolean a, boolean r, attacktype at, damagetype dt, weapontype wt returns nothing
        call Damage.apply(src, tgt, amt, a, r, at, dt, wt)
    endfunction
 
    //! textmacro Damage__DealTypeFunc takes NAME, TYPE
        public function $NAME$ takes unit source, unit target, real amount returns nothing
            call Damage.apply(source, target, amount, false, false, null, $TYPE$, null)
        endfunction
        public function Is$NAME$ takes nothing returns boolean
            return Damage.index.damageType == $TYPE$
        endfunction
    //! endtextmacro
    //! runtextmacro Damage__DealTypeFunc("Pure","DAMAGE_TYPE_UNIVERSAL")
    //! runtextmacro Damage__DealTypeFunc("Spell","DAMAGE_TYPE_MAGIC")
    public function Physical takes unit source, unit target, real amount, attacktype whichType, boolean attack, boolean ranged returns nothing
        call Damage.apply(source, target, amount, attack, ranged, whichType, DAMAGE_TYPE_NORMAL, null)
    endfunction
    public function IsPhysical takes nothing returns boolean
        return Damage.index.damageType == DAMAGE_TYPE_NORMAL
    endfunction
endlibrary
