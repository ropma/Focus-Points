--[[
  Copyright 2019 Whizzbang Inc, ropma

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

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrErrors = import 'LrErrors'
local LrTasks = import 'LrTasks'
local LrPrefs = import "LrPrefs"

require "Utils"

MogrifyUtils = { }    -- class

local fileName
local mogrifyPath

-- local helper functions

--[[
-- Call mogrify with 'params'
-- Raises a LrError in case of an execution error
--]]
local function mogrifyExecute(params, script)
  if mogrifyPath == nil then
    mogrifyPath = LrPathUtils.child( _PLUGIN.path, "bin" )
    mogrifyPath = LrPathUtils.child( mogrifyPath, "ImageMagick" )
    mogrifyPath = LrPathUtils.child(mogrifyPath, "magick.exe")
  end

  local scriptName
  local cmdline = '\"' .. mogrifyPath .. '\" '
  if script then
    scriptName = createMagickScript(params)
    cmdline = cmdline .. '-script ' .. '\"' .. scriptName .. '\"'
  else
    cmdline = cmdline .. 'mogrify ' .. params
  end
  logDebug('mogrifyExecute', cmdline )
  local stat = LrTasks.execute( '\"' .. cmdline .. '\"' )
  if stat ~= 0 then
    logError('mogrifyDraw', 'Error calling: ' .. cmdline )
    LrErrors.throwUserError("Error calling 'mogrify.exe' Please check plugin configuration")
  end
  if script then
    local prefs = LrPrefs.prefsForPlugin( nil )
    if prefs.loggingLevel ~= "DEBUG" then
      -- keep temporary script file for log level DEBUG
      LrFileUtils.delete(scriptName)
    end
  end

end


--[[
-- Export the catalog photo to disk
-- photo: Lr catalog photo
-- xSize: width in pixel of the create temporary photo
-- ySize: height in pixel of the create temporary photo
--
-- requestJpegThumbnail treats the size as minimum value, thus the image on the disk maybe larger
--
-- Note: in LrC 14 (at least on WIN) this function fails on the first call for an image.
-- Analysis and proposal for a fix by John R. Ellis (LR SDK luminary on Adobe forums):
--
-- requestJpegThumbnail() appears to call the callback synchronously if the requested thumbnail
-- is in an internal cache. Otherwise, it returns immediately and calls the callback asynchronously
-- after the thumbnail is generated and loaded into the cache, which could take anywhere from
-- 0.01 seconds to a couple seconds if the photo has to be re-rendered.
-- In order to make sure the thumbnail has been written to file before proceeding with the next
-- steps, exportToDisk() should busy wait until the callback is invoked.
-- photo:getRawMetadata() has to be executed outside the callback, because this method "yields"
-- which is not allowed in a no-yielding context (asynchronous call of callback)
--]]
local function exportToDisk(photo, xSize, ySize)
  local done = false
  local orgPath = photo:getRawMetadata("path")
  local thumb = photo:requestJpegThumbnail(xSize, ySize, function(data, errorMsg)
    if data == nil then
      logError('exportToDisk', 'No thumbnail data')
      LrErrors.throwUserError("Export to disk failed. No thumbnail data received.")
    else
      local leafName = LrPathUtils.leafName( orgPath )
      local leafWOExt = LrPathUtils.removeExtension( leafName )
      local tempPath = LrPathUtils.getStandardFilePath( "temp" )
      fileName = LrPathUtils.child( tempPath, leafWOExt .. "-fpoints.jpg" )
      logDebug('exportToDisk', "filename = " .. fileName )

      local localFile = io.open(fileName, "w+b")
      localFile:write(data)
      localFile:close()
    end
    done = true
  end)
  if not done then
  -- busy wait for (asynchronous) callback to complete
    while not done do LrTasks.sleep (0.1) end
  end
end


--[[
-- Resize the disk image to the given ize
-- xSize: width in pixel
-- ySize: height in pixel
--]]
local function mogrifyResize(xSize, ySize)
  local params = '-resize ' .. math.floor(xSize) .. 'x' .. math.floor(ySize) .. ' \"' .. fileName  .. '\"'
  logDebug('mogrifyResize', params )
  mogrifyExecute(params, false)
end

--[[
-- Get color and strokewith from the icon name
--]]
local function mapIconToStrokewidthAndColor(name)
  local sw = 2
  local color = string.match(name, 'assets/imgs/corner/(%a+)/.*')
  if string.match(name, 'fat') == 'fat' then
    sw = 3
  end
  return sw, color
end

--[[
-- Build the mogrify draw parameters base on the focuspointsTable
--]]
local function buildDrawParams(focuspointsTable)
  local para
  local sw
  local color

  local params = '-fill none '
  for i, fpPoint in ipairs(focuspointsTable) do
    if fpPoint.template.center ~= nil then
      local x = math.floor(tonumber(fpPoint.points.center.x))
      local y = math.floor(tonumber(fpPoint.points.center.y))
      para = '-stroke red -fill red -draw \"circle ' ..x .. ',' .. y .. ' ' .. x+3 .. ',' .. y  .. '\" -fill none '
      logDebug('buildCmdLine', '[' .. i .. '] ' .. para )
      params = params .. para
    end
    if fpPoint.template.corner ~= nil then
      sw, color = mapIconToStrokewidthAndColor(fpPoint.template.corner.fileTemplate)
      para = '-strokewidth ' .. sw .. ' -stroke ' .. color .. ' '
      local tlx = math.floor(tonumber(fpPoint.points.tl.x))
      local tly = math.floor(tonumber(fpPoint.points.tl.y))
      local brx = math.floor(tonumber(fpPoint.points.br.x))
      local bry = math.floor(tonumber(fpPoint.points.br.y))
      -- normalize
      if tlx > brx and ( fpPoint.rotation == 0 or fpPoint.rotation == 360) then
        local x = tlx
        tlx = brx
        brx = x
      end
      if fpPoint.rotation == 0 or fpPoint.rotation == 360 then
        para = para .. '-draw \"roundRectangle ' .. tlx .. ',' .. tly .. ' ' .. brx .. ',' .. bry .. ' 1,1\" '
      else
        local trx = math.floor(tonumber(fpPoint.points.tr.x))
        local try = math.floor(tonumber(fpPoint.points.tr.y))
        local blx = math.floor(tonumber(fpPoint.points.bl.x))
        local bly = math.floor(tonumber(fpPoint.points.bl.y))
        para = para .. '-draw \"polyline ' .. trx .. ',' .. try .. ' ' .. tlx .. ',' .. tly .. ' '
                  .. blx .. ',' .. bly .. ' ' .. brx .. ',' .. bry .. ' ' .. trx .. ',' .. try .. '\" '
      end
      logDebug('buildCmdLine', '[' .. i .. '] ' .. para .. ' ' .. fpPoint.template.corner.fileTemplate)
      params = params .. para
    end
  end
  return params
end

--[[
-- Create a temprory disk impage for the given Lightroom catalog photo.
-- photo: Lr catalog photo
-- xSize: width in pixel of the create temporary photo
-- ySize: height in pixel of the create temporary photo
--]]
function MogrifyUtils.createDiskImage(photo, xSize, ySize)
  logInfo('MogrifyUtils.createDiskImage', photo:getFormattedMetadata( 'fileName' ) .. ' ' .. xSize .. ' ' .. ySize )
  exportToDisk(photo, xSize, ySize)
  mogrifyResize(xSize, ySize)
  return fileName
end


--[[
-- Draw the focus poins bases on focuspointsTable (see 'DefaultPointRenderer.prepareRendering' for adescription of the table)
--]]
function MogrifyUtils.drawFocusPoints(focuspointsTable)
  local params = buildDrawParams(focuspointsTable)
  mogrifyExecute(params, true)
end


--[[
-- Creates a temporay script file for Magick. Returns the name of the temp file
--]]
function createMagickScript(params)
  local scriptName = os.tmpname()
  local file = io.open(scriptName, "w")
  file:write('-read \"' .. fileName .. '\"', "\n")
  file:write(params, "\n")
  file:write('-write \"' .. fileName .. '\"', "\n")
  file:close()
  return scriptName
end


--[[
-- Deletes the temporary file (created by 'MogrifyUtils.exportToDisk')
-- Raises a LrError in case that the deletion fails
--]]
function MogrifyUtils.cleanup()
  if fileName ~= nil then
    local resultOK, errorMsg  = LrFileUtils.delete( fileName )
    if errorMsg ~= nil then
      logError('MogrifyUtils.cleanup', errMsg)
      LrErrors.throwUserError("Deletion of temporary file failed: " ..  errMsg)
    end
  end
end
