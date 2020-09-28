library StructuredDD requires DamageEngine
// Cokemonkey11's StructuredDD and DamageType - made fully Damage Engine compatible. Version 1.0.0.0
// Originals: https://www.hiveworkshop.com/threads/system-structureddd-structured-damage-detection.216968/
// https://www.hiveworkshop.com/threads/system-damagetype-structureddd-extension.228883/
    struct StructuredDD extends array
        static method addHandler takes code c returns nothing
            call RegisterDamageEngine(c, "Mod", 4.00)
        endmethod
    endstruct
endlibrary
library DamageType requires StructuredDD
    struct DamageType extends array
        static constant integer NULLED =-1
        static constant integer ATTACK = 0
        static constant integer SPELL  = 1
        static constant integer CODE   = 2
 
        static method get takes nothing returns integer
            if udg_IsDamageCode then
                return CODE
            elseif udg_IsDamageSpell then
                return SPELL
            elseif udg_DamageEventAmount == 0.00 then
                return NULLED
            endif
            return ATTACK
        endmethod
        static method dealCodeDamage takes unit s, unit t, real d returns nothing
            call Damage.apply(s, t, d, true, false, null, DAMAGE_TYPE_UNIVERSAL, null)
        endmethod
    endstruct
endlibrary
 
