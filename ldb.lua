--[[*****************************************************************************
**** Author		: tanjie(tanjiesymbol@gmail.com)
**** Date		: 2013-07-01
**** Desc		: this is a gdb-like debug tools for lua
**** Usage  : 1.require("ldb")
              2.ldb.ldb_open()  --you will pause here for setting breakpoints
              3.ldb.ldb()				--set breakpoint anywhere you want to pause
              4.b/bd/be/bl      --add/disable/enable/list  the breakpoints
              5.p/print         --print local or global variables
              6.s/step					--step into a function
              7.n/next					--step over a function
              8.l/list					--list ten lines around the current line
              9.f/file					--print the current file and line number
              10.bt							--print traceback
              11.c/cont					--continue
              12.set						--set the value local or global
              13.disp/display				--auto display variables on every command
              14.undisp/undisplay   --delete auto display
*****************************************************************************]]
module("ldb",package.seeall)
dbcmd = {
	next=false,
	trace=false,
	last_cmd="",
	bps={},
	max=0,
	status="",
	stack_depth = 0,
	script_name = "ldb.lua",
	display_list = {}
}

function Split(str, delim, maxNb)
    if string.find(str, delim) == nil then
        return { str }
    end
    if maxNb == nil or maxNb < 1 then
        maxNb = 0    -- No limit
    end
    local result = {}
    local pat = "(.-)" .. delim .. "()"
    local nb = 0
    local lastPos
    for part, pos in string.gmatch(str, pat) do
        nb = nb + 1
        result[nb] = part
        lastPos = pos
        if nb == maxNb then break end
    end
    -- Handle the last field
    if nb ~= maxNb then
        result[nb + 1] = string.sub(str, lastPos)
    end
    return result
end

function get_stack_depth()
	local stack_lines = Split(debug.traceback(),"\n")
	local depth = 0
	for i=1,#stack_lines do
        if string.find(stack_lines[i],dbcmd.script_name) == nil then
			depth = depth + 1
		end
	end
	return depth
end
function print_var(name,value,level)
	if type(value) == "table" then
		print(name .." = { ")
		for k,v in pairs(value) do
			print(k.." = "..tostring(v).." ")
		end
		print("}")
	else
		print(name .." = "..tostring(value))
	end
end
function str2var(varstr)
	local str = "return "..varstr
	return assert(loadstring(str))()
end
function get_local_or_global(var,new_value)
	local index = 1
	local val
	while true do
		local name,value = debug.getlocal(6,index)
		if not name then break end
		if name == var then
			if new_value ~=nil then
				debug.setlocal(6,index,new_value)
			end
			return value
		end
		index = index + 1
	end
	if _G[var] ~= nil then
		return _G[var]
	end
end
function get_var(expr,new_value)
	local varlist = Split(expr,"%.")
	local var = get_local_or_global(varlist[1])
	if var == nil then
		return
	end
	if #varlist == 1 then
		if new_value ~= nil then
			get_local_or_global(varlist[1],new_value)
		end
		return var
	end
	local last_var = var
	for i=2,#varlist do
		last_var = var
		if var[varlist[i]] == nil then
			if tonumber(varlist[i]) ~= nil and var[tonumber(varlist[i])] ~= nil then
				var = var[tonumber(varlist[i])]
			else
				return
			end
		else
			var = var[varlist[i]]
		end
		if i == #varlist then
			if new_value ~= nil then
				last_var[varlist[i]] = new_value
			end
			return var
		end
	end
end
function set_expr(expr)
	print("set expr="..expr)
	local l = Split(expr,"=")
	local si = string.find(expr,"=")
	if si == nil then
		print(expr .. "is not a valid set expression")
		return
	end

	local varname = string.sub(expr,0,si-1)
	local value = string.sub(expr,si+1)
	varname = string.match(varname,"^%s*(.-)%s*$")
	value = string.match(value,"^%s*(.-)%s*$")
	local var = get_var(varname)
	if var == nil then
		print(expr .. "is not valid")
	else
		local v = str2var(value)
		get_var(varname,v)
	end
end


function print_expr(expr)
	local var = get_var(expr)
	if var == nil then
		print(expr .. "is not valid!")
	else
		print_var(expr,var)
	end
end

function add_breakpoint(expr,env,bptype)
	local si = string.find( expr, ":" )
	local source = ""
	local line = ""
	if nil == si then
		line = tonumber(expr)
		if nil == line then
			print( "add breakpoint error, expr (" .. expr .. ") invalid" )
		end
		source = get_bpfile(env.short_src)
	else
		line = string.sub( expr, si + 1 )
		line = tonumber( line )
		source = get_bpfile(string.sub( expr, 1, si - 1 ))
		if ( dbcmd.bps[line] ~= nil ) and ( dbcmd.bps[line][source] ~= nil ) then
			print( string.format( "breakpoint %s:%d existed", source, line ) )
			return
		end
	end
	local tbl = {}
	tbl.source = source
	tbl.line = line
	tbl.active = true
	tbl.bptype = bptype or "normal"
	tbl.number = dbcmd.max + 1

	if dbcmd.bps[line] == nil then
		dbcmd.bps[line] = {}
	end

	dbcmd.bps[line][source] = tbl
	dbcmd.max = dbcmd.max + 1
	print("breakpoint "..tbl.number.." at "..source..":"..line)
end

function del_breakpoint(expr)
	local bp_number = tonumber(expr)
	for k,v in pairs(dbcmd.bps) do
		if type(v) == "table" then
			for k1,v1 in pairs(v) do
				if v1.number == bp_number then
					dbcmd.bps[k][k1] = nil
					print("breakpoint no:"..bp_number.." removed")
					return
				end
			end
		end
	end
	print("breakpoint :"..bp_number.." not found")
