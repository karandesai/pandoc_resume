-- This is a bare bone wrapper to Graphics Magick Wand C API
-- plus some Core (that hopefully will be  complete  some day).
-- Graphics Magick uses several external program ( see gm convert -list Delegate)
-- so be sure to have those you need already installed (at least ghostscript for eps and ps)
-- See http://www.graphicsmagick.org/wand/wand.html for a complete documentation

--
-- Warning: this doesn't work with luajittex !
--

local report_state = logs.reporter("graphics","gs")


local version	= "9.15"
local gs	= require("swiglib.ghostscript.core",version) 
if not(gs) then
 report_state("error: failed loading core" )
 return false
end

local gsusr	= require("swiglib.ghostscript.usercore",version) 
if not(gsusr) then
 report_state("error: failed loading user core" )
 return false
end


local helpers	= require("swiglib.helpers.core","1.0.3") 
if not(helpers) then 
   report_state("error: need helpers  1.0.3")
   return false
end


moduledata.swiglib = moduledata.swiglib or {}
if moduledata.swiglib.ghostscript~=nil then 
   report_state("error: conflicts with another ghostscript")
else
  moduledata.swiglib.ghostscript = gs
end
if moduledata.swiglib.ghostscriptusr~=nil then 
   report_state("error: conflicts with another ghostscriptusr")
else
  moduledata.swiglib.ghostscriptusr = gsusr
end



local max_dimen_bbox    = 150000
local max_dimen_tex     = 16322
local gs_calc_bbox      = true 
local stdout_buffer	= {}
local stderr_buffer	= {}
local arg_init		= {"t-gs", -- just a name 
                           --"-dDEBUG", 
			   "-dQUIET" , 
			   "-dNOPAUSE","-dBATCH", 
			   --'-dEPSCrop',
			   --"-dSAFER", NO!
}


