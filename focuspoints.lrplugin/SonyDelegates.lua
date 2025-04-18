--[[
  Copyright 2016 Whizzbang Inc

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
--]]

--[[
  A collection of delegate functions to be passed into the DefaultPointRenderer when
  the camera is Sony
--]]

local LrStringUtils = import "LrStringUtils"
local LrView = import "LrView"
require "Utils"
require "Log"


SonyDelegates = {}

-- To trigger display whether focus points have been detected or not
SonyDelegates.focusPointsDetected = false

-- Tag that indicates that makernotes / AF section is present
SonyDelegates.metaKeyAfInfoSection = "Sony Model ID"

-- AF relevant tags
SonyDelegates.metaKeyExifImageWidth              = "Exif Image Width"
SonyDelegates.metaKeyExifImageHeight             = "Exif Image Height"
SonyDelegates.metaKeyAfFocusMode                 = "Focus Mode"
SonyDelegates.metaKeyAfFocusLocation             = "Focus Location"
SonyDelegates.metaKeyAfFocusPosition2            = "Focus Position 2"
SonyDelegates.metaKeyAfAreaModeSetting           = "AF Area Mode Setting"
SonyDelegates.metaKeyAfAreaMode                  = "AF Area Mode"
SonyDelegates.metaKeyAfTracking                  = "AF Tracking"
SonyDelegates.metaKeyAfFocalPlaneAFPointsUsed    = "Focal Plane AF Points Used"
SonyDelegates.metaKeyAfFocalPlaneAFPointArea     = "Focal Plane AF Point Area"
SonyDelegates.metaKeyAfFocalPlaneAFPointLocation = "Focal Plane AF Point Location %s"
SonyDelegates.metaKeyAfFacesDetected             = "Faces Detected"
SonyDelegates.metaKeyAfFacePosition              = "Face %s Position"
SonyDelegates.metaKeyAfSonyImageWidth            = "Sony Image Width"
SonyDelegates.metaKeyAfSonyImageHeight           = "Sony Image Height"
SonyDelegates.metaKeyAfPointsUsed                = "AF Points Used"

-- Image and Camera Settings relevant tags
SonyDelegates.metaKeySceneMode                   = "Scene Mode"
SonyDelegates.metaKeyImageStabilization          = "Image Stabilization"

-- relevant metadata values
SonyDelegates.metaValueNA                         = "N/A"


