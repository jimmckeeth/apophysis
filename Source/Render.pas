{
     Flame screensaver Copyright (C) 2002 Ronald Hordijk
     Apophysis Copyright (C) 2001-2004 Mark Townsend
     Apophysis Copyright (C) 2005-2006 Ronald Hordijk, Piotr Borys, Peter Sdobnov

     This program is free software; you can redistribute it and/or modify
     it under the terms of the GNU General Public License as published by
     the Free Software Foundation; either version 2 of the License, or
     (at your option) any later version.

     This program is distributed in the hope that it will be useful,
     but WITHOUT ANY WARRANTY; without even the implied warranty of
     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
     GNU General Public License for more details.

     You should have received a copy of the GNU General Public License
     along with this program; if not, write to the Free Software
     Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
}
unit Render;

interface

uses
  Windows, Graphics, Classes,
  Controlpoint, RenderTypes, ImageMaker;

///////////////////////////////////////////////////////////////////////////////
//
//  { TBaseRenderer }
//
///////////////////////////////////////////////////////////////////////////////

type
  TBaseRenderer = class
  private
    FOnProgress: TOnProgress;

  protected
    camX0, camX1, camY0, camY1, // camera bounds
    camW, camH,                 // camera sizes
    bws, bhs, cosa, sina, rcX, rcY: double;
    ppux, ppuy: extended;

    BucketWidth, BucketHeight: int64;
    BucketSize: int64;

    sample_density: extended;
    oversample: integer;
    gutter_width: Integer;
    max_gutter_width: Integer;

    FCP: TControlPoint;
    FStop: integer;//boolean;

    FImageMaker: TImageMaker;
    strOutput: TStrings;

    ColorMap: TColorMapArray;

    FMaxMem: integer;
    FSlice, FNumSlices: integer;
    image_Width, image_Height: Int64;
    image_Center_X, image_Center_Y: double;

    FCompatibility: integer;
    FNumThreads: integer;
    FNumBatches: integer;//int64;

    FMinDensity: double;
    FMinBatches: integer;
    FRenderOver: boolean;

    RenderTime: TDateTime;

    procedure Progress(value: double);

    procedure SetNumThreads(const n: integer);
    procedure SetMinDensity(const q: double);

    procedure CreateColorMap; virtual;
    procedure CreateCamera;
    procedure CreateCameraMM;
    procedure Prepare; virtual; abstract;
    procedure SetPixels; virtual; abstract;

    procedure CalcBufferSize; virtual;
    procedure CalcBufferSizeMM;

    function GetBits: integer; virtual; abstract;
    function GetBucketsPtr: pointer; virtual; abstract;
    procedure InitBuffers;
    procedure AllocateBuckets; virtual; abstract;
    procedure ClearBuckets; virtual; abstract;
    procedure RenderMM;

  public
    constructor Create; virtual;
    destructor Destroy; override;

    procedure SetCP(CP: TControlPoint);
    procedure Render; virtual;

    function  GetImage: TBitmap; virtual;
    procedure UpdateImage(CP: TControlPoint);
    procedure SaveImage(const FileName: String);

    procedure Stop; virtual;
    procedure Break; virtual;
    procedure Pause; virtual; abstract;
    procedure UnPause; virtual; abstract;

    procedure GetBucketStats(var Stats: TBucketStats);

    property OnProgress: TOnProgress
        read FOnProgress
       write FOnProgress;
    property MaxMem : integer
        read FMaxMem
       write FMaxMem;
    property NrSlices: integer
        read FNumSlices;
    property Slice: integer
        read FSlice;
    property NumThreads: integer
        read FNumThreads
       write SetNumThreads;
    property Output: TStrings
       write strOutput;
    property MinDensity: double
       write SetMinDensity;
    property RenderMore: boolean
       write FRenderOver;
  end;


///////////////////////////////////////////////////////////////////////////////

  { TRenderer }

///////////////////////////////////////////////////////////////////////////////

type
  TRenderer = class
  private
    FRenderer: TBaseRenderer;

    FOnProgress: TOnProgress;
    FCP: TControlPoint;
    FMaxMem: int64;


  public
    destructor Destroy; override;

    procedure SetCP(CP: TControlPoint);
    procedure Render;

    function GetBucketSize: integer; virtual; abstract;

    function GetImage: TBitmap;
    procedure Stop;

    property OnProgress: TOnProgress
      read FOnProgress
      write FOnProgress;
  end;

implementation

uses
  Math, SysUtils, Forms,
  Render32;

///////////////////////////////////////////////////////////////////////////////
//
//  { TBaseRenderer }
//
///////////////////////////////////////////////////////////////////////////////

