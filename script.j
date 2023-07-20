/*
    vJass Damage Engine 5.A.0.0 PREVIEW
    
    This update requires the addition of a new 'DamageEventAttackTarget'. 
    This new unit variable is associated with the 'unit is attacked' event,
    and identifies it correctly during splash damage/multi-hit attacks.
*/
//! novjass
JASS API:

    struct Damage extends array
        readonly static unit source // udg_DamageEventSource in real-time
        readonly static unit target // udg_DamageEventTarget in real-time
        static real          amount // udg_DamageEventAmount in real-time

        readonly unit    sourceUnit   // udg_DamageEventSource by index
        readonly unit    targetUnit   // udg_DamageEventTarget by index
        real             damage       // udg_DamageEventAmount by index
        readonly real    prevAmt      // udg_DamageEventPrevAmt by index
        attacktype       attackType   // udg_DamageEventAttackT by index
        damagetype       damageType   // udg_DamageEventDamageT by index
        weapontype       weaponType   // udg_DamageEventWeaponT by index
        integer          userType     // udg_DamageEventType by index
        readonly boolean isAttack     // udg_IsDamageAttack by index
        readonly boolean isCode       // udg_IsDamageCode by index
        readonly boolean isMelee      // udg_IsDamageMelee by index
        readonly boolean isRanged     // udg_IsDamageRanged by index
        readonly boolean isSpell      // udg_IsDamageSpell by index
        real             armorPierced // udg_DamageEventArmorPierced by index
        integer          armorType    // udg_DamageEventArmorT by index
        integer          defenseType  // udg_DamageEventDefenseT by index

        readonly integer eFilter

        - Set to false to disable the damage event triggers or to true to reverse that
        static boolean operator enabled

        - Same arguments as "UnitDamageTarget" but has the benefit of being performance-friendly during recursive events.
        - Will automatically cause the damage to be registered as Code damage.
        static method apply takes
            unit source,
            unit target,
            real amount,
            boolean isAttack,
            boolean isRanged,
            attacktype at,
            damagetype dt,
            weapontype wt
        returns Damage

        - A simplified version of the above function that autofills each boolean, attacktype and weapontype.
        static method applySpell takes
            unit src,
            unit tgt,
            real amt,
            damagetype dt
        returns Damage

        - A different variation of the above which autofills the "isAttack" boolean
        - and populates damagetype as DAMAGE_TYPE_NORMAL.
        static method applyAttack takes
            unit src,
            unit tgt,
            real amt,
            boolean ranged,
            attacktype at,
            weapontype wt
        returns Damage

    struct DamageTrigger extends array
        method operator filter= takes integer filter returns nothing
        // Apply primary filters such as DamageEngine_FILTER_MELEE/RANGED/SPELL which are based off of limitop handles to enable easier access for GUI folks
        // Full filter list:
        - global integer DamageEngine_FILTER_ATTACK
        - global integer DamageEngine_FILTER_MELEE
        - global integer DamageEngine_FILTER_OTHER
        - global integer DamageEngine_FILTER_RANGED
        - global integer DamageEngine_FILTER_SPELL
        - global integer DamageEngine_FILTER_CODE

        boolean configured //set to True after configuring any filters listed below.

        method configure takes nothing returns nothing
        // Apply custom filters after setting any desired udg_DamageFilter variables (for GUI).
        // Alternatively, vJass users can set these instead. Just be mindful to set the variable
        // "configured" to true after settings these.
        unit    source
        unit    target
        integer sourceType
        integer targetType
        integer sourceBuff
        integer targetBuff
        real    damageMin
        integer attackType
        integer damageType
        integer userType

        //The string in the aruments below requires the following API:
        //  "" for standard damage event
        //  "Modifier(or Mod if you prefer)/After/Lethal/AOE" for the others
        static method registerTrigger takes trigger whichTrig, string var, real value returns nothing
        static method unregister takes trigger t, string eventName, real value, boolean reset returns boolean

        static method getIndex takes trigger t, string eventName, real value returns integer

        //If you already have the index of the trigger you want to unregister.
        method unregisterByIndex takes boolean reset returns boolean

        // Converts a code argument to a trigger, while checking if the same code had already been registered before.
        static method operator [] takes code callback returns trigger

    //The accepted strings here use the same criteria as DamageTrigger.getIndex/registerTrigger/unregister
    function TriggerRegisterDamageEngineEx takes trigger whichTrig, string eventName, real value, integer opId returns nothing
    function TriggerRegisterDamageEngine takes trigger whichTrig, string eventName, real value returns nothing
    function RegisterDamageEngineEx takes code callback, string eventName, real value, integer opId returns nothing
    function RegisterDamageEngine takes code callback, string eventName, real value returns nothing
//! endnovjass

//===========================================================================
library DamageEngine
globals
    private constant boolean USE_GUI = true //If you don't use any of the GUI events, set to false to slightly improve performance

    private constant boolean USE_SCALING     = USE_GUI   //If you don't need or want to use DamageScalingUser/WC3 then set this to false
    private constant boolean USE_EXTRA       = true      //If you don't use DamageEventLevel or SourceDamageEvent, set this to false
    private constant boolean USE_ARMOR_MOD   = true      //If you do not modify nor detect armor/defense, set this to false
    private constant boolean USE_MELEE_RANGE = true      //If you do not detect melee nor ranged damage, set this to false
    private constant boolean USE_LETHAL      = true      //If you do not use LethalDamageEvent nor negative damage (explosive) types, set this to false

    //When manually-enabled recursion is enabled via DamageEngine_recurion, the engine will never go deeper than LIMBO:
    private constant integer LIMBO = 16

    public constant integer TYPE_CODE = 1         //Must be the same as udg_DamageTypeCode, or 0 if you prefer to disable the automatic flag.
    public constant integer TYPE_PURE = 2         //Must be the same as udg_DamageTypePure
    private constant real   DEATH_VAL = 0.405     //In case M$ ever changes this, it'll be a quick fix here.

    private timer           async = null
    private boolean         timerStarted = false

    //Values to track the original pre-spirit Link/defensive damage values
    private Damage lastInstance = 0

    private boolean canKick = true
    private boolean waitingForDamageEventToRun = false

    private boolean array attacksImmune
    private boolean array damagesImmune

    //Primary triggers used to handle all damage events.
    private trigger damagingTrigger = null
    private trigger damagedTrigger = null
    private trigger recursiveTrigger = null //Catches, stores recursive events

    /*
        These variables coincide with Blizzard's "limitop" type definitions
        so as to enable GUI users with some performance perks - however,
        these optimizations need to be tested
    */
    public constant integer FILTER_ATTACK = 0     //LESS_THAN
    public constant integer FILTER_MELEE  = 1     //LESS_THAN_OR_EQUAL
    public constant integer FILTER_OTHER  = 2     //EQUAL
    public constant integer FILTER_RANGED = 3     //GREATER_THAN_OR_EQUAL
    public constant integer FILTER_SPELL  = 4     //GREATER_THAN
    public constant integer FILTER_CODE   = 5     //NOT_EQUAL
    public constant integer FILTER_MAX    = 6
    private integer         eventFilter   = FILTER_OTHER

    public boolean  inception = false     //When true, it allows your trigger to potentially go recursive up to LIMBO. However it must be set per-trigger throughout the game and not only once per trigger during map initialization.
    private boolean dreaming = false
    private integer sleepLevel = 0
    private group   recursionSources = null
    private group   recursionTargets = null
    private boolean kicking = false
    private boolean eventsRun = false
    private keyword run
    private keyword trigFrozen
    private keyword levelsDeep
    private keyword inceptionTrig
    private boolean hasLethal = false
endglobals

native UnitAlive takes unit u returns boolean

