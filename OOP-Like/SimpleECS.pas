unit SimpleECS;
{ Simple Entity Component System.

  Note that for performance reasons, all error checking is done with assertions.
  This way, you can disable error checking in release builds by turning off
  assertions. }

interface

uses
  System.Generics.Collections;

type
  { A bitmask that can be used to identify up to 64 system/manager/component
    types. }
  TTypeBits = UInt64;

const
  { Maximum number of system/manager/component types. }
  MAX_TYPES = SizeOf(TTypeBits) * 8;

type
  { Types of events a TEventListener can subscribe to }
  TEventType = (
    { Is called after an entity has been added to the world. }
    EntityAdded,

    { Is called after an entity has been removed from the world. }
    EntityRemoved,

    { Is called before any world updates are performed. }
    BeforeUpdate,

    { Is called when a world update is performed. }
    Update,

    { Is called after all updates to the world have been performed. }
    AfterUpdate);
  TEventTypes = set of TEventType;

type
  { Utility to generate unique auto-incrementing numbers for Delphi types.
    Uses compile-time "tricks" to make sure that all types you use with this
    generator have a unique index starting from 0.

    This is explained in our blog post "Mapping Delphi Types to Indices at
    Compile Time".
    (https://blog.grijjy.com/2020/04/21/mapping-delphi-types-to-indices-at-compile-time/)

    You can use this to map a Delphi type to an index. Without this utility, you
    could create a TDictionary<PTypeInfo, Integer> to map a Delphi type to an
    index. However, this requires a dictionary lookup at run-time, which incurs
    a performance penalty.

    With this utility, compile-time generic class variables are used to generate
    these indices once during application startup. After that, mapping a Delphi
    type to an index is a very cheap operation.

    For additional flexibility, you can have different "categories" of type
    indices. Each category has its own sequence of auto-incrementing numbers
    starting at 0. The category is a type by itself. This can be any Delphi
    type, a custom type, or an distinct alias to another type. For example:

      type
        TMyCategory = type Integer;

      TTypeIndex<Integer>.Get<Integer>();     ==> 0
      TTypeIndex<Integer>.Get<Single>();      ==> 1
      TTypeIndex<Integer>.Get<String>();      ==> 2
      TTypeIndex<Integer>.Get<Single>();      ==> 1 (again)
      TTypeIndex<TMyCategory>.Get<Single>();  ==> 0 (different category)

    As you can see, type indices from the "Integer" category are different
    from indices from the "TMyCategory" category. The type index for any
    combination of category and type remains constant for the duration of the
    app. All these sequences start at 0, so you can use the returned indices
    to quickly index into an array (instead of using a TDictionary).

    The generic Get method is very fast since it doesn't have to perform any
    lookup or calculations (in fact, it only returns the value of a class
    variable that is specific to the category/type combination). }
  TTypeIndex<TCategory> = class // static
  {$REGION 'Internal Declarations'}
  private type
    TIndex<T> = record
    private class var
      FValue: Integer;
    public
      class constructor Create;
    end;
  private class var
    FNextIndex: Integer;
  public
    class constructor Create;
  {$ENDREGION 'Internal Declarations'}
  public
    { Gets a unique index for type T within category TCategory.
      Returned values start at 0 and increment for each type that is used
      with this utility. So for example, you can use these indices to quickly
      index into an array with information specific to type T. }
    class function Get<T>: Integer; inline; static;
  end;

type
  { A reference to a value type. }
  TRef<T: record> = record
  {$REGION 'Internal Declarations'}
  private type
    P = ^T;
  private
    FRef: P;
    function GetRef: T; inline;
    procedure SetRef(const AValue: T); inline;
  {$ENDREGION 'Internal Declarations'}
  public
    { Whether this is a nil reference }
    function IsNil: Boolean; inline;

    { The referenced value.

      Raises:
        EAssertionFailed (if enabled) if this is a nil reference.
        You can check for this using the IsNil method. }
    property Ref: T read GetRef write SetRef;
  end;

type
  TWorld = class;

  { Uniquely identifies an entity inside a TWorld. }
  TEntityId = Cardinal;
  PEntityId = ^TEntityId;

  { A light-weight entity.

    An entity is just an identifier. To make it useful, you add components
    (see AddComponent) and update those components using systems (see TSystem).

    A component is usually just a POD-type. Components are identified by their
    type, so you must make sure that every component has a unique type. You can
    do this be declaring your own record type, as in:

      TPosition = record
        X, Y: Single;
      end;

    Or by creating a distinct alias, as in:

      TPosition = type TPointF;

    Entities are part of a world (see TWorld) and are created by calling
    TWorld.CreateEntity.}
  TEntity = record
  {$REGION 'Internal Declarations'}
  private
    FId: TEntityId;
    FWorld: TWorld; // Reference
    function GetIsValid: Boolean; inline;
  private
    procedure Initialize(const AId: TEntityId; const AWorld: TWorld); inline;
  {$ENDREGION 'Internal Declarations'}
  public
    { Frees the entity.

      Raises:
        EAssertionFailed (if enabled) if the entity is unassigned or has already
        been freed.

      Since an entity is just an identifier, it isn't actually freed, but this
      will remove any components attached to the entity, and remove the entity
      from any list where it is used.

      This operation is delayed until after the next update (see TWorld.Update).
      The identififier will be reused when a new entity is created. }
    procedure Free; inline;

    { Equality operators }
    class operator Equal(const ALeft, ARight: TEntity): Boolean; inline; static;
    class operator NotEqual(const ALeft, ARight: TEntity): Boolean; inline; static;

    { Adds a component to the entity.

      Parameters:
        T: the type of the component to add, usually a POD type. The type can
           usually be inferred by the compiler. In that case you can omit it.
        AComponent: the component to add (of type T).

      Raises:
        EAssertionFailed (if enabled) if the entity is unassigned or has been
        freed, or if there are more than 64 component types being used.

      In reality, the entity does *not* maintain a list of components (again, an
      entity is just an identifier). Instead, a TComponentManager manages the
      storage of all components and links to their entities. This is both light-
      weight (since entities don't have to maintain lists) and efficient (since
      this allows for cache-friendly storage of components from different
      entities). }
    procedure AddComponent<T: record>(const AComponent: T); inline;

    { Get the component attached to this entity by type.

      Parameters:
        T: the type of the component to retrieve.

      Returns:
        The component of type T, or Default(T) if the entity doesn't have a
        component of type T.

      Raises:
        EAssertionFailed (if enabled) if the entity is unassigned or has been
        freed.

      If you need to update the component, then you should use GetComponentRef
      instead. }
    function GetComponent<T: record>: T; inline;

    { Gets a reference to the component attached to this entity by type.

      Parameters:
        T: the type of the component to retrieve.

      Returns:
        A reference to the component of type T, or a nil reference if the entity
        doesn't have a component of type T.

      Raises:
        EAssertionFailed (if enabled) if the entity is unassigned or has been
        freed.

      If you don't need to update the component, then you should use
      GetComponent instead. }
    function GetComponentRef<T: record>: TRef<T>; inline;

    { Removes a component from the entity by type.

      Parameters:
        T: the type of the component to remove.

      Raises:
        EAssertionFailed (if enabled) if the entity is unassigned or has been
        freed, or if there are more than 64 component types being used. }
    procedure RemoveComponent<T: record>; inline;

    { The identifier of the entity. Every live entity has a unique identifier
      inside the World (entities from different world may have the same
      identifier). Identifiers are reused when an entity is freed and a new
      entity is created later.

      The Id will be 0 if the entity has been freed.}
    property Id: TEntityId read FId;

    { The world the entity belongs to, or nil if the entity has been freed. }
    property World: TWorld read FWorld;

    { Whether the entity is valid (that is, has a non-0 Id and a non-nil World. }
    property IsValid: Boolean read GetIsValid;
  end;
  PEntity = ^TEntity;

  { Abstract base class for classes that listen to certain "world events".
    TManager and TSystem derive from this class. }
  TEventListener = class abstract
  {$REGION 'Internal Declarations'}
  private
    FWorld: TWorld; // Reference
  {$ENDREGION 'Internal Declarations'}
  protected
    { Must be overridden to return the set of event types this listener is
      interested in. }
    class function GetSubscribedEvents: TEventTypes; virtual; abstract;

    { Is called by the ECS to initialize this instance. At this point, the World
      property contains a valid reference to the world that this listener
      belongs to. You can override this method to perform custom initialization.

      For systems, this is a good place to request the list of entities the
      system is interested in, based on a combination of components (by calling
      World.GetEntitiesWith<...>. Since that list will be automatically updated
      as entities and/or components are added or removed, it is sufficient to
      request this list only once (usually inside this method).

      This method does nothing by default. }
    procedure Initialize; virtual;

    { Is called after an entity has been added to the world.

      Parameters:
        AEntity: the entity that has been added to the world.

      This method is only called if the set returned by GetSubscribedEvents
      includes TEventType.EntityAdded.

      This method does nothing by default. }
    procedure EntityAdded(const AEntity: TEntity); virtual;

    { Is called after an entity has been removed from the world.

      Parameters:
        AEntity: the entity that has been removed from the world.

      This method is only called if the set returned by GetSubscribedEvents
      includes TEventType.EntityRemoved.

      This method does nothing by default. }
    procedure EntityRemoved(const AEntity: TEntity); virtual;

    { Is called before any world updates are performed.

      You can override this method to make any preparations before the world is
      updated. For example, a rendering system my override this method to clear
      the screen.

      This method is only called if the set returned by GetSubscribedEvents
      includes TEventType.BeforeUpdate.

      This method does nothing by default. }
    procedure BeforeUpdate; virtual;

    { Is called when a world update is performed.

      Parameters:
        ADeltaTime: the time that has passed since the last update. The time
          units are up to the developer, but is usually either seconds or
          milliseconds.

      Most systems should override this method to perform their logic.

      This method is only called if the set returned by GetSubscribedEvents
      includes TEventType.Update.

      This method does nothing by default. }
    procedure Update(const ADeltaTime: Single); virtual;

    { Is called after all updates to the world have been performed.
      You can override this method to handle actions that need to be performed
      at this time. For example, a rendering system may subscribe to this event
      to swap the back buffer to the screen.

      This method is only called if the set returned by GetSubscribedEvents
      includes TEventType.AfterUpdate.

      This method does nothing by default. }
    procedure AfterUpdate; virtual;

    { The world this listener belongs to. }
    property World: TWorld read FWorld;
  end;

  { Abstract base class for managers.

    A manager manages "objects" in the world and their life times. There are two
    predefined managers: TEntityManager is responsible for creating and
    destroying entities. TComponentManager is reponsible for adding components
    to and removing components from entities. It also maintains lists of all
    entities with certain combinations of components.

    You can also create your own managers by deriving from TManager and
    registering the manager to the world by calling TWorld.AddManager.
    By default, a World will already have an TEntityManager and
    TComponentManager.

    By default, managers don't subscribe to any events, but your own managers
    can change this behavior by overriding the GetSubscribedEvents method.

    This ECS supports at most 64 different manager types per application. }
  TManager = class abstract(TEventListener)
  {$REGION 'Internal Declarations'}
  private type
    { A specific TTypeIndex for types of managers. }
    TTypeIndex = TTypeIndex<TManager>;
  protected
    class function GetSubscribedEvents: TEventTypes; override;
  {$ENDREGION 'Internal Declarations'}
  end;

  { Abstract base class for systems.

    Systems define the behavior of your entity-component-system. This is where
    you write your logic that operates on entities with a certain combination
    of components.

    You create your own systems by deriving from TSystem and registering your
    system with the world by calling TWorld.AddSystem.

    All systems subscribe to the TEventType.Update event, but your own
    systems can subscribe to other events as well by overriding the
    GetSubscribedEvents method.

    This ECS supports at most 64 different system types per application. }
  TSystem = class abstract(TEventListener)
  {$REGION 'Internal Declarations'}
  private type
    { A specific TTypeIndex for types of systems. }
    TTypeIndex = TTypeIndex<TSystem>;
  protected
    { All systems are interested in the Update event by default. }
    class function GetSubscribedEvents: TEventTypes; override;
  {$ENDREGION 'Internal Declarations'}
  end;

  { A specific TManager responsible for creating and destroying entities.

    You usually don't call methods of this manager directly. Instead, you use
    methods of TWorld and TEntity, which will in turn call into the entity
    manager. }
  TEntityManager = class(TManager)
  {$REGION 'Internal Declarations'}
  private
    { The Id of the next entity that will be created. }
    FNextId: TEntityId;

    { A list of all entities Id's currently alive. }
    FEntities: TList<TEntityId>;

    { A list of all entities Id's availble for recycling. When an entity is
      destroyed, its Id is added to this list and reused the next time an entity
      is created. This ensures that most entity Ids will stay grouped together
      and their values stay reasonably low (so the can be used as indices into
      other lists). }
    FEntitiesToRecycle: TList<TEntityId>;

    { A list of entities that should be destroyed on the next world update.
      Entities are not destroyed immediately, but after the world has updated. }
    FEntitiesToDestroy: TList<TEntityId>;
  protected
    { This class is only interested in the AfterUpdate event. }
    class function GetSubscribedEvents: TEventTypes; override;

    { Processes entities that are marked for destruction. }
    procedure AfterUpdate; override;
  {$ENDREGION 'Internal Declarations'}
  public
    constructor Create;
    destructor Destroy; override;

    { Creates a new entity.

      Returns:
        A new entity

      You usually don't call this method yourself, but use TWorld.CreateEntity
      instead. }
    function CreateEntity: TEntity;

    { Destroys an entity.

      Parameters:
        AEntity: the entity to destroy.

      You usually don't call this method yourself, but use TEntity.Free or
      TWorld.DestroyEntity instead. }
    procedure DestroyEntity(var AEntity: TEntity);
  end;

  { A specific TManager that is reponsible for adding components to and removing
    components from entities. It also maintains lists of all entities with
    certain combinations of components.

    You usually don't call method of this manager directly. Instead, you use
    methods of TEntity and TWorld, which will in turn call into the component
    manager. }
  TComponentManager = class(TManager)
  {$REGION 'Internal Declarations'}
  private type
    { A specific TTypeIndex for types of components. }
    TComponentTypeIndex = TTypeIndex<TComponentManager>;
  private type
    { Is used to store temporary data for the delayed destruction of components. }
    TDeleteComponentInfo = record
    public
      { The entity that must be updated. }
      Entity: TEntity;

      { The original components that the entity contains. }
      OldBits: TTypeBits;

      { The new components for the entity (with a specific component removed). }
      NewBits: TTypeBits;
    end;
  private type
    { An optimized dictionary that maps a combination of components (TTypeBits)
      to a list of entities (TList<TEntity>) that supports this combination of
      components. }
    TEntitiesByComponentBits = record
    { Boilerplate dictionary stuff: }
    private const
      EMPTY_HASH = -1;
    private type
      TItem = record
        HashCode: Integer;
        Bits: TTypeBits;
        Entities: TList<TEntity>;
      end;
      PItem = ^TItem;
    private
      FItems: PItem;
      FCount: Integer;
      FCapacity: Integer;
      FGrowThreshold: Integer;
      function GetEntities(const AComponentBits: TTypeBits): TList<TEntity>;
      procedure SetEntities(const AComponentBits: TTypeBits;
        const AValue: TList<TEntity>);
    private
      class function Hash(const ABits: TTypeBits): Integer; static;
    private
      procedure Resize(ANewCapacity: Integer);
    public
      procedure Initialize;
      procedure Free;

      { Updates the dictionary when a component has been added to or removed
        from an entity.

        Parameters:
          AEntity: the entity that has changed.
          AOldBits: the original components that were assigned to the entity.
          ANewBits: the new components to assign to the entity.

        This will update any entity list that depends on a certain combination
        of components.

        When a component is added to an entity, then that entity will be added
        to any list that depends on that component type.

        When a component is removed from an entity, then that entity is removed
        from all lists that depend on that component type.

        When an entire entity is removed, then that entity is removed from all
        lists that contain the entity. }
      procedure ComponentBitsChangedFor(const AEntity: TEntity;
        const AOldBits, ANewBits: TTypeBits);

      { Maps a combination of components (TTypeBits) to a corresponding list of
        entities (TList<Entity>).

        When getting, returns nil if the dictionary does not contain an entity
        list for the given combination of components.

        When setting, raises an EAssertionFailed (if enabled) if the dictionary
        already contains a list for the given combination of components. }
      property Entities[const AComponentBits: TTypeBits]: TList<TEntity> read GetEntities write SetEntities; default;
    end;
  private
    { Keeps track of the combination of components assigned to each entity.
      The index into this list is the Id of the entity.
      So FEntityComponentBits[5] contains the combination of components assigned
      to the entity with Id 5.}
    FEntityComponentBits: TList<TTypeBits>;

    { A list of component lists by component type.
      The index into this list is the index of the component type (see
      TComponentTypeIndex).

      Each element in the list is a TList<T> of the given component type.
      For example, if component TPosition has an index of 3, then
      FComponentsByType[3] will contain a TList<TPosition> with all
      currently active position components.

      The index into that list is the Id of the entity that owns that component.
      So in this example, index [4] will contain the TPosition of entity with
      Id 4. }
    FComponentsByType: TObjectList<TObject>;

    { Maps a combination of components to a list of entities that contains all
      those components. See TEntitiesByComponentBits for more information. }
    FEntitiesByComponentBits: TEntitiesByComponentBits;

    { A temporary list that is used when a component is removed from an entity,
      to the actual removal can be performed in the next update cycle. }
    FComponentsToDelete: TList<TDeleteComponentInfo>;
  private
    { Returns a list of all components of a given type. If such a list does not
      yet exist, then it will be created. }
    function GetComponents<T>: TList<T>;

    { Returns a list of all entities that support the given combination of
      components. If such a list does not yet exist, then it will be created.}
    function GetEntitiesWith(const AComponentBits: TTypeBits): TList<TEntity>; overload;
  private
    { Helper functions that return a bitmask with set bits for 1 to 4 component
      types. That is, the bitmask represents a combination of component types. }
    class function GetComponentTypes<T>: TTypeBits; overload; static;
    class function GetComponentTypes<T1, T2>: TTypeBits; overload; static;
    class function GetComponentTypes<T1, T2, T3>: TTypeBits; overload; static;
    class function GetComponentTypes<T1, T2, T3, T4>: TTypeBits; overload; static;
  protected
    { This class is interested in the EntityAdded, EntityRemoved and AfterUpdate
      events. }
    class function GetSubscribedEvents: TEventTypes; override;

    { Updates the FEntityComponentBits list to initialize the combination of
      components for the given entity (to 0). }
    procedure EntityAdded(const AEntity: TEntity); override;

    { Removes the entity from any list that contains the entity, and resets the
      FEntityComponentBits entry for this entity to 0. }
    procedure EntityRemoved(const AEntity: TEntity); override;

    { Handles any pending component removals (initiated by RemoveComponent) }
    procedure AfterUpdate; override;
  {$ENDREGION 'Internal Declarations'}
  public
    constructor Create;
    destructor Destroy; override;

    { Adds a component to the given entity.

      Parameters:
        T: the type of the component to add, usually a POD type. The type can
           usually be inferred by the compiler. In that case you can omit it.
        AEntity: the entity to add the component to.
        AComponent: the component to add (of type T).

      Raises:
        EAssertionFailed (if enabled) if the entity is unassigned or has been
        freed, or if there are more than 64 component types being used.

      You usually don't call this method yourself, but use
      TEntity.AddComponent<T> instead. }
    procedure AddComponent<T: record>(const AEntity: TEntity; const AComponent: T);

    { Get the component attached to the given entity.

      Parameters:
        T: the type of the component to retrieve.
        AEntity: the entity to request the component from.

      Returns:
        The component of type T, or Default(T) if AEntity doesn't have a
        component of type T.

      Raises:
        EAssertionFailed (if enabled) if AEntity is unassigned or has been
        freed.

      If you need to update the component, then you should use GetComponentRef
      instead.

      You usually don't call this method yourself, but use
      TEntity.GetComponent<T> instead. }
    function GetComponent<T: record>(const AEntity: TEntity): T;

    { Get a reference to the component attached to the given entity.

      Parameters:
        T: the type of the component to retrieve.
        AEntity: the entity to request the component from.

      Returns:
        A reference to the component of type T, or a nil reference if AEntity
        doesn't have a component of type T.

      Raises:
        EAssertionFailed (if enabled) if AEntity is unassigned or has been
        freed.

      If you don't need to update the component, then you should use
      GetComponent instead.

      You usually don't call this method yourself, but use
      TEntity.GetComponentRef<T> instead. }
    function GetComponentRef<T: record>(const AEntity: TEntity): TRef<T>;

    { Removes a component from the given entity by type.

      Parameters:
        T: the type of the component to remove.
        AEntity: the entity to remove the component from.

      Raises:
        EAssertionFailed (if enabled) if the entity is unassigned or has been
        freed, or if there are more than 64 component types being used.

      You usually don't call this method yourself, but use
      TEntity.RemoveComponent<T> instead. }
    procedure RemoveComponent<T: record>(const AEntity: TEntity);

    { Get a list of all entities that support a combination of 1 to 4
      components.

      Parameters:
        TComp*: a list of 1 to 4 component types.

      Returns:
        A list of all entities that support all given component types.

      The returned list is a "live" list, meaning that it gets updated
      automatically as entities and/or components are added or removed. So it
      is sufficient to request this list (for a certain combination of
      components) only once and cache it for reuse whenever you need it.

      You usually don't call this method yourself, but use
      TWorld.GetEntitiesWith<...> instead. }
    function GetEntitiesWith<TComp>: TList<TEntity>; overload; inline;
    function GetEntitiesWith<TComp1, TComp2>: TList<TEntity>; overload; inline;
    function GetEntitiesWith<TComp1, TComp2, TComp3>: TList<TEntity>; overload; inline;
    function GetEntitiesWith<TComp1, TComp2, TComp3, TComp4>: TList<TEntity>; overload; inline;
  end;

  { A world of entities. You can have multiple worlds (scenes), each with their
    own entities, systems and managers. }
  TWorld = class
  {$REGION 'Internal Declarations'}
  private
    { All active managers, indexed by the type index of the manager. }
    FManagers: array [0..MAX_TYPES - 1] of TManager;

    { All active systems, indexed by the type index of the system. }
    FSystems: array [0..MAX_TYPES - 1] of TSystem;

    { All active event listeners, by event type. }
    FEventListeners: array [TEventType] of TList<TEventListener>;

    { Manages creation and destruction of entities. }
    FEntityManager: TEntityManager;

    { Manages adding components to and removing components from entities. Also
      maintains lists of all entities with certain combinations of components. }
    FComponentManager: TComponentManager;
  private
    procedure AddEventListener(const AListener: TEventListener);
    procedure DoEntityAdded(const AEntity: TEntity);
    procedure DoEntityRemoved(const AEntity: TEntity);
    procedure DoBeforeUpdate;
    procedure DoUpdate(const ADeltaTime: Single);
    procedure DoAfterUpdate;
  {$ENDREGION 'Internal Declarations'}
  public
    constructor Create;
    destructor Destroy; override;

    { Adds a manager to the world.

      Parameters:
        T: the type of manager to add.

      Returns:
        An instance of the manager.

      Raises:
        EAssertionFailed (if enabled) if there are more than 64 manager types
        being used.

      If a manager with the same type had previously been added, then the
      existing manager is returned.

      By default, each world has at least a TEntityManager and
      TComponentManager. You don't need to add these yourself, but you can
      define your own managers and add them.

      You should *never* free the returned manager. It is owned by this world. }
    function AddManager<T: TManager, constructor>: T;

    { Returns a manager by type.

      Parameters:
        T: the type of manager to retrieve.

      Returns:
        The manager of that type, or nil if there is no manager with the given
        type.

      Raises:
        EAssertionFailed (if enabled) if there are more than 64 manager types
        being used.

      By default, each world has at least a TEntityManager and
      TComponentManager. }
    function GetManager<T: TManager>: T; inline;

    { Adds a system to the world.

      Parameters:
        T: the type of system to add.

      Returns:
        An instance of the system.

      Raises:
        EAssertionFailed (if enabled) if there are more than 64 system types
        being used.

      If a system with the same type had previously been added, then the
      existing system is returned.

      You should *never* free the returned system. It is owned by this world. }
    function AddSystem<T: TSystem, constructor>: T;

    { Returns a system by type.

      Parameters:
        T: the type of system to retrieve.

      Returns:
        The sytem of that type, or nil if there is no system with the given
        type.

      Raises:
        EAssertionFailed (if enabled) if there are more than 64 system types
        being used. }
    function GetSystem<T: TSystem>: T; inline;

    { Creates a new entity and adds it to the world.

      Returns:
        A new entity }
    function CreateEntity: TEntity; inline;

    { Destroys an entity and removes if from the world.

      Parameters:
        AEntity: the entity to destroy. }
    procedure DestroyEntity(var AEntity: TEntity); inline;

    { Get a list of all entities that support a combination of 1 to 4
      components.

      Parameters:
        TComp*: a list of 1 to 4 component types.

      Returns:
        A list of all entities that support all given component types.

      The returned list is a "live" list, meaning that it gets updated
      automatically as entities and/or components are added or removed. So it
      is sufficient to request this list (for a certain combination of
      components) only once and cache it for reuse whenever you need it. }
    function GetEntitiesWith<TComp>: TList<TEntity>; overload; inline;
    function GetEntitiesWith<TComp1, TComp2>: TList<TEntity>; overload; inline;
    function GetEntitiesWith<TComp1, TComp2, TComp3>: TList<TEntity>; overload; inline;
    function GetEntitiesWith<TComp1, TComp2, TComp3, TComp4>: TList<TEntity>; overload; inline;

    { Updates the world.

      Parameters:
        ADeltaTime: should be set to the time that has passes since the last
          time Update was called. The units are up to the developer, but is
          usually either seconds or milliseconds.

      The will perform the following steps:
      * Fires the BeforeUpdate event for all interested listeners. By default,
        no default listeners are subscribed to this event. You may subscribe to
        this event in your own managers or systems (by overriding
        GetSubscribedEvents and BeforeUpdate). For example, a rendering system
        my subscribe to this event to clear the screen.
      * Fires the Update event. Most systems should subscribe to this event (by
        overriding GetSubscribedEvents and Update) to perform their logic.
      * Fires the AfterUpdate event. The TEntityManager and TComponentManager
        are subscribed to this event to handle delayed destruction of entities
        and/or components. You may also subscribe to this event in your own
        systems (by overriding GetSubscribedEvents and AfterUpdate). For
        example, a rendering system may subscribe to this event to swap the back
        buffer to the screen. }
    procedure Update(const ADeltaTime: Single);
  end;

implementation

{$POINTERMATH ON}

{ TTypeIndex<TCategory> }

class constructor TTypeIndex<TCategory>.Create;
begin
  FNextIndex := 0;
end;

class function TTypeIndex<TCategory>.Get<T>: Integer;
{ Trick to assign a unique auto-incrementing number to a Delphi type within a
  category of types.

  For example:
    type
      TMyCategory = type Integer;

    TTypeIndex<Integer>.Get<Integer>();     ==> 0
    TTypeIndex<Integer>.Get<Single>();      ==> 1
    TTypeIndex<Integer>.Get<String>();      ==> 2
    TTypeIndex<Integer>.Get<Single>();      ==> 1 (again)
    TTypeIndex<TMyCategory>.Get<Single>();  ==> 0 (different category)

  This trick works like this:

  TTypeIndex<TCategory> has a class variable called FNextIndex. Because
  TTypeIndex<TCategory> is a generic record, there is a different instance of
  FNextIndex for each specialized version of TCategory. In this example, there
  are two specializations (Integer and TMyCategory), so there are two versions
  of FNextIndex (and the class constructor TTypeIndex<TCategory>.Create gets
  called two times).

  Likewise, TTypeIndex<TCategory> has a nested type TIndex<T>, which has a class
  variable called FValue. Again, there is a different instance of FValue for
  each combination of TCategory and T. So in this example, there are 4 versions
  of FValue (for Integer/Integer, Integer/Single, Integer/String and
  TMyCategory/Single). The class constructor increments the higher-level
  FNextIndex for the TCategory and stores its value in FValue. }
begin
  Result := TIndex<T>.FValue;
end;

{ TTypeIndex<TCategory>.TIndex<T> }

class constructor TTypeIndex<TCategory>.TIndex<T>.Create;
begin
  FValue := FNextIndex;
  Inc(FNextIndex);
end;

{ TRef<T> }

function TRef<T>.GetRef: T;
begin
  Assert(FRef <> nil, 'Cannot access a nil reference');
  Result := FRef^;
end;

function TRef<T>.IsNil: Boolean;
begin
  Result := (FRef = nil);
end;

procedure TRef<T>.SetRef(const AValue: T);
begin
  Assert(FRef <> nil, 'Cannot access a nil reference');
  FRef^ := AValue;
end;

{ TEntity }

procedure TEntity.AddComponent<T>(const AComponent: T);
begin
  Assert(FWorld <> nil);
  FWorld.FComponentManager.AddComponent(Self, AComponent);
end;

class operator TEntity.Equal(const ALeft, ARight: TEntity): Boolean;
begin
  Result := (ALeft.FId = ARight.FId) and (ALeft.FWorld = ARight.FWorld);
end;

procedure TEntity.Free;
begin
  Assert(FWorld <> nil);
  FWorld.DestroyEntity(Self);
end;

function TEntity.GetComponent<T>: T;
begin
  Assert(FWorld <> nil);
  Result := FWorld.FComponentManager.GetComponent<T>(Self);
end;

function TEntity.GetComponentRef<T>: TRef<T>;
begin
  Assert(FWorld <> nil);
  Result := FWorld.FComponentManager.GetComponentRef<T>(Self);
end;

function TEntity.GetIsValid: Boolean;
begin
  Result := (FId <> 0) and (FWorld <> nil);
end;

procedure TEntity.Initialize(const AId: TEntityId; const AWorld: TWorld);
begin
  FId := AId;
  FWorld := AWorld
end;

class operator TEntity.NotEqual(const ALeft, ARight: TEntity): Boolean;
begin
  Result := (ALeft.FId <> ARight.FId) or (ALeft.FWorld <> ARight.FWorld);
end;

procedure TEntity.RemoveComponent<T>;
begin
  Assert(FWorld <> nil);
  FWorld.FComponentManager.RemoveComponent<T>(Self);
end;

{ TEventListener }

procedure TEventListener.AfterUpdate;
begin
  { No default implementation }
end;

procedure TEventListener.BeforeUpdate;
begin
  { No default implementation }
end;

procedure TEventListener.EntityAdded(const AEntity: TEntity);
begin
  { No default implementation }
end;

procedure TEventListener.EntityRemoved(const AEntity: TEntity);
begin
  { No default implementation }
end;

procedure TEventListener.Initialize;
begin
  { No default implementation }
end;

procedure TEventListener.Update(const ADeltaTime: Single);
begin
  { No default implementation }
end;

{ TManager }

class function TManager.GetSubscribedEvents: TEventTypes;
begin
  Result := [];
end;

{ TSystem }

class function TSystem.GetSubscribedEvents: TEventTypes;
begin
  Result := [TEventType.Update];
end;

{ TEntityManager }

procedure TEntityManager.AfterUpdate;
begin
  if (FEntitiesToDestroy.Count > 0) then
  begin
    { Destroys any entities that are marked for destruction, and moves them to
      a list of recycled entities for reuse later. }
    for var I := 0 to FEntitiesToDestroy.Count - 1 do
    begin
      var Id := FEntitiesToDestroy[I];
      Assert(FEntities.Contains(Id));
      FEntities.Remove(Id);
      FEntitiesToRecycle.Add(Id);

      var Entity: TEntity;
      Entity.Initialize(Id, World);
      World.DoEntityRemoved(Entity);
    end;
    FEntitiesToDestroy.Clear;
  end;
end;

constructor TEntityManager.Create;
begin
  inherited;
  FEntities := TList<TEntityId>.Create;
  FEntitiesToRecycle := TList<TEntityId>.Create;
  FEntitiesToDestroy := TList<TEntityId>.Create;
end;

function TEntityManager.CreateEntity: TEntity;
var
  Id: TEntityId;
begin
  Assert(Assigned(FWorld));

  { First check if there are any recycled entities that we can reuse }
  var Index := FEntitiesToRecycle.Count - 1;
  if (Index >= 0) then
  begin
    Id := FEntitiesToRecycle[Index];
    FEntitiesToRecycle.Delete(Index);
  end
  else
  begin
    { There are no recycled entities available. Generate a new one with a new
      Id. }
    Id := AtomicIncrement(FNextId);
  end;

  FEntities.Add(Id);

  Result.Initialize(Id, FWorld);
  FWorld.DoEntityAdded(Result);
end;

destructor TEntityManager.Destroy;
begin
  FEntitiesToDestroy.Free;
  FEntitiesToRecycle.Free;
  FEntities.Free;
  inherited;
end;

procedure TEntityManager.DestroyEntity(var AEntity: TEntity);
begin
  { Don't destroy the entity immediately. Instead, mark it for destruction (by
    adding it to a list of entities to destroy) so it will be destroyed during
    the next update cycle. }
  Assert(FEntities.Contains(AEntity.FId));
  Assert(not FEntitiesToDestroy.Contains(AEntity.FId));
  FEntitiesToDestroy.Add(AEntity.FId);
  AEntity.Initialize(0, nil);
end;

class function TEntityManager.GetSubscribedEvents: TEventTypes;
begin
  Result := [TEventType.AfterUpdate];
end;

{ TComponentManager }

procedure TComponentManager.AddComponent<T>(const AEntity: TEntity;
  const AComponent: T);
begin
  Assert(AEntity.IsValid);

  { Get a unique integer value that maps to the component type T }
  var TypeIndex := TComponentTypeIndex.Get<T>;
  Assert(Cardinal(TypeIndex) < MAX_TYPES, 'Too many component types.');

  { Get the list of all components of type T. The index in this list is the ID
    of the entity. Its value at this index is the component for that entity. }
  var Components := GetComponents<T>;

  Assert(AEntity.FId < Cardinal(FEntityComponentBits.Count));
  Assert(AEntity.FId < Cardinal(Components.Count));

  { Update the component for this entity }
  Components[AEntity.FId] := AComponent;

  { Retrieve a bitset containing all components that are supported by this
    entity }
  var OldBits := FEntityComponentBits[AEntity.FId];

  { Include this new component into the bitset }
  var NewBits := OldBits or (1 shl TypeIndex);
  Assert(OldBits <> NewBits, 'Component already added to entity');

  { Update the bitset for this entity }
  FEntityComponentBits[AEntity.FId] := NewBits;

  { Update the dictionary accordingly }
  FEntitiesByComponentBits.ComponentBitsChangedFor(AEntity, OldBits, NewBits);
end;

procedure TComponentManager.AfterUpdate;
begin
  if (FComponentsToDelete.Count > 0) then
  begin
    { Deletes any components that are marked for deletion and update the
      dictionary accordingly. }
    for var I := 0 to FComponentsToDelete.Count - 1 do
    begin
      var Info := FComponentsToDelete[I];
      FEntitiesByComponentBits.ComponentBitsChangedFor(Info.Entity, Info.OldBits, Info.NewBits);
    end;
    FComponentsToDelete.Clear;
  end;
end;

constructor TComponentManager.Create;
begin
  inherited;
  FEntityComponentBits := TList<TTypeBits>.Create;
  FComponentsByType := TObjectList<TObject>.Create;
  FEntitiesByComponentBits.Initialize;
  FComponentsToDelete := TList<TDeleteComponentInfo>.Create;
end;

destructor TComponentManager.Destroy;
begin
  FComponentsToDelete.Free;
  FEntitiesByComponentBits.Free;
  FComponentsByType.Free;
  FEntityComponentBits.Free;
  inherited;
end;

procedure TComponentManager.EntityAdded(const AEntity: TEntity);
begin
  { Add the entity to the list }
  if (Cardinal(FEntityComponentBits.Count) <= AEntity.FId) then
    FEntityComponentBits.Count := AEntity.FId + 1;

  { Clear any components associated with the entity }
  FEntityComponentBits[AEntity.FId] := 0;
end;

procedure TComponentManager.EntityRemoved(const AEntity: TEntity);
begin
  Assert(AEntity.FId < Cardinal(FEntityComponentBits.Count));

  { Update the dictionary }
  FEntitiesByComponentBits.ComponentBitsChangedFor(AEntity,
    FEntityComponentBits[AEntity.FId], 0);

  { Clear any components associated with the entity }
  FEntityComponentBits[AEntity.FId] := 0;
end;

function TComponentManager.GetComponent<T>(const AEntity: TEntity): T;
begin
  Assert(AEntity.IsValid);

  { Get a unique integer value that maps to the component type T }
  var TypeIndex := TComponentTypeIndex.Get<T>;

  { Check if the bitset for this entity includes this component.
    If not, return the default value of the component. }
  Assert(AEntity.FId < Cardinal(FEntityComponentBits.Count));
  if ((FEntityComponentBits[AEntity.FId] and (1 shl TypeIndex)) = 0) then
    Exit(Default(T));

  { Get the list of all components of type T. The index in this list is the ID
    of the entity. Its value at this index is the component for that entity. }
  var Components := GetComponents<T>;
  Assert(AEntity.FId < Cardinal(Components.Count));
  Result := Components[AEntity.FId];
end;

function TComponentManager.GetComponentRef<T>(const AEntity: TEntity): TRef<T>;
begin
  Assert(AEntity.IsValid);

  { Get a unique integer value that maps to the component type T }
  var TypeIndex := TComponentTypeIndex.Get<T>;

  { Check if the bitset for this entity includes this component.
    If not, return a nil reference. }
  Assert(AEntity.FId < Cardinal(FEntityComponentBits.Count));
  if ((FEntityComponentBits[AEntity.FId] and (1 shl TypeIndex)) = 0) then
  begin
    Result.FRef := nil;
    Exit;
  end;

  { Get the list of all components of type T. The index in this list is the ID
    of the entity. Its value at this index is the component for that entity. }
  var Components := GetComponents<T>;
  Assert(AEntity.FId < Cardinal(Components.Count));
  var List := Components.List;
  Result.FRef := @List[AEntity.FId];
end;

function TComponentManager.GetComponents<T>: TList<T>;
begin
  { Get a unique integer value that maps to the component type T }
  var TypeIndex := TComponentTypeIndex.Get<T>;

  { Make sure our component list has enough entries }
  if (FComponentsByType.Count <= TypeIndex) then
    FComponentsByType.Count := TypeIndex + 1;

  if (FComponentsByType[TypeIndex] = nil) then
  begin
    { We don't have a list for this component type yet. Create it. }
    Result := TList<T>.Create;
    FComponentsByType[TypeIndex] := Result;
  end
  else
  begin
    { We already have a list for this component type. }
    Assert(FComponentsByType[TypeIndex] is TList<T>);
    Result := TList<T>(FComponentsByType[TypeIndex]);
  end;

  { Make sure the returned list has enough entries }
  if (Result.Count < FEntityComponentBits.Count) then
    Result.Count := FEntityComponentBits.Count;
end;

class function TComponentManager.GetComponentTypes<T1, T2, T3, T4>: TTypeBits;
begin
  { Returns a bitset with 4 bits set corresponding to the 4 requested types }
  Result :=
    (1 shl TComponentTypeIndex.Get<T1>) or
    (1 shl TComponentTypeIndex.Get<T2>) or
    (1 shl TComponentTypeIndex.Get<T3>) or
    (1 shl TComponentTypeIndex.Get<T4>);
end;

class function TComponentManager.GetComponentTypes<T1, T2, T3>: TTypeBits;
begin
  { Returns a bitset with 3 bits set corresponding to the 3 requested types }
  Result :=
    (1 shl TComponentTypeIndex.Get<T1>) or
    (1 shl TComponentTypeIndex.Get<T2>) or
    (1 shl TComponentTypeIndex.Get<T3>);
end;

class function TComponentManager.GetComponentTypes<T1, T2>: TTypeBits;
begin
  { Returns a bitset with 2 bits set corresponding to the 2 requested types }
  Result :=
    (1 shl TComponentTypeIndex.Get<T1>) or
    (1 shl TComponentTypeIndex.Get<T2>);
end;

class function TComponentManager.GetComponentTypes<T>: TTypeBits;
begin
  { Returns a bitset with 1 bit set corresponding to the requested type }
  Result := (1 shl TComponentTypeIndex.Get<T>);
end;

function TComponentManager.GetEntitiesWith(
  const AComponentBits: TTypeBits): TList<TEntity>;
begin
  { Get the list of all entities that support the given combination of
    components. }
  Result := FEntitiesByComponentBits[AComponentBits];
  if (Result = nil) then
  begin
    { There is no such list yet. Create it and fill it with all current entities
      that support the given combination of components. }
    Result := TList<TEntity>.Create;
    FEntitiesByComponentBits[AComponentBits] := Result;

    var Entity: TEntity;
    Entity.Initialize(0, FWorld);
    for var I := 0 to FEntityComponentBits.Count - 1 do
    begin
      var EntityComponentBits := FEntityComponentBits[I];
      if ((EntityComponentBits and AComponentBits) = AComponentBits) then
      begin
        { This entity (ID) supports at least the given combination of
          components. Add it to the list. }
        Entity.FId := I;
        Result.Add(Entity);
      end;
    end;
  end;
end;

function TComponentManager.GetEntitiesWith<TComp1, TComp2, TComp3, TComp4>: TList<TEntity>;
begin
  Result := GetEntitiesWith(GetComponentTypes<TComp1, TComp2, TComp3, TComp4>);
end;

function TComponentManager.GetEntitiesWith<TComp1, TComp2, TComp3>: TList<TEntity>;
begin
  Result := GetEntitiesWith(GetComponentTypes<TComp1, TComp2, TComp3>);
end;

function TComponentManager.GetEntitiesWith<TComp1, TComp2>: TList<TEntity>;
begin
  Result := GetEntitiesWith(GetComponentTypes<TComp1, TComp2>);
end;

function TComponentManager.GetEntitiesWith<TComp>: TList<TEntity>;
begin
  Result := GetEntitiesWith(GetComponentTypes<TComp>);
end;

class function TComponentManager.GetSubscribedEvents: TEventTypes;
begin
  Result := [TEventType.EntityAdded, TEventType.EntityRemoved, TEventType.AfterUpdate];
end;

procedure TComponentManager.RemoveComponent<T>(const AEntity: TEntity);
begin
  Assert(AEntity.IsValid);
  var TypeIndex := TComponentTypeIndex.Get<T>;

  Assert(AEntity.FId < Cardinal(FEntityComponentBits.Count));
  var Info: TDeleteComponentInfo;
  Info.Entity := AEntity;
  Info.OldBits := FEntityComponentBits[AEntity.FId];
  Info.NewBits := Info.OldBits and not (1 shl TypeIndex);
  FEntityComponentBits[AEntity.FId] := Info.NewBits;
  FComponentsToDelete.Add(Info);
end;

{ TComponentManager.TEntitiesByComponentBits }

procedure TComponentManager.TEntitiesByComponentBits.ComponentBitsChangedFor(
  const AEntity: TEntity; const AOldBits, ANewBits: TTypeBits);
begin
  { The bitset (of supported components) for the given entity have changed (from
    AOldBits to ANewBits). Since this dictionary is indexed by bitset, we need
    to remove the old bitset and add the new one. }
  var Item := FItems;
  for var I := 0 to FCapacity - 1 do
  begin
    if (Item.HashCode <> EMPTY_HASH) then
    begin
      Assert(Item.Entities <> nil);
      var Bits := Item.Bits;

      var Exists := ((Bits and AOldBits) = Bits);
      var ShouldExist := ((Bits and ANewBits) = Bits);
      if (Exists <> ShouldExist) then
      begin
        if (ShouldExist) then
          Item.Entities.Add(AEntity)
        else
          Item.Entities.Remove(AEntity);
      end;
    end;
    Inc(Item);
  end;
end;

procedure TComponentManager.TEntitiesByComponentBits.Free;
begin
  var Item := FItems;
  for var I := 0 to FCapacity - 1 do
  begin
    if (Item.HashCode <> EMPTY_HASH) then
      Item.Entities.Free;

    Inc(Item);
  end;
  FreeMem(FItems);
  Initialize;
end;

function TComponentManager.TEntitiesByComponentBits.GetEntities(
  const AComponentBits: TTypeBits): TList<TEntity>;
begin
  { A boilerplate dictionary implementation to retrieve the list of entities
    that supports the given combination of components. }
  if (FCount = 0) then
    Exit(nil);

  var Mask := FCapacity - 1;
  var HashCode := Hash(AComponentBits);
  var Index := HashCode and Mask;

  while True do
  begin
    var HC := FItems[Index].HashCode;
    if (HC = EMPTY_HASH) then
      Exit(nil);

    if (HC = HashCode) and (FItems[Index].Bits = AComponentBits) then
      Exit(FItems[Index].Entities);

    Index := (Index + 1) and Mask;
  end;
end;

class function TComponentManager.TEntitiesByComponentBits.Hash(
  const ABits: TTypeBits): Integer;
{ Peforms the Murmur Hash 2 algorithm to calculate a hash code for the given
  bitset. }
const
  M = $5bd1e995;
  R = 24;
var
  H, K: Cardinal;
begin
  H := SizeOf(TTypeBits);
  K := Cardinal(ABits) * M;
  K := K xor (K shr R);
  K := K * M;

  H := H * M;
  H := H xor K;

  K := (ABits shr 32) * M;
  K := K xor (K shr R);
  K := K * M;

  H := H * M;
  H := H xor K;

  H := H xor (H shr 13);
  H := H * M;
  Result := (H xor (H shr 15)) and $7FFFFFFF;
end;

procedure TComponentManager.TEntitiesByComponentBits.Initialize;
begin
  FItems := nil;
  FCount := 0;
  FCapacity := 0;
  FGrowThreshold := 0;
end;

procedure TComponentManager.TEntitiesByComponentBits.Resize(
  ANewCapacity: Integer);
begin
  { A boilerplate implementation to resize the dictionary. }
  if (ANewCapacity < 4) then
    ANewCapacity := 4;
  var NewMask := ANewCapacity - 1;
  var OldItems := FItems;
  try
    GetMem(FItems, ANewCapacity * SizeOf(TItem));
    FillChar(FItems^, ANewCapacity * SizeOf(TItem), 0);
    var NewItems := FItems;

    for var I := 0 to ANewCapacity - 1 do
      NewItems[I].HashCode := EMPTY_HASH;

    for var I := 0 to FCapacity - 1 do
    begin
      if (OldItems[I].HashCode <> EMPTY_HASH) then
      begin
        var NewIndex := OldItems[I].HashCode and NewMask;
        while (NewItems[NewIndex].HashCode <> EMPTY_HASH) do
          NewIndex := (NewIndex + 1) and NewMask;
        NewItems[NewIndex] := OldItems[I];
      end;
    end;
  finally
    FreeMem(OldItems);
  end;

  FCapacity := ANewCapacity;
  FGrowThreshold := (ANewCapacity * 3) shr 2; // 75%
end;

procedure TComponentManager.TEntitiesByComponentBits.SetEntities(
  const AComponentBits: TTypeBits; const AValue: TList<TEntity>);
begin
  { A boilerplate dictionary implementation to set the list of entities that
    supports the given combination of components. }
  if (FCount >= FGrowThreshold) then
    Resize(FCapacity * 2);

  var HashCode := Hash(AComponentBits);
  var Mask := FCapacity - 1;
  var Index := HashCode and Mask;

  while True do
  begin
    var HC := FItems[Index].HashCode;
    if (HC = EMPTY_HASH) then
      Break;

    if (HC = HashCode) and (FItems[Index].Bits = AComponentBits) then
    begin
      Assert(False, 'Duplicate entry');
      Exit;
    end;

    Index := (Index + 1) and Mask;
  end;

  Assert(FItems[Index].Entities = nil);
  FItems[Index].HashCode := HashCode;
  FItems[Index].Bits := AComponentBits;
  FItems[Index].Entities := AValue;
  Inc(FCount);
end;

{ TWorld }

procedure TWorld.AddEventListener(const AListener: TEventListener);
begin
  { Get the event types that the listener is interested in }
  var EventTypes := AListener.GetSubscribedEvents;

  { For each event type that the listener is interested in, add it to the
    corresponding list of listeners. }
  for var ET := Low(TEventType) to High(TEventType) do
  begin
    if (ET in EventTypes) then
      FEventListeners[ET].Add(AListener);
  end;
end;

function TWorld.AddManager<T>: T;
begin
  { Get a unique integer value that maps to the manager type T }
  var Index := TManager.TTypeIndex.Get<T>;
  Assert(Cardinal(Index) < MAX_TYPES, 'Too many manager types.');

  { Check if a manager of this type already exists.
    If so, return it. }
  if (FManagers[Index] <> nil) then
  begin
    { Manager type already registered. }
    Assert(FManagers[Index] is T);
    Exit(T(FManagers[Index]));
  end;

  { No manager of this type currently exists. Create and add it. }
  Result := T.Create;
  Result.FWorld := Self;
  Result.Initialize;
  FManagers[Index] := Result;

  { Setup the event listeners for this new manager }
  AddEventListener(Result);
end;

function TWorld.AddSystem<T>: T;
begin
  { Get a unique integer value that maps to the system type T }
  var Index := TSystem.TTypeIndex.Get<T>;
  Assert(Cardinal(Index) < MAX_TYPES, 'Too many system types.');

  { Check if a system of this type already exists.
    If so, return it. }
  if (FSystems[Index] <> nil) then
  begin
    { System type already registered. }
    Assert(FSystems[Index] is T);
    Exit(T(FSystems[Index]));
  end;

  { No system of this type currently exists. Create and add it. }
  Result := T.Create;
  Result.FWorld := Self;
  Result.Initialize;
  FSystems[Index] := Result;

  { Setup the event listeners for this new system }
  AddEventListener(Result);
end;

constructor TWorld.Create;
begin
  inherited;
  for var ET := Low(TEventType) to High(TEventType) do
    FEventListeners[ET] := TList<TEventListener>.Create;

  FEntityManager := AddManager<TEntityManager>();
  FEntityManager.FWorld := Self;
  FComponentManager := AddManager<TComponentManager>();
end;

function TWorld.CreateEntity: TEntity;
begin
  Result := FEntityManager.CreateEntity;
end;

destructor TWorld.Destroy;
begin
  for var ET := Low(TEventType) to High(TEventType) do
    FEventListeners[ET].Free;

  for var I := 0 to MAX_TYPES - 1 do
  begin
    FManagers[I].Free;
    FSystems[I].Free;
  end;
  inherited;
end;

procedure TWorld.DestroyEntity(var AEntity: TEntity);
begin
  FEntityManager.DestroyEntity(AEntity);
end;

procedure TWorld.DoAfterUpdate;
begin
  { Call AfterUpdate for all listeners that are interested in this event. }
  var Listeners := FEventListeners[TEventType.AfterUpdate];
  for var I := 0 to Listeners.Count - 1 do
    Listeners[I].AfterUpdate;
end;

procedure TWorld.DoBeforeUpdate;
begin
  { Call BeforeUpdate for all listeners that are interested in this event. }
  var Listeners := FEventListeners[TEventType.BeforeUpdate];
  for var I := 0 to Listeners.Count - 1 do
    Listeners[I].BeforeUpdate;
end;

procedure TWorld.DoEntityAdded(const AEntity: TEntity);
begin
  { Call EntityAdded for all listeners that are interested in this event. }
  var Listeners := FEventListeners[TEventType.EntityAdded];
  for var I := 0 to Listeners.Count - 1 do
    Listeners[I].EntityAdded(AEntity);
end;

procedure TWorld.DoEntityRemoved(const AEntity: TEntity);
begin
  { Call EntityRemoved for all listeners that are interested in this event. }
  var Listeners := FEventListeners[TEventType.EntityRemoved];
  for var I := 0 to Listeners.Count - 1 do
    Listeners[I].EntityRemoved(AEntity);
end;

procedure TWorld.DoUpdate(const ADeltaTime: Single);
begin
  { Call Update for all listeners that are interested in this event. }
  var Listeners := FEventListeners[TEventType.Update];
  for var I := 0 to Listeners.Count - 1 do
    Listeners[I].Update(ADeltaTime);
end;

function TWorld.GetEntitiesWith<TComp1, TComp2, TComp3, TComp4>: TList<TEntity>;
begin
  Result := FComponentManager.GetEntitiesWith(
    TComponentManager.GetComponentTypes<TComp1, TComp2, TComp3, TComp4>);
end;

function TWorld.GetEntitiesWith<TComp1, TComp2, TComp3>: TList<TEntity>;
begin
  Result := FComponentManager.GetEntitiesWith(
    TComponentManager.GetComponentTypes<TComp1, TComp2, TComp3>);
end;

function TWorld.GetEntitiesWith<TComp1, TComp2>: TList<TEntity>;
begin
  Result := FComponentManager.GetEntitiesWith(
    TComponentManager.GetComponentTypes<TComp1, TComp2>);
end;

function TWorld.GetEntitiesWith<TComp>: TList<TEntity>;
begin
  Result := FComponentManager.GetEntitiesWith(
    TComponentManager.GetComponentTypes<TComp>);
end;

function TWorld.GetManager<T>: T;
begin
  { Get a unique integer value that maps to the manager type T }
  var Index := TManager.TTypeIndex.Get<T>;
  Assert(Index < MAX_TYPES);
  Assert(FManagers[Index] is T);

  { Return the manager for this type (if it exists) }
  Result := T(FManagers[Index]);
end;

function TWorld.GetSystem<T>: T;
begin
  { Get a unique integer value that maps to the system type T }
  var Index := TSystem.TTypeIndex.Get<T>;
  Assert(Index < MAX_TYPES);
  Assert(FSystems[Index] is T);

  { Return the system for this type (if it exists) }
  Result := T(FSystems[Index]);
end;

procedure TWorld.Update(const ADeltaTime: Single);
begin
  DoBeforeUpdate;
  DoUpdate(ADeltaTime);
  DoAfterUpdate;
end;

end.