-- return an unsigned  char *
local function getchar(s)
 if not(type(s) == 'string') or (#s == 0) then 
    return nil 
 end
 local stream = helpers.new_u_char_array(#s)
 for i=1,#s do
  helpers.u_char_array_setitem(stream,i-1,string.byte(string.sub(s,i,i)))
 end
 helpers.u_char_array_setitem(stream,#s,0)
 return stream
end

-- gs need a splitted input buffer
local split_input = function (s,l)
   local t={}
   if l==nil then 
      l=2^16-1
   end
   if (type(l) ~= type(0)) then
      return t
   end
   l = math.floor(math.abs(l))
   if l==0 then
      return t
   end
   s = tostring(s) 
   if s==nil then 
      return t
   end
   if s:len()<=l then
      t[#t+1] = s
      return t
   end
   local chunks = math.floor(s:len() / l) 
   for i = 0, chunks-1 do
      local base = i*l
      t[i+1] = string.sub(s,base+1,base+l)
   end
   if s:len()-(chunks*l) > 0 then 
      local base = chunks*l
      t[#t+1] = string.sub(s,base+1,s:len())
   end
   return t
end


local calculate_bbox_lpeg = function(s)
   local sp	= lpeg.patterns.space^1
   local d	= lpeg.C(lpeg.P('-')^-1*lpeg.patterns.digit^1) 
   local bbox	= lpeg.P('%%BoundingBox:')*sp*d*sp*d*sp*d*sp*d
   local _t	= lpeg.match((1-bbox)^1*lpeg.Ct(bbox)*(1-bbox)^1,s) 
   if _t == nil then 
      bbox	= lpeg.P('%%HiResBoundingBox:')*sp*d*sp*d*sp*d*sp*d
       _t	= lpeg.match((1-bbox)^1*lpeg.Ct(bbox)*(1-bbox)^1,s) 
       if _t == nil then 
	  report_state("calculate_bbox_lpeg cannot find a valid (HiRes)BoundingBox")
	  return {}, {}
       end
   end
   return {_t[3],_t[4],_t[1],_t[2]}, {_t[3],_t[4],_t[1],_t[2]}
end


local calculate_bbox = function(ps_string)
   local max_dimen	= gs.Max_dimen_bbox
   local max_dimen_tex  = gs.Max_dimen_tex
   local bbox_device	= table.concat({
	  ' << /PageSize [',
  	  max_dimen," ",max_dimen,
	  '] /OutputDevice /bbox  >> setpagedevice ', 
	  max_dimen/2,' ', max_dimen/2, ' translate gsave \n'})
   ps_string		= table.concat({bbox_device, ps_string, "\ngrestore\n"})
   local state          = gs.State
   local _ref_exit_code = helpers.new_int_p()
   local code 
   local old_stderr = gs.Get_stderr() 
   gs.Reset_stderr()
   -- print("===",ps_string,"===")
   code = gs.gsapi_run_string_begin(state, 0, _ref_exit_code); 
   if code == 0 then 
      local t =  split_input(ps_string)
      for i=1,#t do 
	 code = gs.gsapi_run_string_continue(state, t[i], t[i]:len(), 
					     0, _ref_exit_code) 
      end
   end
   if code == gs.e_NeedInput then 
      code = gs.gsapi_run_string_end(state, 0, _ref_exit_code); 
   end
   if code<0 then 
      report_state("Error on calculate_bbox "..code.." state=".. tostring(state))
      helpers.delete_int_p(_ref_exit_code)
      local err = gs.Get_stderr() 
      gs.Reset_stderr()
      gs.Stderr_buffer[#gs.Stderr_buffer+1] = old_stderr
      gs.Stderr_buffer[#gs.Stderr_buffer+1] = err
      return {} ,{}
   end
   
   -- if all is ok, stderr has the output bbox
   local bbox		= {}
   local hires_bbox	= {}
   local gs_stderr_str	= gs.Get_stderr() 
   report_state("current_bbox found "..gs_stderr_str)
   gs.Reset_stderr()
   gs.Stderr_buffer[#gs.Stderr_buffer+1] = old_stderr
   for i1,i2,i3,i4 in  string.gmatch(gs_stderr_str,'%%%%BoundingBox:%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s*') do
      bbox[#bbox+1]	= i1; bbox[#bbox+1] = i2
      bbox[#bbox+1]	= i3; bbox[#bbox+1] = i4
   end
   for i1,i2,i3,i4 in  string.gmatch(gs_stderr_str,'%%%%HiResBoundingBox:%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*') do
      hires_bbox[#hires_bbox+1] = i1; hires_bbox[#hires_bbox+1] = i2
      hires_bbox[#hires_bbox+1] = i3; hires_bbox[#hires_bbox+1] = i4
   end

   helpers.delete_int_p(_ref_exit_code)
   if #bbox<4 or #hires_bbox<4 then
	 report_state("calculate_bbox_lpeg")
	 return  calculate_bbox_lpeg(ps_string)
   end
   
   local xoffset , yoffset		= bbox[1]-max_dimen/2,bbox[2]-max_dimen/2
   local hires_xoffset , hires_yoffset	= hires_bbox[1]-max_dimen/2,hires_bbox[2]-max_dimen/2

   bbox[3]		= bbox[3] - bbox[1];                   bbox[1] = 0
   bbox[4]		= bbox[4] - bbox[2];                   bbox[2] = 0
   hires_bbox[3]	= hires_bbox[3] - hires_bbox[1]; hires_bbox[1] = 0
   hires_bbox[4]	= hires_bbox[4] - hires_bbox[2]; hires_bbox[2] = 0
   -- sometimes  bbox fails..
   if (bbox[3]>max_dimen_tex) or (bbox[4]>max_dimen_tex) or 
      (hires_bbox[3]>max_dimen_tex) or (hires_bbox[4]>max_dimen_tex) then 
	 report_state("calculate_bbox_lpeg")
	 return  calculate_bbox_lpeg(ps_string)
   end
   return {bbox[3],bbox[4],xoffset,yoffset}, {hires_bbox[3],hires_bbox[4],hires_xoffset,hires_yoffset}
end



local gs_stdin = function(minst,buf,len)
   --report_state("gs_stdin:"..buf.. " " .. len)
   return 0
end

local gs_stdout = function(minst,buf,len)
   --report_state("gs_stdout:"..buf.. " " .. len)
   stdout_buffer[#stdout_buffer+1]=buf
   return len
end

local gs_stderr = function(minst,buf,len)
   --report_state("gs_stderr:"..buf.." "..len)
   stderr_buffer[#stderr_buffer+1] = buf
   return len
end

local reset_stderr = function()
   stderr_buffer = {}
end


local get_stderr = function()
   return table.concat(stderr_buffer,' ')
end


local update_arg_init = function(t) 
   if (t ~= nil) and (type(_t)==type({})) then 
      for i,v in ipairs(_t) do
	 gs.arg_init[#gs.arg_init+1] = v
      end
   end
end


local set_arg_init = function(t) 
   if type(t) == 'string' then 
       t = utilities.parsers.settings_to_array(t)
       if #t==0 then 
         t = nil
       end
   end
   if (t ~= nil) and (type(t)=='table') then 
      arg_init = {}
      for i,v in ipairs(t) do
	 arg_init[#arg_init+1] = v
      end
   end
   gs.Arg_init  = arg_init
end


local function osnulldevice()
   -- unix 
   local nulldevice = '/dev/null'
   local _t = lfs.attributes(nulldevice) 
   if _t.mode == 'char device' and _t.permissions == 'rw-rw-rw-' then 
      return nulldevice
   end
   -- windows 
   if os.type == 'windows' then 
      _t = lfs.attributes('nul') 
      if _t.permissions == 'rw-rw-rw-' then 
	 return 'nul'
      end
   end
   return false 
end


local function gs_flush()
   local state	  = gs.State 
   local nullfile = osnulldevice()
   if not(nullfile) then 
      nullfile = "%stdout"
   end 
   report_state("flushing /OutputFile to "..nullfile)
   local _s = "<< /OutputDevice /pdfwrite /OutputFile ("..nullfile..") >> setpagedevice"
   local _ref_exit_code = helpers.new_int_p()
   gs.gsapi_run_string_begin(state, 0, _ref_exit_code); 
   gs.gsapi_run_string_continue(state, _s, _s:len(), 0, _ref_exit_code); 
   gs.gsapi_run_string_end(state, 0, _ref_exit_code); 
   helpers.delete_int_p(_ref_exit_code)
end



local function gs_run(s,name,func_device)
   local state			= gs.State 
   local pdffilename            = name
   local bbox, hires_bbox	
   local w,h,xoff,yoff	 
   local pdf_device	 

   report_state("gs:run "..name)
   pdf_device	= table.concat({'<<  /OutputDevice /pdfwrite   /OutputFile (',pdffilename,') >> setpagedevice ',
   })

   if gs.CalculateBBox then 
      bbox, hires_bbox	= calculate_bbox(s)  
      if #bbox<4 or #hires_bbox<4 then
	 report_state("gs:run:Error on calculate_bbox for "..name..", there are fewer than 4 components")
	 return {} ,{}
      end
      
      w,h,xoff,yoff  = hires_bbox[1],hires_bbox[2],hires_bbox[3],hires_bbox[4]
      pdf_device     = table.concat({'<< /PageSize [',w, ' ', h,
 '] /OutputDevice /pdfwrite   /OutputFile (',pdffilename,') >> setpagedevice ',
						  -xoff, ' ', -yoff,
					       ' translate '})
   end
   local device         =  pdf_device
   if type(func_device) == "function" then 
      device = func_device(w,h,xoff,yoff,s,name) 
   end
   report_state("gs_run pdf_device="..pdf_device)
   report_state("gs_run     device="..device)
   local ps_string      =  table.concat({'\ngsave \n',device,s,'\ngrestore \n'})
   local _ref_exit_code = helpers.new_int_p()
   local  code
   code = gs.gsapi_run_string_begin(state, 0, _ref_exit_code); 
   if code == 0 then 
      local t =  split_input(ps_string)
      for i=1,#t do 
	 code = gs.gsapi_run_string_continue(state, t[i], t[i]:len(), 0, _ref_exit_code); 
      end
   end
   --if code == gs.e_NeedInput then 
   --  code = gs.gsapi_run_string_continue(state, "quit", 4, 0, _ref_exit_code); 
   --end
   if code == gs.e_NeedInput then 
      code = gs.gsapi_run_string_end(state, 0, _ref_exit_code); 
   end
   --   gs_flush()
   helpers.delete_int_p(_ref_exit_code)
   return code
end

local function gs_run_buffer(s,name,device) 
   local code 
   local _name
   if not(name) then 
	 _name = "psbuf-"..gs.GlobalCounter.."-.pdf"
         gs.GlobalCounter = gs.GlobalCounter+1
         name =  _name 
   end
   code =  gs_run(s,name,device) 
   return code, name
end

local function gs_run_file(filename,notpdf,device) 
   local f_ps = io.open(filename)
   local s = f_ps:read('*a') 
   f_ps:close()
   local code
   if not(notpdf) then
      filename = file.removesuffix(filename)..'.pdf' 
   end
   code = gs_run(s,filename,device) 
   return code, filename
end


local function gs_init()
   local gsargv,gsargc
   local state, _state 
   local code
   _state = helpers.new_void_p_p()
   
   code = gs.gsapi_new_instance(_state, nil)
   if (code < 0) then
      report_state("gs:Error on new instance, "..tostring(code))
      return false
   end
   -- gs.Arg_init[1] = 't-gs'  -- to be sure ?
   gsargc  = #gs.Arg_init

   gsargv  = helpers.new_char_p_array(gsargc)
   for i=0,gsargc-1 do
      helpers.char_p_array_setitem(gsargv,i,gs.Arg_init[i+1])
   end
   gs.Reset_stderr()
   state = helpers.void_p_p_value(_state)
   gs.gsapi_set_stdio_callback(state, gs.Stdin, gs.Stdout, gs.Stderr)
   code = gs.gsapi_set_arg_encoding(state, gs.GS_ARG_ENCODING_UTF8)
   if (code == 0) then 
      code = gs.gsapi_init_with_args(state, gsargc,gsargv)
   elseif (code<0) then 
      gs.gsapi_exit(state)
      gs.gsapi_delete_instance(state)
      report_state("gs:Error on ser_arg_encoding, "..tostring(code))
      return false
   end
   gs.State = state 
   return true 
end

local function gs_end()
  local state = gs.State 
  if not(state)  then 
     report_state("gs: state nil (already closed?)")
     --return gs.e_unknownerror
     return 0 
  end
  code =  gs.gsapi_exit(state) 
  gs.gsapi_delete_instance(state) 
  gs.State  = nil 
  report_state("gs: end with return code ".. ( (code==0 and 'OK') or code))
  return code 
end

luatex.registerstopactions(function()
                              local code 
 			      code = gs_end()
			      report_state("closing all: return code " .. code)
 			      end
)




-- case up to avoid conflicts 
gs.Stdout_buffer	= stdout_buffer	
gs.Stderr_buffer	= stderr_buffer		
gs.Stdin		= gs_stdin 
gs.Stdout		= gs_stdout 
gs.Stderr		= gs_stderr 
gs.Reset_stderr		= reset_stderr 
gs.Get_stderr           = get_stderr
gs.Arg_init             = arg_init
gs.Update_arg_init      = update_arg_init
gs.Set_arg_init         = set_arg_init
gs.End                  = gs_end
gs.Init                 = gs_init
gs.Max_dimen_bbox       = max_dimen_bbox    
gs.Max_dimen_tex        = max_dimen_tex    
gs.Calculate_bbox       = calculate_bbox
gs.State                = nil
gs.GlobalCounter        = 0
gs.Run                  = gs_run
gs.Run_file             = gs_run_file
gs.Run_buffer           = gs_run_buffer
gs.Flush                = gs_flush
gs.CalculateBBox        = gs_calc_bbox