//GUI Vars:
/*
    Retained from 3.8 and prior:
    ----------------------------
    unit            udg_DamageEventSource
    unit            udg_DamageEventTarget
    unit            udg_EnhancedDamageTarget
    group           udg_DamageEventAOEGroup
    integer         udg_DamageEventAOE
    integer         udg_DamageEventLevel
    real            udg_DamageModifierEvent
    real            udg_DamageEvent
    real            udg_AfterDamageEvent
    real            udg_DamageEventAmount
    real            udg_DamageEventPrevAmt
    real            udg_AOEDamageEvent
    boolean         udg_DamageEventOverride
    boolean         udg_NextDamageType
    boolean         udg_DamageEventType
    boolean         udg_IsDamageSpell

    //Added in 5.0:
    boolean          udg_IsDamageMelee
    boolean          udg_IsDamageRanged
    unit             udg_AOEDamageSource
    real             udg_LethalDamageEvent
    real             udg_LethalDamageHP
    real             udg_DamageScalingWC3
    integer          udg_DamageEventAttackT
    integer          udg_DamageEventDamageT
    integer          udg_DamageEventWeaponT

    //Added in 5.1:
    boolean          udg_IsDamageCode

    //Added in 5.2:
    integer          udg_DamageEventArmorT
    integer          udg_DamageEventDefenseT

    //Addded in 5.3:
    real             DamageEventArmorPierced
    real             udg_DamageScalingUser

    //Added in 5.4.2 to allow GUI users to re-issue the exact same attack and damage type at the attacker.
    attacktype array udg_CONVERTED_ATTACK_TYPE
    damagetype array udg_CONVERTED_DAMAGE_TYPE

    //Added after Reforged introduced the new native BlzGetDamageIsAttack
    boolean         udg_IsDamageAttack

    //Added in 5.6 to give GUI users control over the "IsDamageAttack", "IsDamageRanged" and "DamageEventWeaponT" field
    boolean         udg_NextDamageIsAttack  //The first boolean value in the UnitDamageTarget native
    boolean         udg_NextDamageIsMelee   //Flag the damage classification as melee
    boolean         udg_NextDamageIsRanged  //The second boolean value in the UnitDamageTarget native
    integer         udg_NextDamageWeaponT   //Allows control over damage sound effect

    //Added in 5.7 to enable efficient, built-in filtering (see the below "checkConfig" method - I recommend commenting-out anything you don't need in your map)
    integer udg_DamageFilterAttackT
    integer udg_DamageFilterDamageT     //filter for a specific attack/damage type
    unit    udg_DamageFilterSource
    unit    udg_DamageFilterTarget      //filter for a specific source/target
    integer udg_DamageFilterSourceT
    integer udg_DamageFilterTargetT     //unit type of source/target
    integer udg_DamageFilterType        //which DamageEventType was used
    integer udg_DamageFilterSourceB
    integer udg_DamageFilterTargetB     //if source/target has a buff
    real    udg_DamageFilterMinAmount   //only allow a minimum damage threshold

    //Added in 5.8:
    boolean udg_RemoveDamageEvent       //Allow GUI users to more fully unregister a damage event trigger. Can only be used from within a damage event (of any kind).
    integer udg_DamageFilterSourceA
    integer udg_DamageFilterTargetA     //Check if a source or target have a specific ability (will overwrite any source or target buff check, I need to use this because GUI differentiates ability ID and buff ID)
    integer udg_DamageFilterSourceI
    integer udg_DamageFilterTargetI     //Check if a source or target have a specific type of item
    integer udg_DamageFilterSourceC
    integer udg_DamageFilterTargetC     //Classification of source/target (e.g. hero, treant, ward)

    //Added in 5.9
    real udg_SourceDamageEvent          //Like AOEDamageEvent, fires each time the source unit has finished dealing damage, but doesn't care if the damage hit multiple units.
    real udg_PreDamageEvent             //Like DamageModifierEvent 3.99 or less, except can be any real value.
    real udg_ArmorDamageEvent           //Like DamageModifierEvent 4.00 or more, except can be any real value.
    real udg_OnDamageEvent              //Like DamageEvent equal to 1.00 or some non-zero/non-2 value, except can be any real value.
    real udg_ZeroDamageEvent            //Like DamageEvent equal to 0.00 or 2.00, except can be any real value.
*/

struct DamageTrigger extends array

    static method checkItem takes unit u, integer id returns boolean
        local integer i
        if IsUnitType(u, UNIT_TYPE_HERO) then
            set i = UnitInventorySize(u)
            loop
                exitwhen i <= 0
                set i = i - 1
                if GetItemTypeId(UnitItemInSlot(u, i)) == id then
                    return true
                endif
            endloop
        endif
        return false
    endmethod

    /*
        Map makers should probably not use this, unless someone tests performance to see
        if such an ugly hack is even worth it.
    */

    method checkConfig takes nothing returns boolean

        //call BJDebugMsg("Checking configuration")

        if this.sourceType      != 0 and GetUnitTypeId(udg_DamageEventSource) != this.sourceType then
        elseif this.targetType  != 0 and GetUnitTypeId(udg_DamageEventTarget) != this.targetType then
        elseif this.sourceBuff  != 0 and GetUnitAbilityLevel(udg_DamageEventSource, this.sourceBuff) == 0 then
        elseif this.targetBuff  != 0 and GetUnitAbilityLevel(udg_DamageEventTarget, this.targetBuff) == 0 then
        elseif this.failChance  > 0.00 and GetRandomReal(0.00, 1.00) <= this.failChance then
        elseif this.userType    != 0 and udg_DamageEventType != this.userType then
        elseif this.source      != null and this.source != udg_DamageEventSource then
        elseif this.target      != null and this.target != udg_DamageEventTarget then
        elseif this.attackType  >= 0 and this.attackType != udg_DamageEventAttackT then
        elseif this.damageType  >= 0 and this.damageType != udg_DamageEventDamageT then
        elseif this.sourceItem  != 0 and not .checkItem(udg_DamageEventSource, this.sourceItem) then
        elseif this.targetItem  != 0 and not .checkItem(udg_DamageEventTarget, this.targetItem) then
        elseif this.sourceClass >= 0 and not IsUnitType(udg_DamageEventSource, ConvertUnitType(this.sourceClass)) then
        elseif this.targetClass >= 0 and not IsUnitType(udg_DamageEventTarget, ConvertUnitType(this.targetClass)) then
        elseif udg_DamageEventAmount >= this.damageMin then
            //call BJDebugMsg("Configuration passed")
            return true
        endif
        //call BJDebugMsg("Checking failed")
        return false
    endmethod

    //The below variables are to be treated as constant
    readonly static thistype MOD    = 1
    readonly static thistype SHIELD = 4
    readonly static thistype DAMAGE = 5
    readonly static thistype ZERO   = 6
    readonly static thistype AFTER  = 7
    readonly static thistype LETHAL = 8
    readonly static thistype AOE    = 9
    private  static integer  count  = 9

    static thistype lastRegistered  = 0

    private static thistype array   trigIndexStack

    static thistype eventIndex = 0

    static boolean array filters
    readonly string eventStr
    readonly real weight
    boolean usingGUI

    private thistype next
    private trigger rootTrig

    //The below variables are to be treated as private
    boolean trigFrozen      //Whether the trigger is currently disabled due to recursion
    integer levelsDeep      //How deep the user recursion currently is.
    boolean inceptionTrig   //Added in 5.4.2 to simplify the inception variable for very complex DamageEvent triggers.

    //configuration variables:
    boolean configured
    unit    source
    unit    target
    integer sourceType
    integer targetType
    integer sourceBuff
    integer targetBuff
    integer sourceItem
    integer targetItem
    integer sourceClass
    integer targetClass
    real    damageMin
    real    failChance
    integer attackType
    integer damageType
    integer userType

    // setter:
    method operator runChance takes nothing returns real
        return 1.00 - this.failChance
    endmethod

    // getter:
    method operator runChance= takes real chance returns nothing
        set this.failChance = 1.00 - chance
    endmethod

    method configure takes nothing returns nothing
        set this.attackType  = udg_DamageFilterAttackT
        set this.damageType  = udg_DamageFilterDamageT
        set this.source      = udg_DamageFilterSource
        set this.target      = udg_DamageFilterTarget
        set this.sourceType  = udg_DamageFilterSourceT
        set this.targetType  = udg_DamageFilterTargetT
        set this.sourceItem  = udg_DamageFilterSourceI
        set this.targetItem  = udg_DamageFilterTargetI
        set this.sourceClass = udg_DamageFilterSourceC
        set this.targetClass = udg_DamageFilterTargetC
        set this.userType    = udg_DamageFilterType
        set this.damageMin   = udg_DamageFilterMinAmount
        set this.failChance  = 1.00 - (udg_DamageFilterRunChance - udg_DamageFilterFailChance)

        if udg_DamageFilterSourceA > 0 then
            set this.sourceBuff         = udg_DamageFilterSourceA
            set udg_DamageFilterSourceA = 0
        else
            set this.sourceBuff         = udg_DamageFilterSourceB
        endif

        if udg_DamageFilterTargetA > 0 then
            set this.targetBuff         = udg_DamageFilterTargetA
            set udg_DamageFilterTargetA = 0
        else
            set this.targetBuff         = udg_DamageFilterTargetB
        endif

        set udg_DamageFilterAttackT    = -1
        set udg_DamageFilterDamageT    = -1
        set udg_DamageFilterSource     = null
        set udg_DamageFilterTarget     = null
        set udg_DamageFilterSourceT    = 0
        set udg_DamageFilterTargetT    = 0
        set udg_DamageFilterType       = 0
        set udg_DamageFilterSourceB    = 0
        set udg_DamageFilterTargetB    = 0
        set udg_DamageFilterSourceC    = -1
        set udg_DamageFilterTargetC    = -1
        set udg_DamageFilterSourceI    = 0
        set udg_DamageFilterTargetI    = 0
        set udg_DamageFilterMinAmount  = 0.00
        set udg_DamageFilterFailChance = 0.00
        set udg_DamageFilterRunChance  = 1.00

        set this.configured = true
    endmethod

    static method setGUIFromStruct takes boolean full returns nothing
        set udg_DamageEventAmount       = Damage.index.damage
        set udg_DamageEventAttackT      = GetHandleId(Damage.index.attackType)
        set udg_DamageEventDamageT      = GetHandleId(Damage.index.damageType)
        set udg_DamageEventWeaponT      = GetHandleId(Damage.index.weaponType)
        set udg_DamageEventType         = Damage.index.userType
