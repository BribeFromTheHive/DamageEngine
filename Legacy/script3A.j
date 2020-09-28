
//===========================================================================
// Damage Engine 3A.0.0.0 - a new type of Damage Engine for users who don't
// have access to the latest version of WarCraft 3, which incorporates new
// features to inherited from Damage Engine 5.7 by hooking TriggerRegisterVariableEvent.
// However, it requires having JassHelper installed.
//
// Stuff that doesn't work:
// - Pre-armor modification
// - Damage/Attack/Weapotype detection/modification
// - Armor/defense detection/modification
// - Melee/ranged detection
// - Filters for u.
// - Spirit link won't interact with custom damage.
// - Still needs workarounds for Anti-Magic Shell/Mana Shield/Life Drain/etc.
//
// Stuff that is changed from how it worked with 3.8:
// - Recursive damage now uses the Damage Engine 5 anti-recursion method. So
//   all recursive damage will be postponed until the sequence has completed.
// - No more need for using ClearDamageEvent
// - No more need to disable the DamageEventTrigger in order to avoid things
//   going recursively.
//
library DamageEngine
globals
    private timer           alarm           = CreateTimer()
    private boolean         alarmSet        = false
    //Values to track the original pre-spirit Link/defensive damage values
    private Damage          lastInstance    = 0
    private boolean         canKick         = false
    //These variables coincide with Blizzard's "limitop" type definitions so as to enable users (GUI in particular) with some nice performance perks.
    public constant integer FILTER_ATTACK   = 0     //LESS_THAN
    public constant integer FILTER_OTHER    = 2     //EQUAL
    public constant integer FILTER_SPELL    = 4     //GREATER_THAN
    public constant integer FILTER_CODE     = 5     //NOT_EQUAL
    public constant integer FILTER_MAX      = 6
    private integer         eventFilter     = FILTER_OTHER
    private constant integer LIMBO          = 16        //When manually-enabled recursion is enabled via DamageEngine_recurion, the engine will never go deeper than LIMBO.
    public boolean          inception       = false     //When true, it allows your trigger to potentially go recursive up to LIMBO. However it must be set per-trigger throughout the game and not only once per trigger during map initialization.
    private boolean         dreaming        = false
    private integer         sleepLevel      = 0
    private group           proclusGlobal   = CreateGroup() //track sources of recursion
    private group           fischerMorrow   = CreateGroup() //track targets of recursion
    private boolean         kicking         = false
    private boolean         eventsRun       = false
    private unit            protectUnit     = null
    private real            protectLife     = 0.00
    private boolean         blocked         = false
    private keyword         run
    private keyword         trigFrozen
    private keyword         levelsDeep
    private keyword         inceptionTrig
    private keyword         checkLife
    private keyword         lifeTrigger
endglobals
private function CheckAddUnitToEngine takes unit u returns boolean
    if GetUnitAbilityLevel(u, 'Aloc') > 0 then
    elseif not TriggerEvaluate(gg_trg_Damage_Engine_Config) then
    //Add some more elseifs to rule out stuff you don't want to get registered, such as:
    //elseif IsUnitType(u, UNIT_TYPE_STRUCTURE) then
    else
        return true
    endif
    return false
