ldb
===

**** Author  	: tanjie(tanjiesymbol@gmail.com)  
**** Date		: 2013-07-01  
**** Desc		: this is a gdb-like debug tools for lua  
**** Usage  :   
              1.require("ldb")  
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
	      12.set					--set the value of local or global  

