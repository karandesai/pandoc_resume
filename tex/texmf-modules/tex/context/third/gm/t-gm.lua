-- This is a bare bone wrapper to Graphics Magick Wand C API
-- plus some Core (that hopefully will be complete  some day).
-- Graphics Magick uses several external program 
-- so be sure to have those you need already installed (at least ghostscript for eps and ps)
-- See http://www.graphicsmagick.org/wand/wand.html for a complete documentation

--
-- Warning: this doesn't work with luajittex !
--

local version	= "1.3.21"
local gm	= require("swiglib.graphicsmagick.core",version) 
local report_state = logs.reporter("graphics","gm-wand")

if not(gm) then
 report_state("error: failed loading core" )
 return false
end



local res_type_sp					= {} 
res_type_sp[core.PixelsPerInchResolution]		= 4736286.7
res_type_sp[core.PixelsPerCentimeterResolution]		= 1864679.8
res_type_sp[core.UndefinedResolution]			= res_type_sp[core.PixelsPerInchResolution] -- often ok --

local res_type_bp					= {} 
res_type_bp[core.PixelsPerInchResolution]		= 72
res_type_bp[core.PixelsPerCentimeterResolution]		= 28.346457
res_type_bp[core.UndefinedResolution]			= res_type_bp[core.PixelsPerInchResolution] -- often ok --



local res_type_txt					= {} 
res_type_txt[core.UndefinedResolution]			= 'Undefined'
res_type_txt[core.PixelsPerInchResolution]		= 'PixelsPerInch'
res_type_txt[core.PixelsPerCentimeterResolution]	= 'PixelsPerCentimeter'


local colorspace					= {}
colorspace[core.UndefinedColorspace]			= "UndefinedColorspace"
colorspace[core.RGBColorspace]				= "RGBColorspace"
colorspace[core.GRAYColorspace]				= "GRAYColorspace"
colorspace[core.TransparentColorspace]			= "TransparentColorspace"
colorspace[core.OHTAColorspace]				= "OHTAColorspace"
colorspace[core.XYZColorspace]				= "XYZColorspace"
colorspace[core.YCCColorspace]				= "YCCColorspace"
colorspace[core.YIQColorspace]				= "YIQColorspace"
colorspace[core.YPbPrColorspace]			= "YPbPrColorspace"
colorspace[core.YUVColorspace]				= "YUVColorspace"
colorspace[core.CMYKColorspace]				= "CMYKColorspace"
colorspace[core.sRGBColorspace]				= "sRGBColorspace"
colorspace[core.HSLColorspace]				= "HSLColorspace"
colorspace[core.HWBColorspace]				= "HWBColorspace"
colorspace[core.LABColorspace]				= "LABColorspace"
colorspace[core.CineonLogRGBColorspace]			= "CineonLogRGBColorspace"
colorspace[core.Rec601LumaColorspace]			= "Rec601LumaColorspace"
colorspace[core.Rec601YCbCrColorspace]			= "Rec601YCbCrColorspace"
colorspace[core.Rec709LumaColorspace]			= "Rec709LumaColorspace"
colorspace[core.Rec709YCbCrColorspace]			= "Rec709YCbCrColorspace"

local compression					= {}
compression[core.UndefinedCompression]			= "UndefinedCompression"
compression[core.NoCompression]				= "NoCompression"
compression[core.BZipCompression]			= "BZipCompression"
compression[core.FaxCompression]			= "FaxCompression"
compression[core.Group4Compression]			= "Group4Compression"
compression[core.JPEGCompression]			= "JPEGCompression"
compression[core.LosslessJPEGCompression]		= "LosslessJPEGCompression"
compression[core.LZWCompression]			= "LZWCompression"
compression[core.RLECompression]			= "RLECompression"
compression[core.ZipCompression]			= "ZipCompression"

gm.InitializeMagick("")
local imginfo = gm.GetMagickInfo("*",nil)
local formats   = {}
while(imginfo)  do
   if imginfo.name and imginfo.name:len() > 0 then 
    formats[imginfo.name] = {
         ['description']		= imginfo.description,
         ['r']			= (imginfo.decoder~=nil), 
         ['w']			= (imginfo.encoder~=nil), 
         ['adj']		= (imginfo.encoder~=nil) and (imginfo.adjoin >0) ,
         ['coder_class']	= (imginfo.coder_class == gm.PrimaryCoderClass) and  'P' or (imginfo.coder_class == gm.StableCoderClass ) and  'S' or "",
	 ['version']		= (imginfo.version~=nil) or "",
    }
   end
   imginfo = imginfo.next
end
gm.DestroyMagick()


gm.Images			= {}
gm.core				= core 
gm.version			= version
gm.resolution_type_texsp	= res_type_sp 
gm.resolution_type_texbp	= res_type_bp 
gm.resolution_type_text		= res_type_txt 
gm.colorspace			= colorspace
gm.compression			= compression
gm.formats			= formats
gm.cachefile                    = false
gm.true_val                     = 1
gm.false_val                    = 0