endfunction
struct DamageTrigger extends array
   
    //The below variables are constant
    readonly static thistype        MOD             = 1
    readonly static thistype        DAMAGE          = 5
    readonly static thistype        ZERO            = 6
    readonly static thistype        AFTER           = 7
    readonly static thistype        AOE             = 9
    private static integer          count           = 9
    static thistype                 lastRegistered  = 0
    private static thistype array   trigIndexStack
    static thistype                 eventIndex = 0
    static boolean array            filters
    readonly string                 eventStr
    readonly real                   weight
    readonly boolean                configured
    boolean                         usingGUI
    //The below variables are private
    private thistype                next
    private trigger                 rootTrig
    boolean                         trigFrozen      //Whether the trigger is currently disabled due to recursion
    integer                         levelsDeep      //How deep the user recursion currently is.
    boolean                         inceptionTrig   //Added in 5.4.2 to simplify the inception variable for very complex DamageEvent trigger.
   
    static method operator enabled= takes boolean b returns nothing
        if b then
            call EnableTrigger(udg_DamageEventTrigger)
        else
            call DisableTrigger(udg_DamageEventTrigger)
        endif
    endmethod
    static method operator enabled takes nothing returns boolean
        return IsTriggerEnabled(udg_DamageEventTrigger)
    endmethod
   
    static method setGUIFromStruct takes boolean full returns nothing
        set udg_DamageEventAmount       = Damage.index.damage
        set udg_DamageEventType         = Damage.index.userType
        set udg_DamageEventOverride     = Damage.index.override
        if full then
            set udg_DamageEventSource   = Damage.index.sourceUnit
            set udg_DamageEventTarget   = Damage.index.targetUnit
            set udg_DamageEventPrevAmt  = Damage.index.prevAmt
            set udg_IsDamageSpell       = Damage.index.isSpell
            //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_GDD()
            //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_PDD()
            //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_01()
            //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_02()
            //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_03()
            //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_04()
            //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_05()
        endif
    endmethod
    static method getVerboseStr takes string eventName returns string
        if eventName == "Modifier" or eventName == "Mod" then
            return "udg_DamageModifierEvent"
        endif
        return "udg_" + eventName + "DamageEvent"
    endmethod
    private static method getStrIndex takes string var, real lbs returns thistype
        local integer root = R2I(lbs)
        if var == "udg_DamageModifierEvent" then
            set root= MOD
        elseif var == "udg_DamageEvent" then
            if root == 2 or root == 0 then
                set root= ZERO
            else
                set root= DAMAGE //Above 0.00 but less than 2.00, generally would just be 1.00
            endif
        elseif var == "udg_AfterDamageEvent" then
            set root    = AFTER
        elseif var == "udg_AOEDamageEvent" then
            set root    = AOE
        else
            set root    = 0
            //! runtextmacro optional DAMAGE_EVENT_REG_PLUGIN_GDD()
            //! runtextmacro optional DAMAGE_EVENT_REG_PLUGIN_PDD()
            //! runtextmacro optional DAMAGE_EVENT_REG_PLUGIN_01()
            //! runtextmacro optional DAMAGE_EVENT_REG_PLUGIN_02()
            //! runtextmacro optional DAMAGE_EVENT_REG_PLUGIN_03()
            //! runtextmacro optional DAMAGE_EVENT_REG_PLUGIN_04()
            //! runtextmacro optional DAMAGE_EVENT_REG_PLUGIN_05()
        endif
        return root
    endmethod
    private method toggleAllFilters takes boolean flag returns nothing
        set filters[this + FILTER_ATTACK]   = flag
        set filters[this + FILTER_OTHER]    = flag
        set filters[this + FILTER_SPELL]    = flag
        set filters[this + FILTER_CODE]     = flag
    endmethod
    method operator filter= takes integer f returns nothing
        set this = this*FILTER_MAX
        if f == FILTER_OTHER then
            call this.toggleAllFilters(true)
        else
            if f == FILTER_ATTACK then
                set filters[this + FILTER_ATTACK]   = true
            else
                set filters[this + f] = true
            endif
        endif
    endmethod
    static method registerVerbose takes trigger whichTrig, string var, real lbs, boolean GUI, integer filt returns thistype
        local thistype index= getStrIndex(var, lbs)
        local thistype i    = 0
        local thistype id   = 0
     
        if index == 0 then
            return 0
        elseif lastRegistered.rootTrig == whichTrig and lastRegistered.usingGUI then
            set filters[lastRegistered*FILTER_MAX + filt] = true //allows GUI to register multiple different types of Damage filters to the same trigger
            return 0
        endif
     
        if trigIndexStack[0] == 0 then
            set count              = count + 1   //List runs from index 10 and up
            set id                 = count
        else
            set id                 = trigIndexStack[0]
            set trigIndexStack[0]  = trigIndexStack[id]
        endif
        set lastRegistered         = id
        set id.filter              = filt
        set id.rootTrig            = whichTrig
        set id.usingGUI            = GUI
        set id.weight              = lbs
        set id.eventStr            = var
     
        loop
            set i = index.next
            exitwhen i == 0 or lbs < i.weight
            set index = i
        endloop        
        set index.next = id
        set id.next    = i
     
        //call BJDebugMsg("Registered " + I2S(id) + " to " + I2S(index) + " and before " + I2S(i))
        return lastRegistered
    endmethod
    static method registerTrigger takes trigger t, string var, real lbs returns thistype
        return registerVerbose(t, DamageTrigger.getVerboseStr(var), lbs, false, FILTER_OTHER)
    endmethod
    private static thistype prev = 0
    static method getIndex takes trigger t, string eventName, real lbs returns thistype
        local thistype index = getStrIndex(getVerboseStr(eventName), lbs)
        loop
            set prev = index
            set index = index.next
            exitwhen index == 0 or index.rootTrig == t
        endloop
        return index
    endmethod
    static method unregister takes trigger t, string eventName, real lbs, boolean reset returns boolean
        local thistype index        = getIndex(t, eventName, lbs)
        if index == 0 then
            return false
        endif
        set prev.next               = index.next
         
        set trigIndexStack[index]   = trigIndexStack[0]
        set trigIndexStack[0]       = index
     
        if reset then
            set index.configured    = false
            set index               = index*FILTER_MAX
            call index.toggleAllFilters(false)
        endif
        return true
    endmethod
    static method damageUnit takes unit u, real life returns nothing
        call SetWidgetLife(u, RMaxBJ(life, 0.41))
        if life <= 0.405 then
            if udg_DamageEventType < 0 then
                call SetUnitExploded(u, true)
            endif
            //Kill the unit
            set DamageTrigger.enabled = false
            call UnitDamageTarget(udg_DamageEventSource, u, -999, false, false, null, DAMAGE_TYPE_UNIVERSAL, null)
            set DamageTrigger.enabled = true
        endif
    endmethod
    static method checkLife takes nothing returns boolean
        if protectUnit != null then
            if Damage.lifeTrigger != null then
                call DestroyTrigger(Damage.lifeTrigger)
                set Damage.lifeTrigger = null
            endif
            if GetUnitAbilityLevel(protectUnit, udg_DamageBlockingAbility) > 0 then
                call UnitRemoveAbility(protectUnit, udg_DamageBlockingAbility)
                call SetWidgetLife(protectUnit, protectLife)
            elseif udg_IsDamageSpell or blocked then
                call DamageTrigger.damageUnit(protectUnit, protectLife)
            endif
            if blocked then
                set blocked = false
            endif
            set protectUnit = null
            return true
        endif
        return false
    endmethod
    method run takes nothing returns nothing
        local integer cat = this
        local Damage d = Damage.index
        if cat == MOD or not udg_HideDamageFrom[GetUnitUserData(udg_DamageEventSource)] then
            set dreaming = true
            //call BJDebugMsg("Start of event running")
            loop                                  
                set this = this.next
                exitwhen this == 0
                if cat == MOD then
                    exitwhen d.override or udg_DamageEventOverride
                    exitwhen this.weight >= 4.00 and udg_DamageEventAmount <= 0.00
                endif
                set eventIndex = this
                if not this.trigFrozen and filters[this*FILTER_MAX + eventFilter] and IsTriggerEnabled(this.rootTrig) then
                    //! runtextmacro optional DAMAGE_EVENT_FILTER_PLUGIN_PDD()
                    //! runtextmacro optional DAMAGE_EVENT_FILTER_PLUGIN_01()
                    //! runtextmacro optional DAMAGE_EVENT_FILTER_PLUGIN_02()
                    //! runtextmacro optional DAMAGE_EVENT_FILTER_PLUGIN_03()
                    //! runtextmacro optional DAMAGE_EVENT_FILTER_PLUGIN_04()
                    //! runtextmacro optional DAMAGE_EVENT_FILTER_PLUGIN_05()
                 
                    if TriggerEvaluate(this.rootTrig) then
                        call TriggerExecute(this.rootTrig)
                    endif
                    if cat == MOD then
                        //! runtextmacro optional DAMAGE_EVENT_MOD_PLUGIN_PDD()
                        //! runtextmacro optional DAMAGE_EVENT_MOD_PLUGIN_01()
                        //! runtextmacro optional DAMAGE_EVENT_MOD_PLUGIN_02()
                        //! runtextmacro optional DAMAGE_EVENT_MOD_PLUGIN_03()
                        //! runtextmacro optional DAMAGE_EVENT_MOD_PLUGIN_04()
                        //! runtextmacro optional DAMAGE_EVENT_MOD_PLUGIN_05()
                        if this.usingGUI then
                            set d.damage        = udg_DamageEventAmount
                            set d.userType      = udg_DamageEventType
                            set d.override      = udg_DamageEventOverride
                        elseif this.next == 0 or this.next.usingGUI then //Might offer a slight performance improvement
                            call setGUIFromStruct(false)
                        endif
                    endif
                    call checkLife()
                endif
            endloop
            //call BJDebugMsg("End of event running")
            set dreaming                                = false
        endif
    endmethod
   
    static method finish takes nothing returns nothing
        if checkLife() and not blocked and udg_DamageEventAmount != 0.00 then
            call DamageTrigger.AFTER.run()
        endif
    endmethod
   
    static trigger array    autoTriggers
    static boolexpr array   autoFuncs
    static integer          autoN = 0
    static method operator [] takes code c returns trigger
        local integer i             = 0
        local boolexpr b            = Filter(c)
        loop
            if i == autoN then
                set autoTriggers[i] = CreateTrigger()
                set autoFuncs[i]    = b
                call TriggerAddCondition(autoTriggers[i], b)
                exitwhen true
            endif
            set i = i + 1
            exitwhen b == autoFuncs[i]
        endloop
        return autoTriggers[i]
    endmethod
