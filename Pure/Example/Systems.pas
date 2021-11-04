unit Systems;
{ Some sample Systems for use with out ECS example. }

interface

uses
  System.Generics.Collections,
  FMX.Objects3D,
  FMX.MaterialSources,
  SimpleECS;

type
  { Takes care of moving the cubes in the scene.

    Uses the TPosition and TVelocity components of each entity to update its
    position. }
  TMovementSystem = class(TSystem)
  private
    FEntities: TList<TEntity>;
  protected
    procedure Initialize; override;
    procedure Update(const ADeltaTime: Single); override;
  end;

type
  { Takes care of rotating the cubes in the scene.

    Uses the TRotation and TAngularVelocity components of each entity to update
    its rotation. }
  TRotationSystem = class(TSystem)
  private
    FEntities: TList<TEntity>;
  protected
    procedure Initialize; override;
    procedure Update(const ADeltaTime: Single); override;
  end;

type
  { Handles collisions beteen each cube and the 6 walls of the larger container
    cube. When a cube collides with one of the walls, its velocity in that
    direction is inverted.

    To keep things simple, this does *not* handle collisions between the cubes
    themselves.

    Uses the TPosition, TVelocity and TDimensions components of each entity to
    check for collisions. }
  TCollisionSystem = class(TSystem)
  private
    FEntities: TList<TEntity>;
  protected
    procedure Initialize; override;
    procedure Update(const ADeltaTime: Single); override;
  end;

type
  { Takes care of rendering the cubes to the screen.
    This doesn't perform any actual rendering, but instead updates the
    properties of each FireMonkey cube that corresponds with an entity.
    Then FireMonkey will take care of the rendering for us.

    Uses all but the velocity components of each entity to update the
    corresponding cube. }
  TRenderingSystem = class(TSystem)
  private
    FEntities: TList<TEntity>;
    FCubes: TArray<TCube>;
    FMaterialSources: TArray<TLightMaterialSource>;
  protected
    procedure Initialize; override;
    procedure Update(const ADeltaTime: Single); override;
  public
    procedure Setup(const ACubes: TArray<TCube>;
      const AMaterialSources: TArray<TLightMaterialSource>);
  end;

implementation

uses
  System.Math.Vectors,
  Components;

{ TMovementSystem }

procedure TMovementSystem.Initialize;
begin
  inherited;
  { To update the position of cubes, we only need those entities that have both
    a TPosition and TVelocity component. }
  FEntities := World.GetEntitiesWith<TPosition, TVelocity>;
end;

procedure TMovementSystem.Update(const ADeltaTime: Single);
begin
  { Walk through all the entities in the list. }
  for var Entity in FEntities do
  begin
    { We are going to update to position, so we need to get a reference to it }
    var PositionRef := World.GetComponentRef<TPosition>(Entity);
    Assert(not PositionRef.IsNil);

    { We don't need to update the velocity, so we can just get its value
      (instead of a reference) }
    var Velocity := World.GetComponent<TVelocity>(Entity);

    { Get the position from the reference, update it using the velocity and
      time passed, and then update the reference with the new position. }
    var Position := PositionRef.Ref;
    Position.X := Position.X + (ADeltaTime * Velocity.X);
    Position.Y := Position.Y + (ADeltaTime * Velocity.Y);
    Position.Z := Position.Z + (ADeltaTime * Velocity.Z);
    PositionRef.Ref := Position;
  end;
end;

{ TRotationSystem }

procedure TRotationSystem.Initialize;
begin
  inherited;
  { To update the rotation of cubes, we only need those entities that have both
    a TRotation and TAngularVelocity component. }
  FEntities := World.GetEntitiesWith<TRotation, TAngularVelocity>;
end;

procedure TRotationSystem.Update(const ADeltaTime: Single);
begin
  { Walk through all the entities in the list. }
  for var Entity in FEntities do
  begin
    { We are going to update to rotation, so we need to get a reference to it }
    var RotationRef := World.GetComponentRef<TRotation>(Entity);
    Assert(not RotationRef.IsNil);

    { We don't need to update the angular velocity, so we can just get its value
      (instead of a reference) }
    var AngVel := World.GetComponent<TAngularVelocity>(Entity);

    { Get the rotation from the reference, update it using the angular velocity
      and time passed, and then update the reference with the new rotation. }
    var Rotation := RotationRef.Ref;
    Rotation.X := Rotation.X + (ADeltaTime * AngVel.X);
    Rotation.Y := Rotation.Y + (ADeltaTime * AngVel.Y);
    Rotation.Z := Rotation.Z + (ADeltaTime * AngVel.Z);
    RotationRef.Ref := Rotation;
  end;
end;

{ TCollisionSystem }