constructor TBaseRenderer.Create;
begin
  inherited Create;

  FNumSlices := 1;
  FSlice := 0;
  FStop := 0; // False;

  FImageMaker := TImageMaker.Create;
end;

///////////////////////////////////////////////////////////////////////////////
destructor TBaseRenderer.Destroy;
begin
  FImageMaker.Free;

  if assigned(FCP) then
    FCP.Free;

  inherited;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.SetCP(CP: TControlPoint);
begin
  if assigned(FCP) then
    FCP.Free;

  FCP := Cp.Clone;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.Stop;
begin
  FStop := 1; //True;
end;

procedure TBaseRenderer.Break;
begin
  FStop := -1;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.Progress(value: double);
begin
  if assigned(FOnprogress) then
    FOnprogress(Value);
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.SetNumThreads(const n: integer);
begin
  FNumThreads := n;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.SetMinDensity(const q: double);
begin
  if q < fcp.sample_density then FMinDensity := q
  else FMinDensity := fcp.sample_density;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.GetBucketStats(var Stats: TBucketStats);
begin
  FImageMaker.GetBucketStats(Stats);
  Stats.TotalSamples := int64(FNumBatches) * SUB_BATCH_SIZE; // * fcp.nbatches ?
  Stats.RenderTime := RenderTime;
end;

///////////////////////////////////////////////////////////////////////////////
function TBaseRenderer.GetImage: TBitmap;
begin
  if FStop <> 0 then begin
    FImageMaker.OnProgress := OnProgress;
    FImageMaker.CreateImage;
  end;
  Result := FImageMaker.GetImage;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.UpdateImage(CP: TControlPoint);
begin
  FCP.background := cp.background;
  FCP.spatial_filter_radius := cp.spatial_filter_radius;
  FCP.gamma := cp.Gamma;
  FCP.vibrancy := cp.vibrancy;
  FCP.contrast := cp.contrast;
  FCP.brightness := cp.brightness;

  FImageMaker.SetCP(FCP);
  FImageMaker.Init;

  FImageMaker.OnProgress := OnProgress;
  FImageMaker.CreateImage;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.SaveImage(const FileName: String);
begin
  if FStop <> 0 then begin
    if Assigned(strOutput) then
      strOutput.Add(TimeToStr(Now) + Format(' : Creating image with quality = %f', [fcp.actual_density]));
    FImageMaker.OnProgress := OnProgress;
    FImageMaker.CreateImage;
  end;
  if Assigned(strOutput) then
    strOutput.Add(TimeToStr(Now) + ' : Saving image');
  FImageMaker.SaveImage(FileName);
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.CreateColorMap;
var
  i: integer;
begin
  for i := 0 to 255 do
    with ColorMap[i] do begin
      Red   := (fcp.CMap[i][0] * fcp.white_level) div 256;
      Green := (fcp.CMap[i][1] * fcp.white_level) div 256;
      Blue  := (fcp.CMap[i][2] * fcp.white_level) div 256;
    end;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.CreateCamera;
var
  scale: double;
  t0, t1: double;
  t2, t3: double;
  corner_x, corner_y, Xsize, Ysize: double;
  shift: Integer;
begin
  scale := power(2, fcp.zoom);
  sample_density := fcp.sample_density * scale * scale;
  ppux := fcp.pixels_per_unit * scale;
  ppuy := fcp.pixels_per_unit * scale;
  // todo field stuff
  shift := 0;

  corner_x := fcp.center[0] - fcp.Width / ppux / 2.0;
  corner_y := fcp.center[1] - fcp.Height / ppuy / 2.0;
  t0 := gutter_width / (oversample * ppux);
  t1 := gutter_width / (oversample * ppuy);
  t2 := (2 * max_gutter_width - gutter_width) / (oversample * ppux);
  t3 := (2 * max_gutter_width - gutter_width) / (oversample * ppuy);

  camX0 := corner_x - t0;
  camY0 := corner_y - t1 + shift;
  camX1 := corner_x + fcp.Width / ppux + t2;
  camY1 := corner_y + fcp.Height / ppuy + t3; //+ shift;

  camW := camX1 - camX0;
  if abs(camW) > 0.01 then
    Xsize := 1.0 / camW
  else
    Xsize := 1;
  camH := camY1 - camY0;
  if abs(camH) > 0.01 then
    Ysize := 1.0 / camH
  else
    Ysize := 1;
  bws := (BucketWidth - 0.5)  * Xsize;
  bhs := (BucketHeight - 0.5) * Ysize;

  if FCP.FAngle <> 0 then
  begin
    cosa := cos(FCP.FAngle);
    sina := sin(FCP.FAngle);
    rcX := FCP.Center[0]*(1 - cosa) - FCP.Center[1]*sina - camX0;
    rcY := FCP.Center[1]*(1 - cosa) + FCP.Center[0]*sina - camY0;
  end;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.CreateCameraMM;