--
-- User level
--
-- \enabledirectives[system.callbacks.permitoverloads]
-- WARNING: this is a dangerous setup !
directives.enable("system.callbacks.permitoverloads")



-- We also need helpers  1.0.3 
local helpers	= require("swiglib.helpers.core","1.0.3") 
if not(helpers) then 
   report_state("error: need helpers  1.0.3")
   return false
end

moduledata.swiglib = moduledata.swiglib or {}
if moduledata.swiglib.graphicsmagick~=nil then 
   report_state("error: conflicts with another graphicsmagick")
else
  moduledata.swiglib.graphicsmagick = gm 
end


local find_image_file_callback = callback.find('find_image_file')
if type(find_image_file_callback)~='function' then 
   report_state("error: callback find_image_file not found")
   moduledata.swiglib.graphicsmagick = nil 
   return false 
end


local memstream_doc_uri = 'data:application/pdf,'
callback.register('find_image_file' , 
		  function(name) 
                     -- print([[======================> Request:]]..name) 
		     if string.find(name,memstream_doc_uri) then 
			return name 
		     else 
			return find_image_file_callback(name) 
		     end   
		  end
)

-- tell to ConTeXt that we have 
-- a new type of image
local function identifiers_memstream(data)
   data.status.status = 1
   data.used.fullname = data.request.label