end

function enable_breakpoint(expr)
	local bp_number = tonumber(expr)
	for k,v in pairs(dbcmd.bps) do
		if type(v) == "table" then
			for k1,v1 in pairs(v) do
				if v1.number == bp_number then
					dbcmd.bps[k][k1].active = true
					print("breakpoint :"..bp_number.." enabled")
					return
				end
			end
		end
	end
	print("breakpoint :"..bp_number.." not found")
end

function disable_breakpoint(expr)
	local bp_number = tonumber(expr)
	for k,v in pairs(dbcmd.bps) do
		if type(v) == "table" then
			for k1,v1 in pairs(v) do
				if v1.number == bp_number then
					dbcmd.bps[k][k1].active = false
					print("breakpoint :"..bp_number.." disabled")
					return
				end
			end
		end
	end
	print("breakpoint :"..bp_number.." not found")
end



function show_breakpoint()
	for k,v in pairs(dbcmd.bps) do
		if type(v) == "table" then
			for k1,v1 in pairs(v) do
				local str = string.format("breakpoint :%d %s:%d ",v1.number,v1.source,v1.line)
				if v1.active then
					str = str .. "active"
				else
					str = str .. "disable"
				end
				print(str)
			end
		end
	end
end


function execute_cmd(env)
	io.write( "(ldb) " )
	io.input(io.stdin)
	local cmd = string.match(io.read("*line"),"^%s*(.-)%s*$")
	if cmd~="" then
		dbcmd.last_cmd = cmd
	else
		cmd = dbcmd.last_cmd
	end
	local c = ""
	local expr = ""
	if not cmd then
		return false
	end
	local i = string.find(cmd," ")
	if i ~= nil then
		c = string.sub(cmd,1,i-1)
		expr = string.sub(cmd,string.find(cmd," [%w/.]") + 1)
	else
		c = cmd
		expr = ""
	end
	if c ~= "p" and c ~= "print" then
		for k,v in pairs(dbcmd.display_list) do
			print_expr(v)
		end
	end
	if c == "c" or c == "cont" then
		dbcmd.trace = false
		return true
	elseif c == "s" or c == "step" then
		dbcmd.trace = true
		return true
	elseif c == "p" or c == "print" then
		print_expr(expr)
	elseif c == "b" or c == "break" then
		add_breakpoint(expr,env)
	elseif c == "bt" then
		print(debug.traceback("",3))
	elseif c == "bl" or c == "breaklist" then
		show_breakpoint()
	elseif c == "be" or c == "breakenable" then
		enable_breakpoint(expr)
	elseif c == "bd" or c == "breakdisable" then
		disable_breakpoint(expr)
	elseif c == "d" or c == "delete" then
		del_breakpoint(expr)
	elseif c == "l" or c == "list" then
		local curfname = string.gsub(env.source,"@","")
		if tonumber(expr) ~= nil then
			print_file_lines(curfname,tonumber(expr))
		else
			print_file_lines(curfname,env.currentline)
		end
	elseif c == "f" or c == "file" then
		print(env.short_src..":"..env.currentline)
	elseif c == "n" or c == "next" then
        dbcmd.stack_depth = get_stack_depth()
        dbcmd.status = "next"
		dbcmd.trace = false
		return true
	elseif c == "set" then
		set_expr(expr)
	elseif c == "disp" or c == "display" then
		table.insert(dbcmd.display_list,expr)
	elseif c == "undisp" or c == "undisplay" then
		for i=1,#(dbcmd.display_list) do
			if dbcmd.display_list[i] == expr then
				table.remove(dbcmd.display_list,i)
			end
		end
	end


	return false



end

function print_file_lines(filename,cur_line)
	io.input(filename)
	local line1 = math.max(cur_line - 5,1)
	local line2 = cur_line +5
	for i = 1,line2 do
		local line = io.read("*line")
		if not line then
			return
		end
		if i == cur_line then
			print(i.." ->|"..line)
		elseif i >=line1 and i <=line2 then
			print(i.."   |"..line)
		end
	end
end


function get_file_line(filename,line)
	io.input(filename)
	for i=1,line-1 do io.read("*line") end
	local src = io.read("*line")
	return src
end

function get_bpfile(filename)
	local fname
	fname = string.gsub(string.lower(filename),"\\","/")
	for w in string.gmatch(fname,"([%w%d-_]+.lua)") do 
		fname = w
	end
	return fname
end

function trace(event,line)
	local env = debug.getinfo(2)
	if get_bpfile(env.short_src)==dbcmd.script_name  then
		return
	end

	if ( not dbcmd.trace) and (dbcmd.bps[line] ~= nil) then
		local tbl = dbcmd.bps[line][get_bpfile(env.short_src)]
		if tbl~=nil and tbl.active then
			dbcmd.trace = true
			print("breakpoint:"..env.short_src..":"..line)
			if tbl.bptype == "once" then
				del_breakpoint(tbl.number)
			end
		end
	end
    if dbcmd.status == "next" then
        local depth = get_stack_depth()
        if depth <= dbcmd.stack_depth then
            dbcmd.trace = true
            dbcmd.status = ""
        end
    end

	if dbcmd.trace then
		local fname = string.gsub(env.source,"@","")
		local src = get_file_line(fname,line)
		local funname = env.name or "unknown"
		print(line.."   |"..src)
		while not execute_cmd(env) do end
	end

end
function ldb_open()
	dbcmd.trace = true
	debug.sethook(trace,"l")
end
function ldb()
	dbcmd.trace = true
end
function ldb_close()
	dbcmd.trace = false
	debug.sethook()
end