var
  scale: double;
  t0, t1: double;
  corner_x, corner_y, Xsize, Ysize: double;
  shift: Integer;
begin
  scale := power(2, fcp.zoom);
  sample_density := fcp.sample_density * scale * scale;
  ppux := fcp.pixels_per_unit * scale;
  ppuy := fcp.pixels_per_unit * scale;
  // todo field stuff
  shift := 0;
  t0 := gutter_width / (oversample * ppux);
  t1 := gutter_width / (oversample * ppuy);
  corner_x := fcp.center[0] - image_width / ppux / 2.0;
  corner_y := fcp.center[1] - image_height / ppuy / 2.0;

  camX0 := corner_x - t0;
  camY0 := corner_y - t1 + shift;
  camX1 := corner_x + image_width / ppux + t0;
  camY1 := corner_y + image_height / ppuy + t1; //+ shift;

  camW := camX1 - camX0;
  if abs(camW) > 0.01 then
    Xsize := 1.0 / camW
  else
    Xsize := 1;
  camH := camY1 - camY0;
  if abs(camH) > 0.01 then
    Ysize := 1.0 / camH
  else
    Ysize := 1;
  bws := (BucketWidth - 0.5)  * Xsize;
  bhs := (BucketHeight - 0.5) * Ysize;

  if FCP.FAngle <> 0 then
  begin
    cosa := cos(FCP.FAngle);
    sina := sin(FCP.FAngle);
    rcX := image_Center_X*(1 - cosa) - image_Center_Y*sina - camX0;
    rcY := image_Center_Y*(1 - cosa) + image_Center_X*sina - camY0;
  end;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.CalcBufferSize;
begin
  oversample := fcp.spatial_oversample;
  max_gutter_width := (MAX_FILTER_WIDTH - oversample) div 2;
  gutter_width := (FImageMaker.GetFilterSize - oversample) div 2;
  BucketWidth := oversample * fcp.Width + 2 * max_gutter_width;
  BucketHeight := oversample * fcp.Height + 2 * max_gutter_width;
  BucketSize := BucketWidth * BucketHeight;
end;

procedure TBaseRenderer.CalcBufferSizeMM;
begin
  oversample := fcp.spatial_oversample;
  gutter_width := (FImageMaker.GetFilterSize - oversample) div 2;
  BucketHeight := oversample * image_height + 2 * gutter_width;
  Bucketwidth := oversample * image_width + 2 * gutter_width;
  BucketSize := BucketWidth * BucketHeight;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.InitBuffers;
var
  w, h, bits: integer;
begin
  bits := GetBits;
  w := BucketWidth;
  h := BucketHeight;

  CalcBufferSize;

  try
    if Assigned(strOutput) then
      strOutput.Add(TimeToStr(Now) +
             Format(' : Allocating %n Mb of memory', [BucketSize * SizeOfBucket[bits] / 1048576]));

    AllocateBuckets; // SetLength(buckets, BucketHeight, BucketWidth); // hmm :-/

  except
    on EOutOfMemory do begin
      if Assigned(strOutput) then
        strOutput.Add('Error: not enough memory for this render!')
      else
        Application.MessageBox('Error: not enough memory for this render!', 'Apophysis', 48);
      BucketWidth := 0;
      BucketHeight := 0;
      FStop := 1; //true;
      exit;
    end;
  end;

  // share the buffer with imagemaker
  FImageMaker.SetBucketData(GetBucketsPtr, BucketWidth, BucketHeight, bits);
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.Render;
begin
  if fcp.NumXForms <= 0 then exit;
  FStop := 0; //False;

  FImageMaker.SetCP(FCP);
  FImageMaker.Init;

  
  InitBuffers;
  if FStop <> 0 then exit; // memory allocation error?

  CreateColorMap;
  Prepare;

  CreateCamera;
  if not FRenderOver then ClearBuckets;

  RenderTime := Now;
  SetPixels;
  RenderTime := Now - RenderTime;

  if FStop >= 0 then begin
    if Assigned(strOutput) then begin
      if fcp.sample_density = fcp.actual_density then
        strOutput.Add(TimeToStr(Now) + ' : Creating image')
      else
        strOutput.Add(TimeToStr(Now) + Format(' : Creating image with quality = %f', [fcp.actual_density]));
    end;
    FImageMaker.OnProgress := OnProgress;
    FImageMaker.CreateImage;
  end;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TBaseRenderer.RenderMM;