endstruct
struct Damage extends array
    readonly unit           sourceUnit    //stores udg_DamageEventSource
    readonly unit           targetUnit    //stores udg_DamageEventTarget
    real                    damage        //stores udg_DamageEventAmount
    readonly real           prevAmt       //stores udg_DamageEventPrevAmt
    integer                 userType      //stores udg_DamageEventType
    readonly boolean        isCode
    readonly boolean        isSpell       //stores udg_IsDamageSpell
    boolean                 override
    readonly static unit    aoeSource   = null
    readonly static Damage  index       = 0
    private static Damage   damageStack = 0
    private static integer  count = 0 //The number of currently-running queued or sequential damage instances
    private Damage          stackRef
    private DamageTrigger   recursiveTrig
   
    static trigger lifeTrigger = null   //private
    static method operator source takes nothing returns unit
        return udg_DamageEventSource
    endmethod
    static method operator target takes nothing returns unit
        return udg_DamageEventTarget
    endmethod
    static method operator amount takes nothing returns real
        return Damage.index.damage
    endmethod
    static method operator amount= takes real r returns nothing
        set Damage.index.damage = r
    endmethod
     
    private static method onAOEEnd takes nothing returns nothing
        if udg_DamageEventAOE > 1 then
            call DamageTrigger.AOE.run()
        endif
        set udg_DamageEventAOE = 0
        set udg_DamageEventLevel = 0
        set udg_EnhancedDamageTarget = null
        set aoeSource = null
        call GroupClear(udg_DamageEventAOEGroup)
    endmethod
    static method finish takes nothing returns nothing
        local Damage i                                  = 0
        local integer exit                              
        if canKick then
            set canKick = false
            set kicking = true
            call DamageTrigger.finish()
            if damageStack != 0 then
                loop
                    set exit                            = damageStack
                    set sleepLevel                      = sleepLevel + 1
                    loop
                        set eventFilter                 = FILTER_CODE
                        set Damage.index                = i.stackRef
                        call DamageTrigger.setGUIFromStruct(true)
                        call DamageTrigger.MOD.run()
                        call DamageTrigger.DAMAGE.run()
                        if udg_DamageEventAmount != 0.00 then
                            call DamageTrigger.damageUnit(udg_DamageEventTarget, GetWidgetLife(udg_DamageEventTarget) - udg_DamageEventAmount)
                            call DamageTrigger.AFTER.run()
                        endif
                        set i                           = i + 1
                        exitwhen i == exit
                    endloop
                    exitwhen i == damageStack
                endloop
                loop
                    set i                               = i - 1
                    set i.stackRef.recursiveTrig.trigFrozen  = false
                    set i.stackRef.recursiveTrig.levelsDeep  = 0
                    exitwhen i == 0                    
                endloop                                
                set damageStack                         = 0
            endif
            set dreaming                                = false
            set sleepLevel                              = 0
            call GroupClear(proclusGlobal)
            call GroupClear(fischerMorrow)
            set kicking = false
            //call BJDebugMsg("Cleared up the groups")
        endif
    endmethod
   
    private static method wakeUp takes nothing returns nothing
        set alarmSet = false
        set dreaming = false
        set DamageTrigger.enabled = true
       
        call finish()
        call onAOEEnd()
       
        set Damage.count    = 0
        set Damage.index    = 0
        set udg_DamageEventTarget = null
        set udg_DamageEventSource = null
    endmethod
    private static method createLifeTrigger takes unit u, limitop op, real amount returns nothing
        if not blocked then
            set lifeTrigger = CreateTrigger()
            call TriggerAddCondition(lifeTrigger, Filter(function DamageTrigger.finish))
            call TriggerRegisterUnitStateEvent(lifeTrigger, u, UNIT_STATE_LIFE, op, amount)
        endif
        set protectUnit = u
    endmethod
    private method mitigate takes real newAmount, boolean recursive returns nothing
        local real prevLife
        local real life
        local unit u = targetUnit
        local real prevAmount = prevAmt
        set life = GetWidgetLife(u)
        if not isSpell then
            if newAmount != prevAmount then
                set life = life + prevAmount - newAmount
                if GetUnitState(u, UNIT_STATE_MAX_LIFE) < life then
                    set protectLife = life - prevAmount
                    call UnitAddAbility(u, udg_DamageBlockingAbility)
                endif
                call SetWidgetLife(u, RMaxBJ(life, 0.42))
            endif
            call createLifeTrigger(u, LESS_THAN, RMaxBJ(0.41, life - prevAmount/2.00))
        else
            set protectLife = GetUnitState(u, UNIT_STATE_MAX_LIFE)
            set prevLife = life
            if life + prevAmount*0.75 > protectLife then
                set life = RMaxBJ(protectLife - prevAmount/2.00, 1.00)
                call SetWidgetLife(u, life)
                set life = (life + protectLife)/2.00
            else
                set life = life + prevAmount*0.50
            endif
            set protectLife = prevLife - (prevAmount - (prevAmount - newAmount))
            call createLifeTrigger(u, GREATER_THAN, life)
        endif
        set u = null
    endmethod
    private method getSpellAmount takes real amt returns real
        local integer i = 6
        local real mult = 1.00
        set isSpell = amt < 0.00
        if isSpell then
            set amt = -amt
            if IsUnitType(target, UNIT_TYPE_ETHEREAL) and not IsUnitType(target, UNIT_TYPE_HERO) then
                set mult = mult*udg_DAMAGE_FACTOR_ETHEREAL //1.67
            endif
            if GetUnitAbilityLevel(target, 'Aegr') > 0 then
                set mult = mult*udg_DAMAGE_FACTOR_ELUNES //0.80
            endif
            if udg_DmgEvBracers != 0 and IsUnitType(target, UNIT_TYPE_HERO) then
                //Inline of UnitHasItemOfTypeBJ without the potential handle ID leak.
                loop
                    set i = i - 1
                    if GetItemTypeId(UnitItemInSlot(target, i)) == udg_DmgEvBracers then
                        set mult = mult*udg_DAMAGE_FACTOR_BRACERS //0.67
                        exitwhen true
                    endif
                    exitwhen i == 0
                endloop
            endif
            return amt*mult
        endif
        return amt
    endmethod
    private method addRecursive takes nothing returns boolean
        if this.damage != 0.00 then
            set this.recursiveTrig = DamageTrigger.eventIndex
            if not this.isCode then
                set this.isCode = true
            endif
            set inception = inception or DamageTrigger.eventIndex.inceptionTrig
            if kicking and IsUnitInGroup(this.sourceUnit, proclusGlobal) and IsUnitInGroup(this.targetUnit, fischerMorrow) then
                if inception and not DamageTrigger.eventIndex.trigFrozen then
                    set DamageTrigger.eventIndex.inceptionTrig = true
                    if DamageTrigger.eventIndex.levelsDeep < sleepLevel then
                        set DamageTrigger.eventIndex.levelsDeep = DamageTrigger.eventIndex.levelsDeep + 1
                        if DamageTrigger.eventIndex.levelsDeep >= LIMBO then
                            set DamageTrigger.eventIndex.trigFrozen = true
                        endif
                    endif
                else
                    set DamageTrigger.eventIndex.trigFrozen = true
                endif
            endif
            set damageStack.stackRef = this
            set damageStack = damageStack + 1
            //call BJDebugMsg("damageStack: " + I2S(damageStack) + " levelsDeep: " + I2S(DamageTrigger.eventIndex.levelsDeep) + " sleepLevel: " + I2S(sleepLevel))
            return true
        endif
        set inception = false
        return false
    endmethod
    private static method onDamageResponse takes nothing returns boolean
        local Damage d      = Damage.count + 1
        set Damage.count    = d
        set d.sourceUnit    = GetEventDamageSource()
        set d.targetUnit    = GetTriggerUnit()
        set d.damage        = d.getSpellAmount(GetEventDamage())
        set d.prevAmt       = d.damage
        set d.userType      = udg_NextDamageType
        set d.isCode        = udg_NextDamageType != 0 or udg_NextDamageOverride or dreaming
        set d.override      = udg_NextDamageOverride
       
        set udg_NextDamageOverride      = false
        set udg_NextDamageType          = 0
       
        call finish() //in case the unit state event failed and the 0.00 second timer hasn't yet expired
        if dreaming then
            if d.addRecursive() then
                set blocked = true
                call d.mitigate(0.00, true)
            else
                set Damage.count = d - 1
            endif
            return false
        endif
       
        //Added 25 July 2017 to detect AOE damage or multiple single-target damage
        if alarmSet then
            if d.sourceUnit != aoeSource then
                call onAOEEnd()
                set aoeSource           = d.sourceUnit
            elseif d.targetUnit == udg_EnhancedDamageTarget then
                set udg_DamageEventLevel= udg_DamageEventLevel + 1
            elseif not IsUnitInGroup(d.targetUnit, udg_DamageEventAOEGroup) then
                set udg_DamageEventAOE  = udg_DamageEventAOE + 1
            endif
        else
            call TimerStart(alarm, 0.00, false, function Damage.wakeUp)
            set alarmSet                = true
            set aoeSource               = d.sourceUnit
            set udg_EnhancedDamageTarget= d.targetUnit
        endif
       
        set Damage.index = d
        call DamageTrigger.setGUIFromStruct(true)
        call GroupAddUnit(udg_DamageEventAOEGroup, udg_DamageEventTarget)
        call GroupAddUnit(proclusGlobal, udg_DamageEventSource)
        call GroupAddUnit(fischerMorrow, udg_DamageEventTarget)
       
        if udg_DamageEventAmount == 0.00 then
            call DamageTrigger.ZERO.run()
            set canKick = true
            call finish()
        else
            if d.isCode then
                set eventFilter = FILTER_CODE
            elseif udg_IsDamageSpell then
                set eventFilter = FILTER_SPELL
            else
                set eventFilter = FILTER_ATTACK
            endif
            call DamageTrigger.MOD.run()
            call DamageTrigger.DAMAGE.run()
     
            //The damage amount is finalized.
            call d.mitigate(udg_DamageEventAmount, false)
            set canKick = true
        endif
        return false
    endmethod
    static method createDamageTrigger takes nothing returns nothing //private
        set udg_DamageEventTrigger = CreateTrigger()
        call TriggerAddCondition(udg_DamageEventTrigger, Filter(function thistype.onDamageResponse))
    endmethod
    static method setup takes nothing returns boolean //private
        local integer i = udg_UDex
        local unit u
        if udg_UnitIndexEvent == 1.00 then
            set u = udg_UDexUnits[i]
            if CheckAddUnitToEngine(u) then
                set udg_UnitDamageRegistered[i] = true
                call TriggerRegisterUnitEvent(udg_DamageEventTrigger, u, EVENT_UNIT_DAMAGED)
                call UnitAddAbility(u, udg_SpellDamageAbility)
                call UnitMakeAbilityPermanent(u, true, udg_SpellDamageAbility)
            endif
            set u = null
        else
            set udg_HideDamageFrom[i] = false
            if udg_UnitDamageRegistered[i] then
                set udg_UnitDamageRegistered[i] = false
                set udg_DamageEventsWasted = udg_DamageEventsWasted + 1
                if udg_DamageEventsWasted == 32 then //After 32 registered units have been removed...
                    set udg_DamageEventsWasted = 0
           
                    //Rebuild the mass EVENT_UNIT_DAMAGED trigger:
                    call DestroyTrigger(udg_DamageEventTrigger)
                    call createDamageTrigger()
                    set i = udg_UDexNext[0]
                    loop
                        exitwhen i == 0
                        if udg_UnitDamageRegistered[i] then
                            call TriggerRegisterUnitEvent(udg_DamageEventTrigger, udg_UDexUnits[i], EVENT_UNIT_DAMAGED)
                        endif
                        set i = udg_UDexNext[i]
                    endloop
                endif
            endif
        endif
        return false
    endmethod
   
    //! runtextmacro optional DAMAGE_EVENT_STRUCT_PLUGIN_DMGPKG()
    //! runtextmacro optional DAMAGE_EVENT_STRUCT_PLUGIN_01()
    //! runtextmacro optional DAMAGE_EVENT_STRUCT_PLUGIN_02()
    //! runtextmacro optional DAMAGE_EVENT_STRUCT_PLUGIN_03()
    //! runtextmacro optional DAMAGE_EVENT_STRUCT_PLUGIN_04()
    //! runtextmacro optional DAMAGE_EVENT_STRUCT_PLUGIN_05()
   