static if USE_ARMOR_MOD then
        set udg_DamageEventArmorPierced = Damage.index.armorPierced
        set udg_DamageEventArmorT       = Damage.index.armorType
        set udg_DamageEventDefenseT     = Damage.index.defenseType
endif
        if full then
            set udg_DamageEventSource   = Damage.index.sourceUnit
            set udg_DamageEventTarget   = Damage.index.targetUnit
            set udg_DamageEventPrevAmt  = Damage.index.prevAmt
            set udg_IsDamageAttack      = Damage.index.isAttack
            set udg_IsDamageCode        = Damage.index.isCode
            set udg_IsDamageSpell       = Damage.index.isSpell
static if USE_MELEE_RANGE then
            set udg_IsDamageMelee       = Damage.index.isMelee
            set udg_IsDamageRanged      = Damage.index.isRanged
endif
        endif
    endmethod

    static method setStructFromGUI takes nothing returns nothing
        set Damage.index.damage        = udg_DamageEventAmount
        set Damage.index.attackType    = ConvertAttackType(udg_DamageEventAttackT)
        set Damage.index.damageType    = ConvertDamageType(udg_DamageEventDamageT)
        set Damage.index.weaponType    = ConvertWeaponType(udg_DamageEventWeaponT)
        set Damage.index.userType      = udg_DamageEventType
static if USE_ARMOR_MOD then
        set Damage.index.armorPierced  = udg_DamageEventArmorPierced
        set Damage.index.armorType     = udg_DamageEventArmorT
        set Damage.index.defenseType   = udg_DamageEventDefenseT
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
        if (var == "udg_DamageModifierEvent" and root < 4) or var == "udg_PreDamageEvent" then
            set root    = MOD
        elseif var == "udg_DamageModifierEvent" or var == "udg_ArmorDamageEvent" then
            set root    = SHIELD
        elseif (var == "udg_DamageEvent" and root == 2 or root == 0) or var == "udg_ZeroDamageEvent" then
            set root    = ZERO
        elseif var == "udg_DamageEvent" or var == "udg_OnDamageEvent" then
            set root    = DAMAGE
        elseif var == "udg_AfterDamageEvent" then
            set root    = AFTER
        elseif var == "udg_LethalDamageEvent" then
            set root    = LETHAL
        elseif var == "udg_AOEDamageEvent" or var == "udg_SourceDamageEvent" then
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
        set filters[this + FILTER_MELEE]    = flag
        set filters[this + FILTER_OTHER]    = flag
        set filters[this + FILTER_RANGED]   = flag
        set filters[this + FILTER_SPELL]    = flag
        set filters[this + FILTER_CODE]     = flag
    endmethod

    method operator filter= takes integer opId returns nothing
        set this = this*FILTER_MAX
        if opId == FILTER_OTHER then
            call this.toggleAllFilters(true)
        else
            if opId == FILTER_ATTACK then
                set filters[this + FILTER_ATTACK]   = true
                set filters[this + FILTER_MELEE]    = true
                set filters[this + FILTER_RANGED]   = true
            else
                set filters[this + opId] = true
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

        if not hasLethal and index == LETHAL then
            set hasLethal = true
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

        //Next 2 lines added to fix a bug when using manual vJass configuration,
        //discovered and solved by lolreported
        set id.attackType          = -1
        set id.damageType          = -1
		//they will probably bug out with class types as well, so I should add them, just in case:
		set id.sourceClass         = -1
		set id.targetClass         = -1

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

    method unregisterByIndex takes boolean reset returns boolean
        if this == 0 then
            return false
        endif
        set prev.next               = this.next

        set trigIndexStack[this]    = trigIndexStack[0]
        set trigIndexStack[0]       = this

        if reset then
            call this.configure()
            set this.configured     = false
            call thistype(this*FILTER_MAX).toggleAllFilters(false)
        endif
        return true
    endmethod

    static method unregister takes trigger t, string eventName, real lbs, boolean reset returns boolean
        return getIndex(t, eventName, lbs).unregisterByIndex(reset)
    endmethod

    method run takes nothing returns nothing
        local integer cat = this
        local Damage d = Damage.index

        static if USE_GUI then
            local boolean structUnset = false
            local boolean guiUnset = false
            local boolean mod = cat <= DAMAGE
        endif

        if dreaming then
            return
        endif
        set dreaming = true
        call DisableTrigger(damagingTrigger)
        call DisableTrigger(damagedTrigger)
        call EnableTrigger(recursiveTrigger)
        //call BJDebugMsg("Start of event running")
        loop
            set this = this.next
            exitwhen this == 0
            exitwhen cat == MOD and (udg_DamageEventOverride or udg_DamageEventType == TYPE_PURE)
            exitwhen cat == SHIELD and udg_DamageEventAmount <= 0.00

            static if USE_LETHAL then
                exitwhen cat == LETHAL and udg_LethalDamageHP > DEATH_VAL
            endif

            set eventIndex = this
            if (not this.trigFrozen) and /*
                */ filters[this*FILTER_MAX + d.eFilter] and /*
                */ IsTriggerEnabled(this.rootTrig) and /*
                */ ((not this.configured) or (this.checkConfig())) and /*
                */ (cat != AOE or udg_DamageEventAOE > 1 or this.eventStr == "udg_SourceDamageEvent") then
                static if USE_GUI then
                    if mod then
                        if this.usingGUI then
                            if guiUnset then
                                set guiUnset = false
                                call setGUIFromStruct(false)
                            endif
                            //! runtextmacro optional DAMAGE_EVENT_FILTER_PLUGIN_PDD()
                        elseif structUnset then
                            set structUnset = false
                            call setStructFromGUI()
                        endif
                    endif
                endif
                //! runtextmacro optional DAMAGE_EVENT_FILTER_PLUGIN_01()
                //! runtextmacro optional DAMAGE_EVENT_FILTER_PLUGIN_02()
                //! runtextmacro optional DAMAGE_EVENT_FILTER_PLUGIN_03()
                //! runtextmacro optional DAMAGE_EVENT_FILTER_PLUGIN_04()
                //! runtextmacro optional DAMAGE_EVENT_FILTER_PLUGIN_05()

                //JASS users who do not use actions can modify the below block to just evaluate.
                //It should not make any perceptable difference in terms of performance.
                if TriggerEvaluate(this.rootTrig) then
                    call TriggerExecute(this.rootTrig)
                endif
                //! runtextmacro optional DAMAGE_EVENT_MOD_PLUGIN_01()
                //! runtextmacro optional DAMAGE_EVENT_MOD_PLUGIN_02()
                //! runtextmacro optional DAMAGE_EVENT_MOD_PLUGIN_03()
                //! runtextmacro optional DAMAGE_EVENT_MOD_PLUGIN_04()
                //! runtextmacro optional DAMAGE_EVENT_MOD_PLUGIN_05()
                static if USE_GUI then
                    if mod then
                        if this.usingGUI then
                            //! runtextmacro optional DAMAGE_EVENT_MOD_PLUGIN_PDD()
                            if cat != MOD then
                                set d.damage            = udg_DamageEventAmount
                            else
                                set structUnset         = true
                            endif
                        elseif cat != MOD then
                            set udg_DamageEventAmount   = d.damage
                        else
                            set guiUnset                = true
                        endif
                    endif
                    if udg_RemoveDamageEvent then
                        set udg_RemoveDamageEvent = false
                        call this.unregisterByIndex(true)
                    endif
                endif
            endif
        endloop

        static if USE_GUI then
            if structUnset then
                call setStructFromGUI()
            endif
            if guiUnset then
                call setGUIFromStruct(false)
            endif
        else
            call setGUIFromStruct(false)
        endif

        //call BJDebugMsg("End of event running")

        call DisableTrigger(recursiveTrigger)
        call EnableTrigger(damagingTrigger)
        call EnableTrigger(damagedTrigger)
        set dreaming                                = false
    endmethod

    static trigger array    autoTriggers
    static boolexpr array   autoFuncs
    static integer          autoN = 0

    static method operator [] takes code callback returns trigger
        local integer i = 0
        local boolexpr b = Filter(callback)
        loop
            if i == autoN then
                set autoTriggers[i] = CreateTrigger()
                set autoFuncs[i] = b
                call TriggerAddCondition(autoTriggers[i], b)
                exitwhen true
            endif
            set i = i + 1
            exitwhen b == autoFuncs[i]
        endloop
        return autoTriggers[i]
    endmethod
