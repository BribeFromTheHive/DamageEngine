library Evasion requires DamageInterface
    /* ------------------------ Evasion v1.3 by Chopinski ----------------------- */
    //Edited by Bribe for compatibility with Damage Engine
    //! novjass
   
        Evasion implements an easy way to register and detect a custom evasion event.
   
        It works by monitoring custom evasion and missing values given to units,
        and nulling damage when the odds given occurs.
   
        It will only detect custom evasion, so all evasion or miss values given to a
        unit must be done so using the public API provided by this system.
   
        *Evasion requires DamageEvents. Do not use TriggerSleepAction() with Evasion.
   
        The API:
            To register a function to run when an unit evades an attack simply do:
                call RegisterEvasionEvent(function YourFunction)
                    -> YourFunction will run when a unit evades an attack.
   
            function GetMissingUnit takes nothing returns unit
                -> Returns the unit missing the attack
       
            function GetEvadingUnit takes nothing returns unit
                -> Returns the unit evading the attack
       
            function GetEvadedDamage takes nothing returns real
                -> Returns the amount of evaded damage
       
            function GetUnitEvasionChance takes unit u returns real
                -> Returns this system amount of evasion chance given to a unit
       
            function GetUnitMissChance takes unit u returns real
                -> Returns this system amount of miss chance given to a unit
       
            function SetUnitEvasionChance takes unit u, real chance returns nothing
                -> Set's unit evasion chance to specified amount
       
            function SetUnitMissChance takes unit u, real chance returns nothing
                -> Set's unit miss chance to specified amount
       
            function UnitAddEvasionChance takes unit u, real chance returns nothing
                -> Add to a unit Evasion chance the specified amount
       
            function UnitAddMissChance takes unit u, real chance returns nothing
                -> Add to a unit Miss chance the specified amount
       
            function UnitAddEvasionChanceTimed takes unit u, real amount, real duration returns nothing
                -> Add to a unit Evasion chance the specified amount for a given period
       
            function UnitAddMissChanceTimed takes unit u, real amount, real duration returns nothing
                -> Add to a unit Miss chance the specified amount for a given period
       
            function MakeUnitNeverMiss takes unit u, boolean flag returns nothing
                -> Will make a unit never miss attacks no matter the evasion chance of the attacked unit
       
            function DoUnitNeverMiss takes unit u returns boolean
                -> Returns true if the unit will never miss an attack
   
    //! endnovjass
    /* ----------------------------------- END ---------------------------------- */

        private struct Evasion
            //Text size of Critical Event
            static constant real text_size = 0.019
            //--------------------------------------------------
            readonly static trigger Evasion = CreateTrigger()
            static timer t = CreateTimer()
            static integer didx = -1
            static thistype array data
            //--------------------------------------------------
            static unit EvasionSource
            static unit EvasionTarget
            static real EvadedDamage
            static real array EvasionChance
            static real array MissChance
            static integer array NeverMiss
            //--------------------------------------------------
   
            unit    u
            real    amount
            real    ticks
            boolean evasion
   
            method destroy takes nothing returns nothing
                if didx == -1 then
                    call PauseTimer(t)
                endif
   
                set this.u     = null
                set this.ticks = 0
                call this.deallocate()
            endmethod
   
            static method GetEvasionChance takes unit u returns real
                return EvasionChance[GetUnitUserData(u)]
            endmethod
   
            static method GetMissChance takes unit u returns real
                return MissChance[GetUnitUserData(u)]
            endmethod
   
            static method SetEvasionChance takes unit u, real value returns nothing
                set EvasionChance[GetUnitUserData(u)] = value
            endmethod
   
            static method SetMissChance takes unit u, real value returns nothing
                set MissChance[GetUnitUserData(u)] = value
            endmethod
   
            static method OnPeriod takes nothing returns nothing
                local integer  i = 0
                local thistype this
               
                loop
                    exitwhen i > didx
                        set this = data[i]
                        set this.ticks = this.ticks - 1
   
                        if this.ticks <= 0 then
                            if this.evasion then
                                call SetEvasionChance(this.u, GetEvasionChance(this.u) - this.amount)
                            else
                                call SetMissChance(this.u, GetMissChance(this.u) - this.amount)
                            endif
   
                            set  data[i] = data[didx]
                            set  didx    = didx - 1
                            set  i       = i - 1
                            call this.destroy()
                        endif
                    set i = i + 1
                endloop
            endmethod
   
            static method AddTimed takes unit u, real amount, real duration, boolean evasion returns nothing
                local thistype this = thistype.allocate()
   
                set this.u       = u
                set this.amount  = amount
                set this.ticks   = duration/0.03125000
                set this.evasion = evasion
                set didx         = didx + 1
                set data[didx]   = this
   
                if evasion then
                    call SetEvasionChance(u, GetEvasionChance(u) + amount)
                else
                    call SetMissChance(u, GetMissChance(u) + amount)
                endif
               
                if didx == 0 then
                    call TimerStart(t, 0.03125000, true, function thistype.OnPeriod)
                endif
            endmethod
   
            static method EvasionText takes unit whichUnit, string text, real duration, integer red, integer green, integer blue, integer alpha returns nothing
                local texttag tx = CreateTextTag()
               
                call SetTextTagText(tx, text, text_size)
                call SetTextTagPosUnit(tx, whichUnit, 0)
                call SetTextTagColor(tx, red, green, blue, alpha)
                call SetTextTagLifespan(tx, duration)
                call SetTextTagVelocity(tx, 0.0, 0.0355)
                call SetTextTagPermanent(tx, false)
               
                set tx = null
            endmethod
   
            static method OnDamage takes nothing returns nothing
                local unit     src    = Damage.index.source
                local unit     tgt    = Damage.index.target
                //----------------------------------------------
                local real     damage = Damage.index.damage
                //----------------------------------------------
                local integer  sIdx   = GetUnitUserData(src)
                local integer  tIdx   = GetUnitUserData(tgt)
                //----------------------------------------------

                if damage > 0 and not (NeverMiss[sIdx] > 0) then
                    if GetRandomReal(0, 100) <= EvasionChance[tIdx] or GetRandomReal(0, 100) <= MissChance[sIdx] then
                        set udg_DamageEventOverride = true
                        set EvasionSource = src
                        set EvasionTarget = tgt
                        set EvadedDamage  = damage
   
                        call TriggerEvaluate(Evasion)
                        set Damage.index.weaponType = WEAPON_TYPE_WHOKNOWS
                        set Damage.index.damage = 0.00
                        call EvasionText(src, "miss", 1.5, 255, 0, 0, 255)
   
                        set EvasionSource = null
                        set EvasionTarget = null
                        set EvadedDamage  = 0.0
                    endif
                endif
            endmethod
   
            static method Register takes code c returns nothing
                call TriggerAddCondition(Evasion, Filter(c))
            endmethod
   
            static method onInit takes nothing returns nothing
                call RegisterAttackDamagingEvent(function thistype.OnDamage)
            endmethod
        endstruct
   
        /* -------------------------------------------------------------------------- */
        /*                               Public JASS API                              */
        /* -------------------------------------------------------------------------- */
   
        function RegisterEvasionEvent takes code c returns nothing
            call Evasion.Register(c)
        endfunction
   
        function GetMissingUnit takes nothing returns unit
            return Evasion.EvasionSource
        endfunction
   
        function GetEvadingUnit takes nothing returns unit
            return Evasion.EvasionTarget
        endfunction
   
        function GetEvadedDamage takes nothing returns real
            return Evasion.EvadedDamage
        endfunction
   
        function GetUnitEvasionChance takes unit u returns real
            return Evasion.GetEvasionChance(u)
        endfunction
   
        function GetUnitMissChance takes unit u returns real
            return Evasion.GetMissChance(u)
        endfunction
   
        function SetUnitEvasionChance takes unit u, real chance returns nothing
            call Evasion.SetEvasionChance(u, chance)
        endfunction
   
        function SetUnitMissChance takes unit u, real chance returns nothing
            call Evasion.SetMissChance(u, chance)
        endfunction
   
        function UnitAddEvasionChance takes unit u, real chance returns nothing
            call Evasion.SetEvasionChance(u, Evasion.GetEvasionChance(u) + chance)
        endfunction
   
        function UnitAddMissChance takes unit u, real chance returns nothing
            call Evasion.SetMissChance(u, Evasion.GetMissChance(u) + chance)
        endfunction
   
        function UnitAddEvasionChanceTimed takes unit u, real amount, real duration returns nothing
            call Evasion.AddTimed(u, amount, duration, true)
        endfunction
   
        function UnitAddMissChanceTimed takes unit u, real amount, real duration returns nothing
            call Evasion.AddTimed(u, amount, duration, false)
        endfunction
   
        function MakeUnitNeverMiss takes unit u, boolean flag returns nothing
            if flag then
                set Evasion.NeverMiss[GetUnitUserData(u)] = Evasion.NeverMiss[GetUnitUserData(u)] + 1
            else
                set Evasion.NeverMiss[GetUnitUserData(u)] = Evasion.NeverMiss[GetUnitUserData(u)] - 1
            endif
        endfunction
   
        function DoUnitNeverMiss takes unit u returns boolean
            return Evasion.NeverMiss[GetUnitUserData(u)] > 0
        endfunction
endlibrary