const
  Dividers: array[0..15] of integer = (1, 2, 3, 4, 5, 6, 7, 8, 10, 16, 20, 32, 64, 128, 256, 512);
var
  ApproxMemory, MaxMemory: int64;
  i: integer;
  zoom_scale, center_base, center_y: double;
  t: TDateTime;
begin
  FStop := 0; //False;

  image_Center_X := fcp.center[0];
  image_Center_Y := fcp.center[1];

  image_Height := fcp.Height;
  image_Width := fcp.Width;
  oversample := fcp.spatial_oversample;

  // entered memory - imagesize
  MaxMemory := FMaxMem * 1024 * 1024 - 4 * image_Height * int64(image_Width);

  ApproxMemory := SizeOfBucket[GetBits] * sqr(oversample) * image_Height * int64(image_Width);

  assert(MaxMemory > 0);
  if MaxMemory <= 0 then exit;

  FNumSlices := 1 + ApproxMemory div MaxMemory;

  if FNumSlices > Dividers[High(Dividers)] then begin
    for i := High(Dividers) downto 0 do begin
      if image_height <> (image_height div dividers[i]) * dividers[i] then begin
        FNumSlices := dividers[i];
        break;
      end;
    end;
  end else begin
    for i := 0 to High(Dividers) do begin
      if image_height <> (image_height div dividers[i]) * dividers[i] then
        continue;
      if FNumSlices <= dividers[i] then begin
        FNumSlices := dividers[i];
        break;
      end;
    end;
  end;

  FImageMaker.SetCP(FCP);
  FImageMaker.Init;

  fcp.height := fcp.height div FNumSlices;
  center_y := fcp.center[1];
  zoom_scale := power(2.0, fcp.zoom);
  center_base := center_y - ((FNumSlices - 1) * fcp.height) /  (2 * fcp.pixels_per_unit * zoom_scale);

  image_height := fcp.Height;
  image_Width := fcp.Width;

  InitBuffers;
  CreateColorMap;
  Prepare;

  RenderTime := 0;
  for i := 0 to FNumSlices - 1 do begin
    if FStop <> 0 then Exit;

    FSlice := i;
    fcp.center[1] := center_base + fcp.height * slice / (fcp.pixels_per_unit * zoom_scale);
    CreateCameraMM;
    ClearBuckets;

    t := Now;
    SetPixels;
    RenderTime := RenderTime + (Now - t);

    if FStop = 0 then begin
      if Assigned(strOutput) then strOutput.Add(TimeToStr(Now) + ' : Creating image');
      FImageMaker.OnProgress := OnProgress;
      FImageMaker.CreateImage(Slice * fcp.height);
    end;
  end;

  fcp.height := fcp.height * FNumSlices;
end;

///////////////////////////////////////////////////////////////////////////////
//
//  { TRenderer }
//
///////////////////////////////////////////////////////////////////////////////

destructor TRenderer.Destroy;
begin
  if assigned(FRenderer) then
    FRenderer.Free;

  inherited;
end;

///////////////////////////////////////////////////////////////////////////////
function TRenderer.GetImage: TBitmap;
begin
  Result := nil;
  if assigned(FRenderer) then
    Result := FRenderer.GetImage;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRenderer.SetCP(CP: TControlPoint);
begin
  FCP := CP;
end;

{
///////////////////////////////////////////////////////////////////////////////
constructor TRenderer.Create;
begin
end;
}

///////////////////////////////////////////////////////////////////////////////
procedure TRenderer.Render;
begin
  if assigned(FRenderer) then
    FRenderer.Free;

  assert(Fmaxmem=0);
  if FMaxMem = 0 then begin
    FRenderer := TRenderer32.Create;
  end else begin
    FRenderer := TRenderer32MM.Create;
    FRenderer.MaxMem := FMaxMem
  end;

  FRenderer.SetCP(FCP);
//  FRenderer.compatibility := compatibility;
  FRenderer.OnProgress := FOnProgress;
  FRenderer.Render;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRenderer.Stop;
begin
  if assigned(FRenderer) then
    FRenderer.Stop;
end;

{
procedure TRenderer.UpdateImage(CP: TControlPoint);
begin

end;

procedure TRenderer.SaveImage(const FileName: String);
begin
  if assigned(FRenderer) then
    FRenderer.SaveImage(FileName);
end;

procedure TRenderer.GetBucketStats(var Stats: TBucketStats);
begin
  if assigned(FRenderer) then
    FRenderer.GetBucketStats(Stats);
end;
}

end.

