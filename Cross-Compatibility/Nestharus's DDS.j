library DDS requires DamageEngine
// Nestharus's Damage system, partially* made Damage Engine compatible. Version 1.0.0.0
// Original: https://github.com/nestharus/JASS/tree/master/jass/Systems/DDS
//*Incorporates the core elements of Nestharus's DDS's API
//Event registration only works via Module interface as yucky Trigger syntax is ignored.
private struct S extends array
    static constant integer SPELL    = 0
    static constant integer PHYSICAL = 1
    static constant integer CODE     = 2
endstruct
struct DDS extends array
    readonly static S Archetype = 0
    static method operator archetype takes nothing returns integer
        if udg_IsDamageCode then
            return S.CODE
        elseif udg_IsDamageSpell then
            return S.SPELL
        endif
        return S.PHYSICAL
    endmethod
    static method operator damageCode= takes integer i returns nothing
        set udg_NextDamageType = udg_DamageTypeCode
    endmethod
    static method operator damageCode takes nothing returns integer
        return GetUnitUserData(udg_DamageEventTarget)
    endmethod
    static method operator source takes nothing returns unit
        return udg_DamageEventSource
    endmethod
    static method operator sourceId takes nothing returns integer
        return GetUnitUserData(udg_DamageEventSource)
    endmethod
    static method operator target takes nothing returns unit
        return udg_DamageEventTarget
    endmethod
    static method operator targetId takes nothing returns integer
        return GetUnitUserData(udg_DamageEventTarget)
    endmethod
    static method operator damage takes nothing returns real
        return Damage.amount
    endmethod
    static method operator damage= takes real r returns nothing
        set Damage.amount = r
    endmethod
    static method operator damageOriginal takes nothing returns real
        return udg_DamageEventPrevAmt
    endmethod
    static method operator damageModifiedAmount takes nothing returns real
        return Damage.amount - udg_DamageEventPrevAmt
    endmethod
    static method operator sourcePlayer takes nothing returns player
        return GetOwningPlayer(Damage.source)
    endmethod
    static method operator targetPlayer takes nothing returns player
        return GetOwningPlayer(Damage.target)
    endmethod
    method operator enabled= takes boolean b returns nothing
        set Damage.enabled = b
    endmethod
    method operator enabled takes nothing returns boolean
        return Damage.enabled
    endmethod
endstruct
module DDS
  private static delegate DDS dds = 0
  static if thistype.onDamage.exists then
    private static method preOnDamage takes nothing returns nothing
        call thistype(DDS.targetId).onDamage()
    endmethod
  endif
  static if thistype.onDamageOutgoing.exists then
    private static method preOnDamageOutgoing takes nothing returns nothing
        call thistype(DDS.sourceId).onDamageOutgoing()
    endmethod
  endif
  static if not thistype.onDamageBefore.exists and not thistype.onDamageAfter.exists and not thistype.onDamage.exists and not thistype.onDamageOutgoing.exists then
  else
    private static method onInit takes nothing returns nothing
      static if thistype.onDamageBefore.exists then
        call RegisterDamageEngine(function thistype.onDamageBefore, "Mod", 1.00)
      endif
      static if thistype.onDamageAfter.exists then
        call RegisterDamageEngine(function thistype.onDamageAfter, "Mod", 4.10)
      endif
      static if thistype.onDamage.exists then
        call RegisterDamageEngine(function thistype.preOnDamage, "Mod", 4.00)
      endif
      static if thistype.onDamageOutgoing.exists then
        call RegisterDamageEngine(function thistype.preOnDamageOutgoing, "Mod", 4.00)
      endif
    endmethod
  endif
endmodule
endlibrary