procedure TCollisionSystem.Initialize;
begin
  inherited;
  { To check for collisions, we need those entities that have a TPosition,
    TDimensions and TVelocity component. }
  FEntities := World.GetEntitiesWith<TPosition, TDimensions, TVelocity>;
end;

procedure TCollisionSystem.Update(const ADeltaTime: Single);
begin
  { Walk through all the entities in the list. }
  for var Entity in FEntities do
  begin
    { We may update the position and velocity of the entity, so we need to get
      references to these }
    var PosRef := World.GetComponentRef<TPosition>(Entity);
    Assert(not PosRef.IsNil);

    var VelRef := World.GetComponentRef<TVelocity>(Entity);
    Assert(not VelRef.IsNil);

    { We don't need to update the dimensions, so we can just get its value
      (instead of a reference) }
    var Dim := World.GetComponent<TDimensions>(Entity);

    { Get the position and velocity from its references.
      As a small optimization, we also use a Modified flag that will be True
      only if we change the position and velocity. That we, we don't need to
      update the references if nothing has changed. }
    var Pos := PosRef.Ref;
    var Vel := VelRef.Ref;
    var Modified := False;

    { The big container cube has dimensions of 1 x 1 x 1 and is located at the
      origin of the world (0, 0, 0). This means its "walls" are positioned at
      coordinates -0.5 and 0.5 in the X, Y and Z dimensions. }

    { Check for collisions with the Left and Right walls. }
    if ((Pos.X - Dim) < -0.5) then
    begin
      { Collision with the left wall: Clamp the position to the left wall and
        invert the velocity in the X direction. }
      Pos.X := -0.5 + Dim;
      Vel.X := -Vel.X;
      Modified := True;
    end
    else if ((Pos.X + Dim) > 0.5) then
    begin
      { Collision with the right wall: Clamp the position to the right wall and
        invert the velocity in the X direction. }
      Pos.X := 0.5 - Dim;
      Vel.X := -Vel.X;
      Modified := True;
    end;

    { Check for collisions with the Top and Bottom walls. }
    if ((Pos.Y - Dim) < -0.5) then
    begin
      Pos.Y := -0.5 + Dim;
      Vel.Y := -Vel.Y;
      Modified := True;
    end
    else if ((Pos.Y + Dim) > 0.5) then
    begin
      Pos.Y := 0.5 - Dim;
      Vel.Y := -Vel.Y;
      Modified := True;
    end;

    { Check for collisions with the Near and Far walls.
      NOTE: The Near wall is close to the camera, so we use a smaller range
      (-0.4 instead of -0.5) to make sure the cube doesn't get too close to the
      camera (which can result in visual artifacts) }
    if ((Pos.Z - Dim) < -0.4) then
    begin
      Pos.Z := -0.4 + Dim;
      Vel.Z := -Vel.Z;
      Modified := True;
    end
    else if ((Pos.Z + Dim) > 0.5) then
    begin
      Pos.Z := 0.5 - Dim;
      Vel.Z := -Vel.Z;
      Modified := True;
    end;

    { Update the references if the position and velocities have changed. }
    if (Modified) then
    begin
      PosRef.Ref := Pos;
      VelRef.Ref := Vel;
    end;
  end;
end;

{ TRenderingSystem }

procedure TRenderingSystem.Initialize;
begin
  inherited;
  { We need all components (except for velocity components) to update the
    FireMonkey cube that matches each entity. }
  FEntities := World.GetEntitiesWith<TPosition, TRotation, TDimensions, TMaterialIndex>;
end;

procedure TRenderingSystem.Setup(const ACubes: TArray<TCube>;
  const AMaterialSources: TArray<TLightMaterialSource>);
begin
  FCubes := ACubes;
  FMaterialSources := AMaterialSources;
end;

procedure TRenderingSystem.Update(const ADeltaTime: Single);
begin
  { Walk through all the entities in the list. }
  for var I := 0 to FEntities.Count - 1 do
  begin
    var Entity := FEntities[I];

    { Get the cube that corresponds to this entity }
    Assert(I < Length(FCubes));
    var Cube := FCubes[I];

    { Get the entity components we need to update the cube }
    var Pos := World.GetComponent<TPosition>(Entity);
    var Rot := World.GetComponent<TRotation>(Entity);
    var Dim := World.GetComponent<TDimensions>(Entity);
    var Mat := World.GetComponent<TMaterialIndex>(Entity);
    Assert(Mat < Length(FMaterialSources));

    { Update the properties of the cube to correspond with the components of
      the entity. }
    Cube.BeginUpdate;
    try
      Cube.Position.Point := TPoint3D(Pos);
      Cube.RotationAngle.Point := TPoint3D(Rot);
      Cube.SetSize(Dim, Dim, Dim);
      Cube.MaterialSource := FMaterialSources[Mat];
    finally
      Cube.EndUpdate;
    end;
  end;
end;

end.