endstruct

//! runtextmacro optional DAMAGE_EVENT_USER_STRUCT_PLUGIN_01()
//! runtextmacro optional DAMAGE_EVENT_USER_STRUCT_PLUGIN_02()
//! runtextmacro optional DAMAGE_EVENT_USER_STRUCT_PLUGIN_03()
//! runtextmacro optional DAMAGE_EVENT_USER_STRUCT_PLUGIN_04()
//! runtextmacro optional DAMAGE_EVENT_USER_STRUCT_PLUGIN_05()

struct Damage extends array
    readonly unit    sourceUnit
    readonly unit    targetUnit
    real             damage
    readonly real    prevAmt
    attacktype       attackType
    damagetype       damageType
    weapontype       weaponType
    integer          userType
    readonly boolean isAttack
    readonly boolean isCode
    readonly boolean isSpell

    static if USE_MELEE_RANGE then
        readonly boolean isMelee       //stores udg_IsDamageMelee
    endif

    readonly boolean isRanged      //stores udg_IsDamageRanged
    readonly integer eFilter       //stores the previous eventFilter variable

    static if USE_ARMOR_MOD then
        real    armorPierced  //stores udg_DamageEventArmorPierced
        integer armorType     //stores udg_DamageEventArmorT
        integer defenseType   //stores udg_DamageEventDefenseT
    endif

    readonly static Damage index = 0

    private static Damage damageStack = 0

    private static Damage prepped = 0

    private static integer count = 0 //The number of currently-running queued or sequential damage instances

    private Damage stackRef
    private DamageTrigger recursiveTrig

    private integer prevArmorT
    private integer prevDefenseT

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

    static if USE_ARMOR_MOD then
        private method setArmor takes boolean reset returns nothing
            local real pierce
            local integer at
            local integer dt

            if reset then
                set pierce = udg_DamageEventArmorPierced
                set at = Damage.index.prevArmorT
                set dt = Damage.index.prevDefenseT
                set udg_DamageEventArmorPierced = 0.00
                set this.armorPierced = 0.00
            else
                set pierce = -udg_DamageEventArmorPierced
                set at = udg_DamageEventArmorT
                set dt = udg_DamageEventDefenseT
            endif

            if not (pierce == 0.00) then //Changed from != to not == due to bug reported by BLOKKADE
                call BlzSetUnitArmor(udg_DamageEventTarget, BlzGetUnitArmor(udg_DamageEventTarget) + pierce)
            endif

            if Damage.index.prevArmorT != udg_DamageEventArmorT then
                call BlzSetUnitIntegerField(udg_DamageEventTarget, UNIT_IF_ARMOR_TYPE, at)
            endif
            if Damage.index.prevDefenseT != udg_DamageEventDefenseT then
                call BlzSetUnitIntegerField(udg_DamageEventTarget, UNIT_IF_DEFENSE_TYPE, dt)
            endif
        endmethod
    endif

    static if USE_EXTRA then
        private static method onAOEEnd takes nothing returns nothing
            call DamageTrigger.AOE.run()
            set udg_DamageEventAOE       = 1
            set udg_DamageEventLevel     = 1
            set udg_EnhancedDamageTarget = null
            set udg_AOEDamageSource      = null
            call GroupClear(udg_DamageEventAOEGroup)
        endmethod
    endif

    private static method afterDamage takes nothing returns nothing
        if udg_DamageEventDamageT != 0 and not (udg_DamageEventPrevAmt == 0.00) then
            call DamageTrigger.AFTER.run()
            set udg_DamageEventDamageT  = 0
            set udg_DamageEventPrevAmt  = 0.00
        endif
    endmethod

    private method doPreEvents takes boolean natural returns boolean

        static if USE_ARMOR_MOD then
            set this.armorType    = BlzGetUnitIntegerField(this.targetUnit, UNIT_IF_ARMOR_TYPE)
            set this.defenseType  = BlzGetUnitIntegerField(this.targetUnit, UNIT_IF_DEFENSE_TYPE)
            set this.prevArmorT   = this.armorType
            set this.prevDefenseT = this.defenseType
            set this.armorPierced = 0.00
        endif

        set Damage.index = this
        call DamageTrigger.setGUIFromStruct(true)

        call GroupAddUnit(recursionSources, udg_DamageEventSource)
        call GroupAddUnit(recursionTargets, udg_DamageEventTarget)

        //! runtextmacro optional DAMAGE_EVENT_PRE_VARS_PLUGIN_01()
        //! runtextmacro optional DAMAGE_EVENT_PRE_VARS_PLUGIN_02()
        //! runtextmacro optional DAMAGE_EVENT_PRE_VARS_PLUGIN_03()
        //! runtextmacro optional DAMAGE_EVENT_PRE_VARS_PLUGIN_04()
        //! runtextmacro optional DAMAGE_EVENT_PRE_VARS_PLUGIN_05()

        // Using not == instead of !=; the idea is to eliminate floating point bugs when two numbers are very close to 0,
        // because JASS uses a less-strict comparison for checking if a number is equal than when it is unequal.
        if not (udg_DamageEventAmount == 0.00) then
            set udg_DamageEventOverride = udg_DamageEventDamageT == 0

            call DamageTrigger.MOD.run()

            static if not USE_GUI then
                call DamageTrigger.setGUIFromStruct(false)
            endif

            if natural then
                call BlzSetEventAttackType(this.attackType)
                call BlzSetEventDamageType(this.damageType)
                call BlzSetEventWeaponType(this.weaponType)
                call BlzSetEventDamage(udg_DamageEventAmount)
            endif

            static if USE_ARMOR_MOD then
                call this.setArmor(false)
            endif

            return false
        endif
        return true
    endmethod

    private static method unfreeze takes nothing returns nothing
        local Damage i = damageStack

        loop
            exitwhen i == 0
            set i = i - 1
            set i.stackRef.recursiveTrig.trigFrozen = false
            set i.stackRef.recursiveTrig.levelsDeep = 0
        endloop

        call EnableTrigger(damagingTrigger)
        call EnableTrigger(damagedTrigger)

        set kicking     = false
        set damageStack = 0
        set prepped     = 0
        set dreaming    = false
        set sleepLevel  = 0
        call GroupClear(recursionSources)
        call GroupClear(recursionTargets)

        //call BJDebugMsg("Cleared up the groups")
    endmethod

    static method finish takes nothing returns nothing
        local Damage i = 0
        local integer exit

        if eventsRun then
            set eventsRun = false
            call afterDamage()
        endif

        if canKick and not kicking then
            if damageStack != 0 then
                set kicking = true
                loop
                    set sleepLevel = sleepLevel + 1
                    set exit = damageStack
                    loop
                        set prepped = i.stackRef

                        if UnitAlive(prepped.targetUnit) then

                            call prepped.doPreEvents(false) //don't evaluate the pre-event

                            if prepped.damage > 0.00 then
                                call DisableTrigger(damagingTrigger) //Force only the after armor event to run.
                                call EnableTrigger(damagedTrigger)  //in case the user forgot to re-enable this

                                set waitingForDamageEventToRun = true

                                call UnitDamageTarget( /*
                                    */ prepped.sourceUnit, /*
                                    */ prepped.targetUnit, /*
                                    */ prepped.damage, /*
                                    */ prepped.isAttack, /*
                                    */ prepped.isRanged, /*
                                    */ prepped.attackType, /*
                                    */ prepped.damageType, /*
                                    */ prepped.weaponType /*
                                */ )
                            else
                                if udg_DamageEventDamageT != 0 then
                                    //No new events run at all in this case
                                    call DamageTrigger.DAMAGE.run()
                                endif

                                if prepped.damage < 0.00 then
                                    //No need for BlzSetEventDamage here
                                    call SetWidgetLife( /*
                                        */ prepped.targetUnit, /*
                                        */ GetWidgetLife(prepped.targetUnit) - prepped.damage /*
                                    */ )
                                endif

                                static if USE_ARMOR_MOD then
                                    call prepped.setArmor(true)
                                endif
                            endif
                            call afterDamage()
                        endif
                        set i = i + 1
                        exitwhen i == exit
                    endloop
                    exitwhen i == damageStack
                endloop
            endif
            call unfreeze()
        endif
    endmethod

    private static method failsafeClear takes nothing returns nothing
        static if USE_ARMOR_MOD then
            call Damage.index.setArmor(true)
        endif
        set canKick = true
        set kicking = false

        set waitingForDamageEventToRun = false

        if udg_DamageEventDamageT != 0 then
            call DamageTrigger.DAMAGE.run()
            set eventsRun   = true
        endif

        call finish()
    endmethod

    static method operator enabled= takes boolean b returns nothing
        if b then
            if dreaming then
                call EnableTrigger(recursiveTrigger)
            else
                call EnableTrigger(damagingTrigger)
                call EnableTrigger(damagedTrigger)
            endif
        else
            if dreaming then
                call DisableTrigger(recursiveTrigger)
            else
                call DisableTrigger(damagingTrigger)
                call DisableTrigger(damagedTrigger)
            endif
        endif
    endmethod

    static method operator enabled takes nothing returns boolean
        return IsTriggerEnabled(damagingTrigger)
    endmethod

    private static boolean arisen = false

    private static method getOutOfBed takes nothing returns nothing
        if waitingForDamageEventToRun then
            call failsafeClear() //WarCraft 3 didn't run the DAMAGED event despite running the DAMAGING event.
        else
            set canKick     = true
            set kicking     = false
            call finish()
        endif

        static if USE_EXTRA then
            call onAOEEnd()
        endif

        set arisen = true
    endmethod

    private static method wakeUp takes nothing returns nothing
        set dreaming = false
        set Damage.enabled = true

        call ForForce(bj_FORCE_PLAYER[0], function thistype.getOutOfBed) //Moved to a new thread in case of a thread crash

        if not arisen then
            //call BJDebugMsg("DamageEngine issue: thread crashed!")
            call unfreeze()
        else
            set arisen = false
        endif

        set Damage.count    = 0
        set Damage.index    = 0
        set timerStarted        = false

        //call BJDebugMsg("Timer wrapped up")
    endmethod

    private method addRecursive takes nothing returns nothing
        if not (this.damage == 0.00) then

            set this.recursiveTrig = DamageTrigger.eventIndex

            if not this.isCode then
                set this.isCode = true
                set this.userType = TYPE_CODE
            endif

            set inception = inception or DamageTrigger.eventIndex.inceptionTrig

            if kicking and IsUnitInGroup(this.sourceUnit, recursionSources) and IsUnitInGroup(this.targetUnit, recursionTargets) then
                if not inception then
                    set DamageTrigger.eventIndex.trigFrozen = true
                elseif not DamageTrigger.eventIndex.trigFrozen then
                    set DamageTrigger.eventIndex.inceptionTrig = true
                    if DamageTrigger.eventIndex.levelsDeep < sleepLevel then
                        set DamageTrigger.eventIndex.levelsDeep = DamageTrigger.eventIndex.levelsDeep + 1
                        if DamageTrigger.eventIndex.levelsDeep >= LIMBO then
                            set DamageTrigger.eventIndex.trigFrozen = true
                        endif
                    endif
                endif
            endif

            set damageStack.stackRef = this
            set damageStack = damageStack + 1

            //call BJDebugMsg("damageStack: " + I2S(damageStack) + " levelsDeep: " + I2S(DamageTrigger.eventIndex.levelsDeep) + " sleepLevel: " + I2S(sleepLevel))
        endif
        set inception = false
    endmethod

    private static method clearNexts takes nothing returns nothing
        set udg_NextDamageIsAttack      = false
        set udg_NextDamageType          = 0
        set udg_NextDamageWeaponT       = 0

        static if USE_MELEE_RANGE then
            set udg_NextDamageIsMelee       = false
            set udg_NextDamageIsRanged      = false
        endif
    endmethod

    static method create takes unit src, unit tgt, real amt, boolean a, attacktype at, damagetype dt, weapontype wt returns Damage
        local Damage d      = Damage.count + 1
        set Damage.count    = d
        set d.sourceUnit    = src
        set d.targetUnit    = tgt
        set d.damage        = amt
        set d.prevAmt       = amt

        set d.attackType    = at
        set d.damageType    = dt
        set d.weaponType    = wt

        set d.isAttack      = udg_NextDamageIsAttack or a
        set d.isSpell       = d.attackType == null and not d.isAttack
        return d
    endmethod

    private static method createFromEvent takes nothing returns Damage
        local Damage d = create( /*
            */ GetEventDamageSource(), /*
            */ GetTriggerUnit(), /*
            */ GetEventDamage(), /*
            */ BlzGetEventIsAttack(), /*
            */ BlzGetEventAttackType(), /*
            */ BlzGetEventDamageType(), /*
            */ BlzGetEventWeaponType() /*
        */ )

        set d.isCode = udg_NextDamageType != 0 or /*
            */ udg_NextDamageIsAttack or /*
            */ udg_NextDamageIsRanged or /*
            */ udg_NextDamageIsMelee or /*
            */ d.damageType == DAMAGE_TYPE_MIND or /*
            */ udg_NextDamageWeaponT != 0 or /*
            */ (d.damageType == DAMAGE_TYPE_UNKNOWN and not (d.damage == 0.00))

        if d.isCode then
            if udg_NextDamageType != 0 then
                set d.userType = udg_NextDamageType
            else
                set d.userType = TYPE_CODE
            endif

            static if USE_MELEE_RANGE then
                set d.isMelee = udg_NextDamageIsMelee
                set d.isRanged = udg_NextDamageIsRanged
            endif

            set d.eFilter               = FILTER_CODE

            if udg_NextDamageWeaponT != 0 then
                set d.weaponType = ConvertWeaponType(udg_NextDamageWeaponT)
                set udg_NextDamageWeaponT = 0
            endif
        else
            set d.userType              = 0

            if d.damageType == DAMAGE_TYPE_NORMAL and d.isAttack then

                static if USE_MELEE_RANGE then
                    set d.isMelee           = IsUnitType(d.sourceUnit, UNIT_TYPE_MELEE_ATTACKER)
                    set d.isRanged          = IsUnitType(d.sourceUnit, UNIT_TYPE_RANGED_ATTACKER)

                    if d.isMelee and d.isRanged then
                        set d.isMelee       = d.weaponType != null  // Melee units play a sound when damaging
                        set d.isRanged      = not d.isMelee         // In the case where a unit is both ranged and melee, the ranged attack plays no sound.
                    endif

                    if d.isMelee then
                        set d.eFilter = FILTER_MELEE
                    elseif d.isRanged then
                        set d.eFilter = FILTER_RANGED
                    else
                        set d.eFilter = FILTER_ATTACK
                    endif
                else
                    set d.eFilter = FILTER_ATTACK
                endif
            else
                if d.isSpell then
                    set d.eFilter = FILTER_SPELL
                else
                    set d.eFilter = FILTER_OTHER
                endif

                static if USE_MELEE_RANGE then
                    set d.isMelee           = false
                    set d.isRanged          = false
                endif
            endif
        endif
        call clearNexts()
        return d
    endmethod

    private static method onRecursion takes nothing returns boolean
        local Damage d  = Damage.createFromEvent()
        call d.addRecursive()
        call BlzSetEventDamage(0.00)
        return false
    endmethod

    private static method onDamaging takes nothing returns boolean
        local Damage d              = Damage.createFromEvent()

        //call BJDebugMsg("Pre-damage event running for " + GetUnitName(GetTriggerUnit()))

        if timerStarted then
            if waitingForDamageEventToRun then
                //WarCraft 3 didn't run the DAMAGED event despite running the DAMAGING event.

                if d.damageType == DAMAGE_TYPE_SPIRIT_LINK or /*
                    */ d.damageType == DAMAGE_TYPE_DEFENSIVE or /*
                    */ d.damageType == DAMAGE_TYPE_PLANT /*
                */ then
                    set waitingForDamageEventToRun = false
                    set lastInstance= Damage.index
                    set canKick     = false
                else
                    call failsafeClear() //Not an overlapping event - just wrap it up
                endif
            else
                call finish() //wrap up any previous damage index
            endif

            static if USE_EXTRA then
                if d.sourceUnit != udg_AOEDamageSource then

                    call onAOEEnd()
                    set udg_AOEDamageSource = d.sourceUnit
                    set udg_EnhancedDamageTarget = d.targetUnit

                elseif d.targetUnit == udg_EnhancedDamageTarget then

                    set udg_DamageEventLevel= udg_DamageEventLevel + 1

                elseif not IsUnitInGroup(d.targetUnit, udg_DamageEventAOEGroup) then
                    set udg_DamageEventAOE  = udg_DamageEventAOE + 1
                endif
            endif
        else
            call TimerStart(async, 0.00, false, function Damage.wakeUp)
            set timerStarted = true

            static if USE_EXTRA then
                set udg_AOEDamageSource     = d.sourceUnit
                set udg_EnhancedDamageTarget= d.targetUnit
            endif
        endif

        static if USE_EXTRA then
            call GroupAddUnit(udg_DamageEventAOEGroup, d.targetUnit)
        endif

        if d.doPreEvents(true) then
            call DamageTrigger.ZERO.run()
            set canKick = true
            call finish()
        endif
        set waitingForDamageEventToRun = lastInstance == 0 or /*
            */ attacksImmune[udg_DamageEventAttackT] or /*
            */ damagesImmune[udg_DamageEventDamageT] or /*
            */ not IsUnitType(udg_DamageEventTarget, UNIT_TYPE_MAGIC_IMMUNE)

        return false
    endmethod

    private static method onDamaged takes nothing returns boolean
        local real r = GetEventDamage()
        local Damage d = Damage.index

        //call BJDebugMsg("Second damage event running for " + GetUnitName(GetTriggerUnit()))

        if prepped > 0 then
            set prepped = 0
        elseif dreaming or d.prevAmt == 0.00 then
            return false
        elseif waitingForDamageEventToRun then
            set waitingForDamageEventToRun = false
        else
            // This should only happen for native recursive WarCraft 3 damage
            // such as Spirit Link, Thorns Aura, or Spiked Carapace / Barricades.
            call afterDamage()
            set Damage.index = lastInstance
            set lastInstance = 0
            set d = Damage.index
            set canKick = true
            call DamageTrigger.setGUIFromStruct(true)
        endif

        static if USE_ARMOR_MOD then
            call d.setArmor(true)
        endif

        static if USE_SCALING then
            if not (udg_DamageEventAmount == 0.00) and not (r == 0.00) then
                set udg_DamageScalingWC3 = r / udg_DamageEventAmount
            elseif udg_DamageEventAmount > 0.00 then
                set udg_DamageScalingWC3 = 0.00
            else
                set udg_DamageScalingWC3 = 1.00
                if udg_DamageEventPrevAmt == 0.00 then
                    set udg_DamageScalingUser = 0.00
                else
                    set udg_DamageScalingUser = udg_DamageEventAmount / udg_DamageEventPrevAmt
                endif
            endif
        endif
        set udg_DamageEventAmount = r
        set d.damage = r

        //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_GDD()
        //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_PDD()
        //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_01()
        //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_02()
        //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_03()
        //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_04()
        //! runtextmacro optional DAMAGE_EVENT_VARS_PLUGIN_05()

        if udg_DamageEventAmount > 0.00 then

            call DamageTrigger.SHIELD.run()

            static if not USE_GUI then
                set udg_DamageEventAmount = d.damage
            endif

            static if USE_LETHAL then
                if hasLethal or udg_DamageEventType < 0 then
                    set udg_LethalDamageHP = /*
                        */ GetWidgetLife(udg_DamageEventTarget) - udg_DamageEventAmount

                    if udg_LethalDamageHP <= DEATH_VAL then
                        if hasLethal then
                            call DamageTrigger.LETHAL.run()

                            set udg_DamageEventAmount = /*
                                */ GetWidgetLife(udg_DamageEventTarget) - udg_LethalDamageHP
                            set d.damage = udg_DamageEventAmount
                        endif
                        if udg_DamageEventType < 0 and udg_LethalDamageHP <= DEATH_VAL then
                            call SetUnitExploded(udg_DamageEventTarget, true)
                        endif
                    endif
                endif
            endif

            static if USE_SCALING then
                if udg_DamageEventPrevAmt == 0.00 or udg_DamageScalingWC3 == 0.00 then
                    set udg_DamageScalingUser = 0.00
                else
                    set udg_DamageScalingUser = udg_DamageEventAmount / udg_DamageEventPrevAmt / udg_DamageScalingWC3
                endif
            endif
        endif

        if udg_DamageEventDamageT != 0 then
            call DamageTrigger.DAMAGE.run()
        endif

        call BlzSetEventDamage(udg_DamageEventAmount)

        set eventsRun = true

        if udg_DamageEventAmount == 0.00 then
            call finish()
        endif

        // This return statement was needed years ago to avoid potential crashes on Mac.
        // I am not sure if that's still a thing.
        return false
    endmethod

    static method apply takes /*
        */ unit src, /*
        */ unit tgt, /*
        */ real amt, /*
        */ boolean a, /*
        */ boolean r, /*
        */ attacktype at, /*
        */ damagetype dt, /*
        */ weapontype wt /*
    */ returns Damage
        local Damage d

        if udg_NextDamageType == 0 then
           set udg_NextDamageType = TYPE_CODE
        endif

        if dreaming then
            set d = create(src, tgt, amt, a, at, dt, wt)
            set d.isCode = true
            set d.eFilter = FILTER_CODE

            set d.userType = udg_NextDamageType

            static if USE_MELEE_RANGE then
                if not d.isSpell then
                    set d.isRanged = udg_NextDamageIsRanged or r
                    set d.isMelee  = not d.isRanged
                endif
            endif

            call d.addRecursive()
        else
            call UnitDamageTarget(src, tgt, amt, a, r, at, dt, wt)

            set d = Damage.index

            call finish()
        endif

        call clearNexts()

        return d
    endmethod

    static method applySpell takes unit src, unit tgt, real amt, damagetype dt returns Damage
        return apply(src, tgt, amt, false, false, null, dt, null)
    endmethod

    static method applyAttack takes unit src, unit tgt, real amt, boolean ranged, attacktype at, weapontype wt returns Damage
        return apply(src, tgt, amt, true, ranged, at, DAMAGE_TYPE_NORMAL, wt)
    endmethod

    /*
        This part is the most critical to get things kicked off. All the code we've seen up until now
        is related to event handling, trigger assignment, edge cases, etc. But it's the following that
        is really quite esesntial for any damage engine - not just this one.
    */
    private static method onInit takes nothing returns nothing
        set async = CreateTimer()

        set recursionSources = CreateGroup()
        set recursionTargets = CreateGroup()

        set damagingTrigger  = CreateTrigger()
        set damagedTrigger   = CreateTrigger()
        set recursiveTrigger = CreateTrigger() //Moved from globals block as per request of user Ricola3D

        call TriggerRegisterAnyUnitEventBJ(damagingTrigger, EVENT_PLAYER_UNIT_DAMAGING)
        call TriggerAddCondition(damagingTrigger, Filter(function Damage.onDamaging))

        call TriggerRegisterAnyUnitEventBJ(damagedTrigger, EVENT_PLAYER_UNIT_DAMAGED)
        call TriggerAddCondition(damagedTrigger, Filter(function Damage.onDamaged))

        //For recursion
        call TriggerRegisterAnyUnitEventBJ(recursiveTrigger, EVENT_PLAYER_UNIT_DAMAGING)
        call TriggerAddCondition(recursiveTrigger, Filter(function Damage.onRecursion))
        call DisableTrigger(recursiveTrigger) //starts disabled. Will be enabled during recursive event handling.

        //For preventing Thorns/Defensive glitch.
        //Data gathered from https://www.hiveworkshop.com/threads/repo-in-progress-mapping-damage-types-to-their-abilities.316271/
        set attacksImmune[0]  = false   //ATTACK_TYPE_NORMAL
        set attacksImmune[1]  = true    //ATTACK_TYPE_MELEE
        set attacksImmune[2]  = true    //ATTACK_TYPE_PIERCE
        set attacksImmune[3]  = true    //ATTACK_TYPE_SIEGE
        set attacksImmune[4]  = false   //ATTACK_TYPE_MAGIC
        set attacksImmune[5]  = true    //ATTACK_TYPE_CHAOS
        set attacksImmune[6]  = true    //ATTACK_TYPE_HERO

        set damagesImmune[0]  = true    //DAMAGE_TYPE_UNKNOWN
        set damagesImmune[4]  = true    //DAMAGE_TYPE_NORMAL
        set damagesImmune[5]  = true    //DAMAGE_TYPE_ENHANCED
        set damagesImmune[8]  = false   //DAMAGE_TYPE_FIRE
        set damagesImmune[9]  = false   //DAMAGE_TYPE_COLD
        set damagesImmune[10] = false   //DAMAGE_TYPE_LIGHTNING
        set damagesImmune[11] = true    //DAMAGE_TYPE_POISON
        set damagesImmune[12] = true    //DAMAGE_TYPE_DISEASE
        set damagesImmune[13] = false   //DAMAGE_TYPE_DIVINE
        set damagesImmune[14] = false   //DAMAGE_TYPE_MAGIC
        set damagesImmune[15] = false   //DAMAGE_TYPE_SONIC
        set damagesImmune[16] = true    //DAMAGE_TYPE_ACID
        set damagesImmune[17] = false   //DAMAGE_TYPE_FORCE
        set damagesImmune[18] = false   //DAMAGE_TYPE_DEATH
        set damagesImmune[19] = false   //DAMAGE_TYPE_MIND
        set damagesImmune[20] = false   //DAMAGE_TYPE_PLANT
        set damagesImmune[21] = false   //DAMAGE_TYPE_DEFENSIVE
        set damagesImmune[22] = true    //DAMAGE_TYPE_DEMOLITION
        set damagesImmune[23] = true    //DAMAGE_TYPE_SLOW_POISON
        set damagesImmune[24] = false   //DAMAGE_TYPE_SPIRIT_LINK
        set damagesImmune[25] = false   //DAMAGE_TYPE_SHADOW_STRIKE
        set damagesImmune[26] = true    //DAMAGE_TYPE_UNIVERSAL
    endmethod

    //! runtextmacro optional DAMAGE_EVENT_STRUCT_PLUGIN_DMGPKG()
    //! runtextmacro optional DAMAGE_EVENT_STRUCT_PLUGIN_01()
    //! runtextmacro optional DAMAGE_EVENT_STRUCT_PLUGIN_02()
    //! runtextmacro optional DAMAGE_EVENT_STRUCT_PLUGIN_03()
    //! runtextmacro optional DAMAGE_EVENT_STRUCT_PLUGIN_04()
    //! runtextmacro optional DAMAGE_EVENT_STRUCT_PLUGIN_05()

