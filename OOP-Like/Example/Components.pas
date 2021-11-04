unit Components;
{ Some sample Components for use with out ECS example.
  Each component type is just a distinct type alias of standard type. }

interface

uses
  System.Math.Vectors;

type
  { The index of a material in the FMaterialSources array (of the main form) }
  TMaterialIndex = type Integer;

  { The 3D position of a cube }
  TPosition = type TPoint3D;

  { The 3D rotation angle of a cube }
  TRotation = type TPoint3D;

  { The 3D velocity vector of a cube (by which TPosition is updated) }
  TVelocity = type TPoint3D;

  { The 3D angular velocity vector of a cube (by which TRotation is updated) }
  TAngularVelocity = type TPoint3D;

  { The dimensions (size) of a cube }
  TDimensions = type Single;

{ Some helper function to initialize these components }
function MakePosition(const AX, AY, AZ: Single): TPosition;
function MakeRotation(const AX, AY, AZ: Single): TRotation;
function MakeVelocity(const AX, AY, AZ: Single): TVelocity;
function MakeAngularVelocity(const AX, AY, AZ: Single): TAngularVelocity;

implementation

function MakePosition(const AX, AY, AZ: Single): TPosition;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Z := AZ;
end;

function MakeRotation(const AX, AY, AZ: Single): TRotation;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Z := AZ;
end;

function MakeVelocity(const AX, AY, AZ: Single): TVelocity;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Z := AZ;
end;

function MakeAngularVelocity(const AX, AY, AZ: Single): TAngularVelocity;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Z := AZ;
end;

end.