--[[
  public table SonyDelegates.getAfPoints(photo, metaData)
  ----
  Get autofocus points and frames for detected face from metadata
--]]
function SonyDelegates.getAfPoints(photo, metaData)

  SonyDelegates.focusPointsDetected = false

  -- Get orginal dimensions (in native aspect ratio)
  local orgPhotoWidth, orgPhotoHeight = DefaultPointRenderer.getNormalizedDimensions(photo)

  -- Exif Image dimensions may differ from original for photos taken with non-native aspect ratio
  local exifImageWidth  = ExifUtils.findValue(metaData, SonyDelegates.metaKeyExifImageWidth)
  local exifImageHeight = ExifUtils.findValue(metaData, SonyDelegates.metaKeyExifImageHeight)
  if not (exifImageWidth and exifImageHeight) then
    Log.logError("Sony",
      string.format("No valid information on image width/height. Relevant tags '%s' / '%s' not found",
        SonyDelegates.metaKeyExifImageWidth, SonyDelegates.metaKeyExifImageHeight))
    Log.logWarn("Sony", FocusInfo.msgImageNotOoc)
    return nil
  end

  local result

  local focusPoint = ExifUtils.findValue(metaData, SonyDelegates.metaKeyAfFocusLocation)
  if focusPoint then
    Log.logInfo("Sony",
      string.format("Focus point tag '%s' found", SonyDelegates.metaKeyAfFocusLocation))

    local values = split(focusPoint, " ")
    local imageWidth = LrStringUtils.trimWhitespace(values[1])
    local imageHeight = LrStringUtils.trimWhitespace(values[2])

    if imageWidth and imageHeight then
      if (imageWidth ~= "0") and (imageHeight ~= "0") then

        local fpW = LrStringUtils.trimWhitespace(values[1])
        local fpH = LrStringUtils.trimWhitespace(values[2])
        local fpX = LrStringUtils.trimWhitespace(values[3])
        local fpY = LrStringUtils.trimWhitespace(values[4])

        -- Consider coordinate shift in case the photo has been taken using an aspect ratio other than native 3:2
        local x = fpX + (orgPhotoWidth  - fpW) / 2
        local y = fpY + (orgPhotoHeight - fpH) / 2

        SonyDelegates.focusPointsDetected = true

        Log.logInfo("Sony", string.format("Focus point detected at [x=%s, y=%s]",
          math.floor(x), math.floor(y)))

        result = DefaultPointRenderer.createFocusPixelBox(x, y)

      else
        -- focus location string is "0 0 0 0" -> the focus point is a PDAF point #FIXME but which one exactly?
        Log.logWarn("Sony",
          string.format("Unusal CAF focus location: '%s'", focusPoint))
      end
    else
      Log.logError("Sony",
        string.format("No valid information on image width/height found"))
      Log.logWarn("Sony", FocusInfo.msgImageNotOoc)
    end
  else
    -- no focus points found - handled on upper layers
    Log.logWarn("Sony",
      string.format("Focus point tag '%s' tag not found", SonyDelegates.metaKeyAfFocusLocation))
  end

  -- Let's see if we used any PDAF points
  local numPdafPointsStr = ExifUtils.findValue(metaData, SonyDelegates.metaKeyAfFocalPlaneAFPointsUsed)
  if numPdafPointsStr then

    local numPdafPoints = LrStringUtils.trimWhitespace(numPdafPointsStr)
    if numPdafPoints then
      Log.logInfo("Sony", "PDAF points used: " .. numPdafPoints)

      local pdafDimensionsStr = ExifUtils.findValue(metaData, SonyDelegates.metaKeyAfFocalPlaneAFPointArea)
      if pdafDimensionsStr then

        local pdafDimensions = split(pdafDimensionsStr, " ")
        local pdafWidth  = LrStringUtils.trimWhitespace(pdafDimensions[1])
        local pdafHeight = LrStringUtils.trimWhitespace(pdafDimensions[2])
        if pdafWidth and pdafHeight then

          for i=1, numPdafPoints do
            local pdafPointStr = ExifUtils.findValue(
                    metaData, string.format(SonyDelegates.metaKeyAfFocalPlaneAFPointLocation, i))

            if pdafPointStr then
              local pdafPoint = split(pdafPointStr, " ")
              local pdafX = LrStringUtils.trimWhitespace(pdafPoint[1])
              local pdafY = LrStringUtils.trimWhitespace(pdafPoint[2])
              if pdafX and pdafY then
                Log.logDebug("Sony", "PDAF unscaled point at [" .. pdafX .. ", " .. pdafY .. "]")

                local xScale = exifImageWidth  / pdafWidth
                local yScale = exifImageHeight / pdafHeight

                local x = pdafX * xScale
                local y = pdafY * yScale

                -- Consider coordinate shift in case the photo has been taken using an aspect ratio other than native 3:2
                x = x + (orgPhotoWidth  - exifImageWidth ) / 2
                y = y + (orgPhotoHeight - exifImageHeight) / 2

                local pdafPointSize = orgPhotoWidth * 0.039/2  -- #TODO is 0.039/2 be different for other models?
                Log.logInfo("Sony", "PDAF scaled point at [" .. math.floor(x) .. ", " .. math.floor(x) .. "]")

                if not SonyDelegates.focusPointsDetected then
                  -- this is actually the focus point!
                  Log.logInfo("Sony", "Focus location at [" .. math.ceil(x * xScale) .. ", " .. math.floor(y * yScale) .. "]")
                  SonyDelegates.focusPointsDetected = true
                  result = {
                    pointTemplates = DefaultDelegates.pointTemplates,
                    points = {
                      {
                        pointType = DefaultDelegates.POINTTYPE_AF_FOCUS_BOX,
                        x = x,
                        y = y,
                        width = pdafPointSize,
                        height = pdafPointSize
                      }
                    }
                  }
                else
                  -- add the PDAF point as inactive point
                  table.insert(result.points, {
                    pointType = DefaultDelegates.POINTTYPE_AF_INACTIVE,
                    x = x,
                    y = y,
                    width = pdafPointSize,
                    height = pdafPointSize
                  })
                end
              end
            end
          end
        end
      end
    end
  end

  -- Let see if we have detected faces
  local detectedFaces = ExifUtils.findValue(metaData, SonyDelegates.metaKeyAfFacesDetected)
  if detectedFaces and detectedFaces > "0" then
    for i=1, detectedFaces, 1 do
      local currFaceTag = string.format(SonyDelegates.metaKeyAfFacePosition, i)
      local coordinatesStr = ExifUtils.findValue(metaData, currFaceTag)
      if coordinatesStr ~= nil then
        -- format as per https://exiftool.org/TagNames/Sony.html:
        -- scaled to return the top, left, height and width of detected face,
        -- with coordinates relative to the full-sized unrotated image and increasing Y downwards)
        local coordinatesTable = split(coordinatesStr, " ")
        local w = coordinatesTable[3]
        local h = coordinatesTable[4]
        local x = coordinatesTable[2] + w/2
        local y = coordinatesTable[1] + h/2
        Log.logInfo("Sony", "Face detected at [" .. x .. ", " .. y .. "]")
        local face = {
          pointType = DefaultDelegates.POINTTYPE_FACE,
          x = x,
          y = y,
          width  = w,
          height = h,
        }
        if result then
          table.insert(result.points, face)
        else
          -- an image can have detected face but no focus point!
          result = {
            pointTemplates = DefaultDelegates.pointTemplates,
            points = { face }
          }
        end
      end
    end
  end
  return result