endstruct

// Called from the GUI configuration trigger once the assignments are in place.
public function DebugStr takes nothing returns nothing
    local integer i = 0
    loop
        set udg_CONVERTED_ATTACK_TYPE[i] = ConvertAttackType(i)
        exitwhen i == 6
        set i = i + 1
    endloop

    set i = 0
    loop
        set udg_CONVERTED_DAMAGE_TYPE[i] = ConvertDamageType(i)
        exitwhen i == 26
        set i = i + 1
    endloop

    set udg_AttackTypeDebugStr[0]        = "SPELLS"   //ATTACK_TYPE_NORMAL in JASS
    set udg_AttackTypeDebugStr[1]        = "NORMAL"   //ATTACK_TYPE_MELEE in JASS
    set udg_AttackTypeDebugStr[2]        = "PIERCE"
    set udg_AttackTypeDebugStr[3]        = "SIEGE"
    set udg_AttackTypeDebugStr[4]        = "MAGIC"
    set udg_AttackTypeDebugStr[5]        = "CHAOS"
    set udg_AttackTypeDebugStr[6]        = "HERO"
    set udg_DamageTypeDebugStr[0]        = "UNKNOWN"
    set udg_DamageTypeDebugStr[4]        = "NORMAL"
    set udg_DamageTypeDebugStr[5]        = "ENHANCED"
    set udg_DamageTypeDebugStr[8]        = "FIRE"
    set udg_DamageTypeDebugStr[9]        = "COLD"
    set udg_DamageTypeDebugStr[10]       = "LIGHTNING"
    set udg_DamageTypeDebugStr[11]       = "POISON"
    set udg_DamageTypeDebugStr[12]       = "DISEASE"
    set udg_DamageTypeDebugStr[13]       = "DIVINE"
    set udg_DamageTypeDebugStr[14]       = "MAGIC"
    set udg_DamageTypeDebugStr[15]       = "SONIC"
    set udg_DamageTypeDebugStr[16]       = "ACID"
    set udg_DamageTypeDebugStr[17]       = "FORCE"
    set udg_DamageTypeDebugStr[18]       = "DEATH"
    set udg_DamageTypeDebugStr[19]       = "MIND"
    set udg_DamageTypeDebugStr[20]       = "PLANT"
    set udg_DamageTypeDebugStr[21]       = "DEFENSIVE"
    set udg_DamageTypeDebugStr[22]       = "DEMOLITION"
    set udg_DamageTypeDebugStr[23]       = "SLOW_POISON"
    set udg_DamageTypeDebugStr[24]       = "SPIRIT_LINK"
    set udg_DamageTypeDebugStr[25]       = "SHADOW_STRIKE"
    set udg_DamageTypeDebugStr[26]       = "UNIVERSAL"
    set udg_WeaponTypeDebugStr[0]        = "NONE"    //WEAPON_TYPE_WHOKNOWS in JASS
    set udg_WeaponTypeDebugStr[1]        = "METAL_LIGHT_CHOP"
    set udg_WeaponTypeDebugStr[2]        = "METAL_MEDIUM_CHOP"
    set udg_WeaponTypeDebugStr[3]        = "METAL_HEAVY_CHOP"
    set udg_WeaponTypeDebugStr[4]        = "METAL_LIGHT_SLICE"
    set udg_WeaponTypeDebugStr[5]        = "METAL_MEDIUM_SLICE"
    set udg_WeaponTypeDebugStr[6]        = "METAL_HEAVY_SLICE"
    set udg_WeaponTypeDebugStr[7]        = "METAL_MEDIUM_BASH"
    set udg_WeaponTypeDebugStr[8]        = "METAL_HEAVY_BASH"
    set udg_WeaponTypeDebugStr[9]        = "METAL_MEDIUM_STAB"
    set udg_WeaponTypeDebugStr[10]       = "METAL_HEAVY_STAB"
    set udg_WeaponTypeDebugStr[11]       = "WOOD_LIGHT_SLICE"
    set udg_WeaponTypeDebugStr[12]       = "WOOD_MEDIUM_SLICE"
    set udg_WeaponTypeDebugStr[13]       = "WOOD_HEAVY_SLICE"
    set udg_WeaponTypeDebugStr[14]       = "WOOD_LIGHT_BASH"
    set udg_WeaponTypeDebugStr[15]       = "WOOD_MEDIUM_BASH"
    set udg_WeaponTypeDebugStr[16]       = "WOOD_HEAVY_BASH"
    set udg_WeaponTypeDebugStr[17]       = "WOOD_LIGHT_STAB"
    set udg_WeaponTypeDebugStr[18]       = "WOOD_MEDIUM_STAB"
    set udg_WeaponTypeDebugStr[19]       = "CLAW_LIGHT_SLICE"
    set udg_WeaponTypeDebugStr[20]       = "CLAW_MEDIUM_SLICE"
    set udg_WeaponTypeDebugStr[21]       = "CLAW_HEAVY_SLICE"
    set udg_WeaponTypeDebugStr[22]       = "AXE_MEDIUM_CHOP"
    set udg_WeaponTypeDebugStr[23]       = "ROCK_HEAVY_BASH"
    set udg_DefenseTypeDebugStr[0]       = "LIGHT"
    set udg_DefenseTypeDebugStr[1]       = "MEDIUM"
    set udg_DefenseTypeDebugStr[2]       = "HEAVY"
    set udg_DefenseTypeDebugStr[3]       = "FORTIFIED"
    set udg_DefenseTypeDebugStr[4]       = "NORMAL"   //Typically deals flat damage to all armor types
    set udg_DefenseTypeDebugStr[5]       = "HERO"
    set udg_DefenseTypeDebugStr[6]       = "DIVINE"
    set udg_DefenseTypeDebugStr[7]       = "UNARMORED"
    set udg_ArmorTypeDebugStr[0]         = "NONE"      //ARMOR_TYPE_WHOKNOWS in JASS, added in 1.31
    set udg_ArmorTypeDebugStr[1]         = "FLESH"
    set udg_ArmorTypeDebugStr[2]         = "METAL"
    set udg_ArmorTypeDebugStr[3]         = "WOOD"
    set udg_ArmorTypeDebugStr[4]         = "ETHEREAL"
    set udg_ArmorTypeDebugStr[5]         = "STONE"
    // -
    // Added 25 July 2017 to allow detection of things like Bash or Pulverize or AOE spread
    // -
    set udg_DamageEventAOE = 1
    set udg_DamageEventLevel = 1
    // -
    // In-game World Editor doesn't allow Attack Type and Damage Type comparisons. Therefore I need to code them as integers into GUI
    // -
    set udg_ATTACK_TYPE_SPELLS = 0
    set udg_ATTACK_TYPE_NORMAL = 1
    set udg_ATTACK_TYPE_PIERCE = 2
    set udg_ATTACK_TYPE_SIEGE = 3
    set udg_ATTACK_TYPE_MAGIC = 4
    set udg_ATTACK_TYPE_CHAOS = 5
    set udg_ATTACK_TYPE_HERO = 6
    // -
    set udg_DAMAGE_TYPE_UNKNOWN = 0
    set udg_DAMAGE_TYPE_NORMAL = 4
    set udg_DAMAGE_TYPE_ENHANCED = 5
    set udg_DAMAGE_TYPE_FIRE = 8
    set udg_DAMAGE_TYPE_COLD = 9
    set udg_DAMAGE_TYPE_LIGHTNING = 10
    set udg_DAMAGE_TYPE_POISON = 11
    set udg_DAMAGE_TYPE_DISEASE = 12
    set udg_DAMAGE_TYPE_DIVINE = 13
    set udg_DAMAGE_TYPE_MAGIC = 14
    set udg_DAMAGE_TYPE_SONIC = 15
    set udg_DAMAGE_TYPE_ACID = 16
    set udg_DAMAGE_TYPE_FORCE = 17
    set udg_DAMAGE_TYPE_DEATH = 18
    set udg_DAMAGE_TYPE_MIND = 19
    set udg_DAMAGE_TYPE_PLANT = 20
    set udg_DAMAGE_TYPE_DEFENSIVE = 21
    set udg_DAMAGE_TYPE_DEMOLITION = 22
    set udg_DAMAGE_TYPE_SLOW_POISON = 23
    set udg_DAMAGE_TYPE_SPIRIT_LINK = 24
    set udg_DAMAGE_TYPE_SHADOW_STRIKE = 25
    set udg_DAMAGE_TYPE_UNIVERSAL = 26
    // -
    // The below variables don't affect damage amount, but do affect the sound played
    // They also give important information about the type of attack used.
    // They can differentiate between ranged and melee for units who are both
    // -
    set udg_WEAPON_TYPE_NONE = 0
    // Metal Light/Medium/Heavy
    set udg_WEAPON_TYPE_ML_CHOP = 1
    set udg_WEAPON_TYPE_MM_CHOP = 2
    set udg_WEAPON_TYPE_MH_CHOP = 3
    set udg_WEAPON_TYPE_ML_SLICE = 4
    set udg_WEAPON_TYPE_MM_SLICE = 5
    set udg_WEAPON_TYPE_MH_SLICE = 6
    set udg_WEAPON_TYPE_MM_BASH = 7
    set udg_WEAPON_TYPE_MH_BASH = 8
    set udg_WEAPON_TYPE_MM_STAB = 9
    set udg_WEAPON_TYPE_MH_STAB = 10

    // Wood Light/Medium/Heavy
    set udg_WEAPON_TYPE_WL_SLICE = 11
    set udg_WEAPON_TYPE_WM_SLICE = 12
    set udg_WEAPON_TYPE_WH_SLICE = 13
    set udg_WEAPON_TYPE_WL_BASH = 14
    set udg_WEAPON_TYPE_WM_BASH = 15
    set udg_WEAPON_TYPE_WH_BASH = 16
    set udg_WEAPON_TYPE_WL_STAB = 17
    set udg_WEAPON_TYPE_WM_STAB = 18

    // Claw Light/Medium/Heavy
    set udg_WEAPON_TYPE_CL_SLICE = 19
    set udg_WEAPON_TYPE_CM_SLICE = 20
    set udg_WEAPON_TYPE_CH_SLICE = 21

    // Axe Medium
    set udg_WEAPON_TYPE_AM_CHOP = 22

    // Rock Heavy
    set udg_WEAPON_TYPE_RH_BASH = 23

    /*
        Since GUI still doesn't provide Defense Type and Armor Types,
        I needed to include the below:
    */
    set udg_ARMOR_TYPE_NONE = 0
    set udg_ARMOR_TYPE_FLESH = 1
    set udg_ARMOR_TYPE_METAL = 2
    set udg_ARMOR_TYPE_WOOD = 3
    set udg_ARMOR_TYPE_ETHEREAL = 4
    set udg_ARMOR_TYPE_STONE = 5

    set udg_DEFENSE_TYPE_LIGHT = 0
    set udg_DEFENSE_TYPE_MEDIUM = 1
    set udg_DEFENSE_TYPE_HEAVY = 2
    set udg_DEFENSE_TYPE_FORTIFIED = 3
    set udg_DEFENSE_TYPE_NORMAL = 4
    set udg_DEFENSE_TYPE_HERO = 5
    set udg_DEFENSE_TYPE_DIVINE = 6
    set udg_DEFENSE_TYPE_UNARMORED = 7

    /*
        The remaining stuff is an ugly 'optimization' that I did a long
        time ago, thinking that it would improve performance for GUI users
        by not having so many different triggerconditions evaluating per
        damage event. I am not sure if it even worked; in Lua it might
        perform worse, but in vJass it remains to be tested.
    */

    set udg_UNIT_CLASS_HERO = 0
    set udg_UNIT_CLASS_DEAD = 1
    set udg_UNIT_CLASS_STRUCTURE = 2

    set udg_UNIT_CLASS_FLYING = 3
    set udg_UNIT_CLASS_GROUND = 4

    set udg_UNIT_CLASS_ATTACKS_FLYING = 5
    set udg_UNIT_CLASS_ATTACKS_GROUND = 6

    set udg_UNIT_CLASS_MELEE = 7
    set udg_UNIT_CLASS_RANGED = 8

    set udg_UNIT_CLASS_GIANT = 9
    set udg_UNIT_CLASS_SUMMONED = 10
    set udg_UNIT_CLASS_STUNNED = 11
    set udg_UNIT_CLASS_PLAGUED = 12
    set udg_UNIT_CLASS_SNARED = 13

    set udg_UNIT_CLASS_UNDEAD = 14
    set udg_UNIT_CLASS_MECHANICAL = 15
    set udg_UNIT_CLASS_PEON = 16
    set udg_UNIT_CLASS_SAPPER = 17
    set udg_UNIT_CLASS_TOWNHALL = 18
    set udg_UNIT_CLASS_ANCIENT = 19

    set udg_UNIT_CLASS_TAUREN = 20
    set udg_UNIT_CLASS_POISONED = 21
    set udg_UNIT_CLASS_POLYMORPHED = 22
    set udg_UNIT_CLASS_SLEEPING = 23
    set udg_UNIT_CLASS_RESISTANT = 24
    set udg_UNIT_CLASS_ETHEREAL = 25
    set udg_UNIT_CLASS_MAGIC_IMMUNE = 26

    set udg_DamageFilterAttackT = -1
    set udg_DamageFilterDamageT = -1
    set udg_DamageFilterSourceC = -1
    set udg_DamageFilterTargetC = -1
    set udg_DamageFilterRunChance = 1.00
