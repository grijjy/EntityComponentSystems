unit FMain;

{ Enable this define to use a lot of cubes of smaller sizes }
{.$DEFINE MANY_CUBES}

interface

uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Classes,
  System.Variants,
  System.Math.Vectors,
  System.Diagnostics,
  FMX.Types,
  FMX.Controls,
  FMX.Forms3D,
  FMX.Types3D,
  FMX.Forms,
  FMX.Graphics,
  FMX.Dialogs,
  FMX.Controls3D,
  FMX.MaterialSources,
  FMX.Objects3D,
  SimpleECS;

const
  { Number of colors (materials) for the cubes }
  CUBE_COLOR_COUNT = 8;

{$IFDEF MANY_CUBES}
const
  { Number of cubes in the world }
  CUBE_COUNT = 400;

  { Maximum size of a cube }
  MAX_CUBE_SIZE = 0.01;

  { Maximum velocity of a cube }
  MAX_CUBE_VELOCITY = 0.4;
{$ELSE}
const
  { Number of cubes in the world }
  CUBE_COUNT = 30;

  { Maximum size of a cube }
  MAX_CUBE_SIZE = 0.1;

  { Maximum velocity of a cube }
  MAX_CUBE_VELOCITY = 1;
{$ENDIF}


type
  TFormMain = class(TForm3D)
    CubeContainer: TCube;
    ContainerMaterial: TLightMaterialSource;
    Light: TLight;
    Camera: TCamera;
    TimerUpdate: TTimer;
    procedure Form3DCreate(Sender: TObject);
    procedure Form3DDestroy(Sender: TObject);
    procedure TimerUpdateTimer(Sender: TObject);
  private
    { The ECS world }
    FWorld: TWorld;

    { The materials (sources) uses by the cubes }
    FMaterialSources: TArray<TLightMaterialSource>;

    { A stopwatch used to measure the number of seconds between screen updates }
    FStopwatch: TStopwatch;
  end;

var
  FormMain: TFormMain;

implementation

{$R *.fmx}

uses
  Components,
  Systems;

const
  { Predefined colors for the cubes }
  CUBE_COLORS: array [0..CUBE_COLOR_COUNT - 1] of TAlphaColor = (
    TAlphaColors.Cornflowerblue,
    TAlphaColors.Coral,
    TAlphaColors.Goldenrod,
    TAlphaColors.Mediumseagreen,
    TAlphaColors.Yellowgreen,
    TAlphaColors.Sienna,
    TAlphaColors.Indianred,
    TAlphaColors.Lightslategray);

{ Some helper functions to return random coordinates, velocities and rotation
  angles }

function RandomCoord: Single;
begin
  { The big container cube has dimensions of 1 x 1 x 1.
    The smaller cubes must fit in this container cube, so its XYZ positions
    should be between -0.5 and 0.5. To account for the size of the cubes, we
    limit the range to -0.4 to 0.4. }
  Result := (Random - 0.5) * 0.8;
end;

function RandomVel: Single;
begin
  { Returns a random velocity for a cube. This is the XYZ distance a cube will
    travel in on second. }
  Result := (Random - 0.5) * MAX_CUBE_VELOCITY;
end;

function RandomAngle: Single;
begin
  { Returns a random XYZ rotation angle for a cube from 0 to 360 degrees. }
  Result := Random * 360;
end;

function RandomAngVel: Single;
begin
  { Returns a random angular XYZ velocity for a cube. This is the number of
    degrees that a cube rotates in one second. }
  Result := Random * 50;
end;

procedure TFormMain.Form3DCreate(Sender: TObject);
var
  Cubes: TArray<TCube>;
begin
  ReportMemoryLeaksOnShutdown := True;

  { Create some light material sources for our predefined cube colors. }
  SetLength(FMaterialSources, CUBE_COLOR_COUNT);
  for var I := 0 to CUBE_COLOR_COUNT - 1 do
  begin
    var Mat := TLightMaterialSource.Create(Self);
    Mat.Ambient := CUBE_COLORS[I];
    Mat.Diffuse := CUBE_COLORS[I];
    FMaterialSources[I] := Mat;
  end;

  { Create an ECS world, and add our 4 systems (movment, rotation, collision
    and rendering) to it. }
  FWorld := TWorld.Create;
  FWorld.AddSystem<TMovementSystem>();
  FWorld.AddSystem<TRotationSystem>();
  FWorld.AddSystem<TCollisionSystem>();
  var RenderingSystem := FWorld.AddSystem<TRenderingSystem>();

  { Add a bunch of entities to the world, were each entity is represented by
    one cube. Note that it is perfectly legal (and very common) to add and
    delete entities while the app is running. We keep things simple however, and
    add a predefined number of entities. }
  Randomize;
  SetLength(Cubes, CUBE_COUNT);
  for var I := 0 to CUBE_COUNT - 1 do
  begin
    { Create a new entity }
    var E := FWorld.CreateEntity;

    { Add random Position and Velocity components.
      Note that we don't need to specify the generic type here, since the
      Delphi compiler can infer this from the Make* calls. }
    FWorld.AddComponent(E, MakePosition(RandomCoord, RandomCoord, RandomCoord));
    FWorld.AddComponent(E, MakeVelocity(RandomVel, RandomVel, RandomVel));

    { Add random Rotation and AngularVelocity components }
    FWorld.AddComponent(E, MakeRotation(RandomAngle, RandomAngle, RandomAngle));
    FWorld.AddComponent(E, MakeAngularVelocity(RandomAngVel, RandomAngVel, RandomAngVel));

    { Add random Dimensions and MaterialIndex components.
      Note that we need to specify the generic type here (TDimensions and
      TMaterialIndex), otherwise Delphi's type inference will interpret these
      as Double or Integer types, which is incorrect. }
    FWorld.AddComponent<TDimensions>(E, (Random * MAX_CUBE_SIZE) + 0.02);
    FWorld.AddComponent<TMaterialIndex>(E, Random(CUBE_COLOR_COUNT));

    { NOTE: In this example, each entity has the same components. However, this
      does not have to be the case (and usually isn't). One of the powers of an
      ECS is that you can mix and match components, without having to create
      complex inheritance hierachies. }

    { Create a cube that matches the entity }
    var Cube := TCube.Create(Self);
    Cube.HitTest := False; // Optimization
    AddObject(Cube);
    Cubes[I] := Cube;
  end;

  { Pass the cubes and materials to the rendering system. }
  RenderingSystem.Setup(Cubes, FMaterialSources);

  { Start the update timer }
  FStopwatch := TStopwatch.StartNew;
  TimerUpdate.Enabled := True;
end;

procedure TFormMain.Form3DDestroy(Sender: TObject);
begin
  FWorld.Free;
end;

procedure TFormMain.TimerUpdateTimer(Sender: TObject);
begin
  { Update the world about 50 times per second }
  var DeltaTime: Single := FStopwatch.Elapsed.TotalSeconds;
  FStopwatch.Reset;
  FStopwatch.Start;

  BeginUpdate;
  try
    { Update the world. This will automatically update all systems, so we don't
      need to perform any logic here. For performance reasons on the FireMonkey
      platform, it is best to wrap this inside a BeginUpdate/EndUpdate pair. }
    FWorld.Update(DeltaTime);
  finally
    EndUpdate;
  end;
end;

end.