endstruct
public function RegisterFromHook takes trigger whichTrig, string var, limitop op, real value returns nothing
    call DamageTrigger.registerVerbose(whichTrig, var, value, true, GetHandleId(op))
endfunction
hook TriggerRegisterVariableEvent RegisterFromHook
function TriggerRegisterDamageEngineEx takes trigger whichTrig, string eventName, real value, integer f returns DamageTrigger
    return DamageTrigger.registerVerbose(whichTrig, DamageTrigger.getVerboseStr(eventName), value, false, f)
endfunction
function TriggerRegisterDamageEngine takes trigger whichTrig, string eventName, real value returns DamageTrigger
    return DamageTrigger.registerTrigger(whichTrig, eventName, value)
endfunction
function RegisterDamageEngineEx takes code c, string eventName, real value, integer f returns DamageTrigger
    return TriggerRegisterDamageEngineEx(DamageTrigger[c], eventName, value, f)
endfunction
//Similar to TriggerRegisterDamageEvent, although takes code instead of trigger as the first argument.
function RegisterDamageEngine takes code c, string eventName, real value returns DamageTrigger
    return RegisterDamageEngineEx(c, eventName, value, FILTER_OTHER)
endfunction
endlibrary
function InitTrig_Damage_Engine takes nothing returns nothing
    local unit u = CreateUnit(Player(bj_PLAYER_NEUTRAL_EXTRA), 'uloc', 0, 0, 0)
    local integer i = bj_MAX_PLAYERS //Fixed in 3.8
   
    //Create this trigger with UnitIndexEvents in order to add and remove units
    //as they are created or removed.
    local trigger t = CreateTrigger()
    call TriggerRegisterVariableEvent(t, "udg_UnitIndexEvent", EQUAL, 1.00)
    call TriggerRegisterVariableEvent(t, "udg_UnitIndexEvent", EQUAL, 2.00)
    call TriggerAddCondition(t, Filter(function Damage.setup))
    set t = null
   
    //Run the configuration actions to set all configurables:
    call ExecuteFunc("Trig_Damage_Engine_Config_Actions")
   
    //Create trigger for storing all EVENT_UNIT_DAMAGED events.
    call Damage.createDamageTrigger()
 
    //Disable SpellDamageAbility for every player.
    loop
        set i = i - 1
        call SetPlayerAbilityAvailable(Player(i), udg_SpellDamageAbility, false)
        exitwhen i == 0
    endloop
 
    //Preload abilities.
    call UnitAddAbility(u, udg_DamageBlockingAbility)
    call UnitAddAbility(u, udg_SpellDamageAbility)
    call RemoveUnit(u)
    set u = null
endfunction