endfunction

public function RegisterFromHook takes /*
    */ trigger whichTrig, /*
    */ string var, /*
    */ limitop op, /*
    */ real value /*
*/ returns nothing
    call DamageTrigger.registerVerbose(whichTrig, var, value, true, GetHandleId(op))
endfunction
hook TriggerRegisterVariableEvent RegisterFromHook

function TriggerRegisterDamageEngineEx takes /*
    */ trigger whichTrig, /*
    */ string eventName, /*
    */ real value, /*
    */ integer opId /*
*/ returns DamageTrigger
    return DamageTrigger.registerVerbose( /*
        */ whichTrig, /*
        */ DamageTrigger.getVerboseStr(eventName), /*
        */ value, /*
        */ false, /*
        */ opId /*
    */ )
endfunction

function TriggerRegisterDamageEngine takes /*
    */ trigger whichTrig, /*
    */ string eventName, /*
    */ real value /*
*/ returns DamageTrigger
    return DamageTrigger.registerTrigger(whichTrig, eventName, value)
endfunction

function RegisterDamageEngineEx takes /*
    */ code callback, /*
    */ string eventName, /*
    */ real value, /*
    */ integer opId /*
*/ returns DamageTrigger
    return TriggerRegisterDamageEngineEx(DamageTrigger[callback], eventName, value, opId)
endfunction

//Similar to TriggerRegisterDamageEvent, but takes code instead of trigger as the first argument.
function RegisterDamageEngine takes /*
    */ code callback, /*
    */ string eventName, /*
    */ real value /*
*/ returns DamageTrigger
    return RegisterDamageEngineEx(callback, eventName, value, FILTER_OTHER)
endfunction

/*
    The below macros are for GUI to tap into more powerful vJass event filtering:
*/

//! textmacro DAMAGE_TRIGGER_CONFIG
    if not DamageTrigger.eventIndex.configured then
//! endtextmacro

//! textmacro DAMAGE_TRIGGER_CONFIG_END
        call DamageTrigger.eventIndex.configure()
    endif
    if not DamageTrigger.eventIndex.checkConfig() then
        return
    endif
//! endtextmacro

endlibrary