end
figures.identifiers.list[#figures.identifiers.list+1] = identifiers_memstream


--
-- a  fast digest
--
local function djb2_digest(s)
  local hash = 5381
  local s    = tostring(s)
  local byte = string.byte 
  for i=1,s:len() do 
     hash = ( (hash * 33 ) + byte(s,i) ) % 2^32
  end 
  return string.format("%x",hash)
end


local function init(path,env) 
  if env then
    for k,v in pairs(env) do 
      os.setenv(k,tostring(v))
    end
  end
  if path then 
      gm.InitializeMagick(path)
  else
     gm.InitializeMagick(".")
  end
end


local function _storeinfo(wand,name)
  local height		= function() return gm.MagickGetImageHeight(wand)  end 
  local width		= function() return gm.MagickGetImageWidth(wand)   end 
  local units		= function() return gm.MagickGetImageUnits(wand)   end 
  local images		= function() return gm.MagickGetNumberImages(wand) end 
  local curr_img	= function() return 1+gm.MagickGetImageScene(wand) end
  local res		= 
   function()
     local _x,x = helpers.new_double_array(1),-1
     local _y,y = helpers.new_double_array(1),-1
     gm.MagickGetImageResolution(wand, _x,_y); 
     x = helpers.double_array_getitem(_x,0)
     y = helpers.double_array_getitem(_y,0)
     helpers.delete_double_array(_x)
     helpers.delete_double_array(_y)
     return {['x'] = x, ['y'] = y}
  end
  local h_sp		= function() return height()/res().y * gm.resolution_type_texsp[units()] end
  local w_sp		= function() return width() /res().x * gm.resolution_type_texsp[units()] end
  local h_bp		= function() return height()/res().y * gm.resolution_type_texbp[units()] end
  local w_bp		= function() return width() /res().x * gm.resolution_type_texbp[units()] end 
  local colorspace	= function() return gm.colorspace[gm.MagickGetImageColorspace(wand)]     end
  -- some info for name
  gm.Images[name]={
     ['h']		= height,
     ['w']		= width,
     ['res']		= res,
     ['wand']		= wand,
     ['units']		= function() return gm.resolution_type_text[units()] end,
     ['images']		= images,
     ['current_image']	= curr_img,
     ['colorspace']	= colorspace,
     ['h_sp']		= h_sp,
     ['w_sp']		= w_sp,
     ['h_bp']		= h_bp,
     ['w_bp']		= w_bp,
  }
end



local function blobimage(blob,format,name)
  if not(blob) then
     report_state("error: blobimage called with bad blob "..tostring(blob))
     return false
  end 
  if not(format) then
     report_state("error: blobimage called with bad format "..tostring(format))
     return false
  end 
  if not(name) then
     local _name = djb2_digest(blob)..'.' .. format
     report_state("warning: blobimage called with bad name "..tostring(name)..": using ".. _name)
     name = _name 
  end 
  --
  -- opening the same image destroy the
  -- previous one and create a new wand
  if gm.Images[name] then 
     gm.destroyimage(name)
  end   
  gm.Images[name]={}
  local wand     =  gm.NewMagickWand()
  if not(wand) then
     report_state("error: wand is NULL for "..name)
     return false
  end
  local blob_len = blob:len() -- embedded '\000' included !
  local res 
  res =  gm.MagickSetFormat(wand,format)
  if res == gm.false_val then
   report_state("error: MagickSetFormat failed")
   return false
  end
  res =  gm.MagickReadImageBlob(wand, blob, blob_len ) 
  if res == gm.false_val then
   report_state("error: MagickReadImageBlob failed")
   return false
  end
  -- The first image
  gm.MagickResetIterator(wand)
  _storeinfo(wand,name)
  return true,name
end



local function openimage(filename)
  if not(filename) then
     report_state("error: openimage called with bad filename "..tostring(filename))
     return false
  end 
  -- opening the same image destroy the
  -- previous one and create a new wand
  if gm.Images[filename] then 
     gm.destroyimage(filename)
  end   
  gm.Images[filename]={}

  local wand     =  gm.NewMagickWand()
  if not(wand) then
    report_state("error: wand is NULL for "..filename)
    return false
  end
  local res 
  res =  gm.MagickReadImage(wand, filename ) 
  if res == gm.false_val then
   report_state("error: MagickReadImage failed")
   return false
  end
  -- The first image
  gm.MagickResetIterator(wand)
   _storeinfo(wand,filename)
  return true
end



local function register(filename)
  if gm.Images[filename].doc_id~=nil then
     --already in memory
     return true
  end
 local my_img = gm.Images[filename]
  --[==[
 report_state("registered %s: %dx%d pixels, %dx%d %s %sx%s scaled point %sx%s bp format:%s colorspace:%s images:%d",
	       filename,
	       my_img.w(),my_img.h(),my_img.res().x,my_img.res().y,my_img.units(),
	       my_img.w_sp(),my_img.h_sp(),
	       my_img.w_bp(),my_img.h_bp(),
	       gm.MagickGetImageFormat( my_img.wand ),
	       my_img.colorspace(),
	       my_img.images()
  )
  ]==]
  local _l,l    = helpers.new_size_t_array(1),-1
  local my_img_wand= my_img.wand
  -- in-memory conversion to PDF (could use temp file , who knows?)
  gm.MagickSetImageFormat( my_img_wand, "PDF" )
  if gm.cachefile then
   gm.MagickWriteImage(my_img_wand, filename ..'_gm_1.0.pdf' );
  end
  local s       = gm.MagickWriteImageBlob( my_img_wand, _l ) --[==[ this is a SWIG userdata! ]==]
  l             = helpers.size_t_array_getitem(_l,0)
  helpers.delete_size_t_array(_l)
  if l<=0 then 
     report_state("error: cannot convert ".. tostring(filename).." to pdf")
     gm.destroyimage(filename)
     return false
  end
  -- brrr... an unboxed  uchar pointer 
  -- This is ok:
  -- print(helpers.swig_light_user_type(_s))
  -- but this gives seg. fault ( a wrong implementation of swig_type )
  -- print(helpers.swig_type(_s))
  local _s      = helpers.userdata_to_lightuserdata_uchar_p(s)
  local doc, doc_id, doc_uri = epdf.openMemStream(_s,l,filename)
  if not(doc) or not(doc_id) or (doc_uri~=memstream_doc_uri) then
     report_state("error: cannot create a doc for "..tostring(filename))
     if s then 
	gm.MagickRelinquishMemory(s) 
     end
     gm.destroyimage(filename)
     return false
  end
  -- ok, filename is converted as pdf and registered in the avl tree
  -- we must not free the array s, it's managed by luatex
  -- Also we have to anchor doc, otherwise the garbage collector can delete it
  -- when still in use
  gm.Images[filename]['doc']		= doc 
  gm.Images[filename]['doc_id']		= doc_id
  gm.Images[filename]['doc_uri']	= doc_uri
  pcall(  gm.DestroyMagickWand(gm.Images[filename]['wand']) )
  gm.Images[filename]['wand'] = nil
  return true 
end

local function destroyimage(filename)
  if gm.Images[filename] and gm.Images[filename]['wand'] then
     pcall(  gm.DestroyMagickWand(gm.Images[filename]['wand']) )
     gm.Images[filename] = nil 
     return true
  else 
    --report_state("error destroying: filename "..tostring(filename).." not found")
    return false
  end       
end

local function destroy() 
   local t = {}
   local imgs = gm.Images
   if imgs then
      for k,_ in pairs(imgs) do t[#t+1]=k   end
      for _,k in ipairs(t)   do gm.destroyimage(k) end
   end
   gm.DestroyMagick()
end


local function getdocid(name)
  return gm.Images[name].doc_id
end

gm.destroyimage = destroyimage
gm.destroy      = destroy 
gm.init         = init 
gm.blobimage    = blobimage
gm.openimage    = openimage
gm.register     = register
gm.digest       = djb2_digest
gm.getdocid     = getdocid
gm.getimage     = getdocid
gm.updateinfo   = _storeinfo
gm.report_state = report_state


luatex.registerstopactions(function()
			      report_state("closing all" )
			      destroy()
			      end
)
