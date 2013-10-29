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
              15.finish					-- Execute until selected stack frame returns.
              16.info               --print all local/global/upvalue (info local/global/upvalue)
              16.h/help             --print help information
*****************************************************************************]]
module("ldb",package.seeall)

helps = {
	b='b/break add a breakpoint with or without a condition. eg. "b main.lua:50 gt index 5" \nsupport 4 condition breakpoint:gt(greater)/lt(smaller)/eq(equal)/md(modified) \neg. "b main.lua:50 gt index 5"  /  "b main.lua:50 lt index 5"  /"b main.lua:50 eq index 5" /"b main.lua:50 md index"',
	bl = 'bl list all breakpoint',
	be = 'be  enable a breakpoint',
	bd = 'bd  disable a breakpoint',
	d  = 'd/delete  delete a breakpoint',
	p= 'p/print print the value of a  specific local or global or upvalue',
	s = 's/step  step into a funciton',
	n = 'n/next  step over a line of code',
	l = 'l/list  list ten lines around current line',
	f = 'f/file  print current file and line number',
	bt = 'print traceback',
	c = 'c/cont  continue',
	set = 'set  set the value of local or global or upvalue',
	disp = 'disp/display  auto display variables on every command',
	finish = 'finish Execute until selected stack frame returns',
	info = 'info print all local/global/upvalue (info local/global/upvalue)',
	load = 'load execute a line of lua code',
	h = 'h/help show help information',
}


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
			print(tostring(k).." = "..tostring(v).." ")
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
function get_local_or_global(var,level,new_value)
	if not level then
		level = 6
	end
	local index = 1
	local val
	while true do
		local name,value = debug.getlocal(level,index)
		if not name then break end
		if name == var then
			if new_value ~=nil then
				debug.setlocal(level,index,new_value)
			end
			return value
		end
		index = index + 1
	end
	if _G[var] ~= nil then
		return _G[var]
	end
	local func = debug.getinfo(level).func
	local i = 1
	while true do
		local name,value = debug.getupvalue(func,i)
		if not name then break end
		if name == var then
			if new_value ~=nil then
				debug.setupvalue(func,i,new_value)
			end
			return value
		end
		i = i + 1
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
			get_local_or_global(varlist[1],6,new_value)
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
		print(expr .. " is not valid")
	else
		local v = str2var(value)
		get_var(varname,v)
	end
end


function print_expr(expr)
	local var = get_var(expr)
	if var == nil then
		print(expr .. " is not valid!")
	else
		print_var(expr,var)
	end
end

function add_breakpoint(expr,env,bptype)
	local cond = ''
	local bp = ''
	local i = string.find(expr," ")
	if i ~= nil then
		bp = string.sub(expr,1,i-1)
		cond = string.sub(expr,string.find(expr," [%w/.]") + 1)
	else
		bp = expr
		cond = ""
	end

	local si = string.find( bp, ":" )
	local source = ""
	local line = ""
	if nil == si then
		line = tonumber(bp)
		if nil == line then
			print( "add breakpoint error, bp (" .. bp .. ") invalid" )
		end
		
		source = get_bpfile(env.short_src)
	else
		line = string.sub( bp, si + 1 )
		line = tonumber( line )
		source = get_bpfile(string.sub( bp, 1, si - 1 ))
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
	if cond ~= '' then
		local cl = Split(cond,"%s")
		tbl.cond_operator = cl[1]
		if tbl.cond_operator ~= 'gt' and tbl.cond_operator ~= 'lt' and tbl.cond_operator ~= 'eq' and tbl.cond_operator ~= 'md' then
			print("breakpoint condition operator ("..tbl.cond_operator..") error! operator must be one of gt/lt/eq/md")
			return
		end
		if tbl.cond_operator == 'md' then
			if #cl ~= 2 then
				print("breakpoint condition format error! the format: md operand")
				return
			end
		else
			if #cl ~= 3 then
				print("breakpoint condition format error! the format: operator operand1 operand2")
				return
			end
		end

		tbl.cond_operand1 = cl[2]
		if tbl.cond_operator == 'md' then
			tbl.cond_operand2 = get_local_or_global(tbl.cond_operand1,3)
			if not tbl.cond_operand2 then
				print(tbl.cond_operand1 .." not exist!")
				return
			end
		else
			tbl.cond_operand2 = cl[3]
		end
	end

	if dbcmd.bps[line] == nil then
		if line then
			dbcmd.bps[line] = {}
		else
			return
		end
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

function show_var(vartype)
	if vartype == "local" then
		print("local variables:")
		local index = 1
		while true do
			local name,value = debug.getlocal(4,index)
			if not name then break end
			print_var(name,value)
			index = index + 1
		end
	elseif vartype == "global" then
		print("global variables:")
		print_expr("_G")
	elseif vartype == "upvalue" then
		print("upvalue variables:")
		local func = debug.getinfo(4).func
		local i = 1
		while true do
			local name,value = debug.getupvalue(func,i)
			if not name then break end
			print_var(name,value)
			i = i + 1
		end
	end
end




















function print_help(command)
	if command then
		if helps[command] then
			print(helps[command])
		else
			print('no such command')
			for k,v in pairs(helps) do
				print(v)
			end
		end
	else
		for k,v in pairs(helps) do
			print(v)
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
	elseif c == "finish" then
		dbcmd.stack_depth = get_stack_depth()
		dbcmd.status = "finish"
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
	elseif c == "i" or c == 'info' then
		show_var(expr)
	elseif c == "o" or c == "load" then
		print(expr)
		local func = loadstring(expr)
		if func then
			func()
		else
			print('loadstring error! '..expr)
		end
	elseif c == 'h' or c == 'help' then
		print_help(expr)
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
	--for w in string.gmatch(fname,"([%w%d-_]+.lua)") do 
	for w in string.gmatch(fname,"([%w%d-_.]+)") do 
		fname = w
	end
	if not string.find(fname,"\.lua$") then
		fname = fname .."\.lua"
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
			local trace_flag = false
			if tbl.cond_operator and tbl.cond_operator ~= '' then
				print(tbl.cond_operator.." "..tbl.cond_operand1.." "..tbl.cond_operand2)
				local op1_value = get_local_or_global(tbl.cond_operand1,3)
				if op1_value == nil then
					print("op1_value is nil")
				else
					local op2_value
					if type(op1_value) == "string" then
						op2_value = tostring(tbl.cond_operand2)
					elseif type(op1_value) == "number" then
						op2_value = tonumber(tbl.cond_operand2)
					else
						print("op1 type not string or number")
					end
					if tbl.cond_operator == "gt" and op1_value > op2_value then
						trace_flag = true
					end
					if tbl.cond_operator == "lt" and op1_value < op2_value then
						trace_flag = true
					end
					if tbl.cond_operator == "eq" and op1_value == op2_value then
						trace_flag = true
					end
					if tbl.cond_operator == "md" and op1_value ~= op2_value then
						trace_flag = true
					end
				end
			else
				trace_flag = true
			end
			print("trace_flag="..tostring(trace_flag))
			if trace_flag == true then
				dbcmd.trace = true
				print("breakpoint:"..env.short_src..":"..line)
			end			
			--if tbl.bptype == "once" then
			--	del_breakpoint(tbl.number)
			--end
		end
	end
    if dbcmd.status == "next" then
        local depth = get_stack_depth()
        if depth <= dbcmd.stack_depth then
            dbcmd.trace = true
            dbcmd.status = ""
        end
    end
    if dbcmd.status == "finish" then
    	local depth = get_stack_depth()
    	if depth < dbcmd.stack_depth then
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