end


--[[--------------------------------------------------------------------------------------------------------------------
   Start of section that deals with display of maker specific metadata
----------------------------------------------------------------------------------------------------------------------]]

--[[
  @@public table SonyDelegates.addInfo(string title, string key, table props, table metaData)
  ----
  Creates the view element for an item to add to a info section and creates/populates the corresponding property
--]]
function SonyDelegates.addInfo(title, key, props, metaData)
  local f = LrView.osFactory()

  -- Helper function to create and populate the property corresponding to metadata key
  local function populateInfo(key)
    local value
    if type(key) == "string" then
      value = ExifUtils.findValue(metaData, key)
    else
      -- type(key) == "table"
      value = ExifUtils.findFirstMatchingValue(metaData, key)
    end
    if (value == nil) then
      props[key] = SonyDelegates.metaValueNA
    else
      -- everything else is the default case!
      props[key] = value
    end
  end

  -- Avoid issues with implicite followers that do not exist for all models
  if not key then return nil end

  -- Create and populate property with designated value
  populateInfo(key)

  -- Check if there is (meaningful) content to add
  if props[key] and props[key] ~= SonyDelegates.metaValueNA then
    -- compose the row to be added
    local result = f:row {
      f:column{f:static_text{title = title .. ":", font="<system>"}},
      f:spacer{fill_horizontal = 1},
      f:column{f:static_text{title = wrapText(props[key], ",",30), font="<system>"}}
    }
    -- check if the entry to be added has implicite followers (eg. Priority for AF modes)
    if (key == SonyDelegates.metaKeyAfTracking) and string.find(string.lower(props[key]), "face") then
      return f:column{
        fill = 1, spacing = 2, result,
        SonyDelegates.addInfo("Faces Detected", SonyDelegates.metaKeyAfFacesDetected, props, metaData)
      }
    else
      -- add row as composed
      return result
    end
  else
    -- we won't display any "N/A" entries - return empty row
    return FocusInfo.emptyRow()
  end
end


--[[
  @@public table function SonyDelegates.getImageInfo(table photo, table props, table metaData)
  -- called by FocusInfo.createInfoView to append maker specific entries to the "Image Information" section
  -- if any, otherwise return an empty column
--]]
function SonyDelegates.getImageInfo(photo, props, metaData)
  local imageInfo
  return imageInfo
end


--[[
  @@public table function SonyDelegates.getCameraInfo(table photo, table props, table metaData)
  -- called by FocusInfo.createInfoView to append maker specific entries to the "Camera Information" section
  -- if any, otherwise return an empty column
--]]
function SonyDelegates.getCameraInfo(photo, props, metaData)
  local f = LrView.osFactory()
  local cameraInfo
  -- append maker specific entries to the "Camera Settings" section
  cameraInfo = f:column {
    fill = 1,
    spacing = 2,
    SonyDelegates.addInfo("Scene Mode"         , SonyDelegates.metaKeySceneMode         , props, metaData),
    SonyDelegates.addInfo("Image Stabilization", SonyDelegates.metaKeyImageStabilization, props, metaData),
  }
  return cameraInfo
end


--[[
  @@public table SonyDelegates.getFocusInfo(table photo, table info, table metaData)
  ----
  Constructs and returns the view to display the items in the "Focus Information" group
--]]
function SonyDelegates.getFocusInfo(photo, props, metaData)
  local f = LrView.osFactory()

  -- Check if makernotes AF section is (still) present in metadata of file
  local errorMessage = FocusInfo.afInfoMissing(metaData, SonyDelegates.metaKeyAfInfoSection)
  if errorMessage then
    -- if not, finish this section with predefined error message
    return errorMessage
  end

  -- Create the "Focus Information" section

  local focusInfo = f:column {
      fill = 1,
      spacing = 2,
      FocusInfo.FocusPointsStatus(SonyDelegates.focusPointsDetected),
      SonyDelegates.addInfo("Focus Mode"          , SonyDelegates.metaKeyAfFocusMode             , props, metaData),
      SonyDelegates.addInfo("AF Area Mode Setting", SonyDelegates.metaKeyAfAreaModeSetting       , props, metaData),
      SonyDelegates.addInfo("AF Area Mode"        , SonyDelegates.metaKeyAfAreaMode              , props, metaData),
      SonyDelegates.addInfo("AF Tracking"         , SonyDelegates.metaKeyAfTracking              , props, metaData),
--    SonyDelegates.addInfo("PDAF Point Used"     , SonyDelegates.metaKeyAfFocalPlaneAFPointsUsed, props, metaData),
      }
  return focusInfo
end
