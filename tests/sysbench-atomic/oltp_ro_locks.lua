function prepare()
   local query
   local i

   set_vars()

   db_connect()

   print("Creating table 'sbtest'...")

   if (db_driver == "mysql") then
      query = [[
	    CREATE TABLE sbtest (
	      id INTEGER UNSIGNED NOT NULL ]] .. ((oltp_auto_inc and "AUTO_INCREMENT") or "") .. [[,
	      k INTEGER UNSIGNED DEFAULT '0' NOT NULL,
	      c CHAR(120) DEFAULT '' NOT NULL,
              pad CHAR(60) DEFAULT '' NOT NULL,
              PRIMARY KEY (id)
	    ) /*! ENGINE = ]] .. mysql_table_engine .. " MAX_ROWS = " .. myisam_max_rows .. " */"
   else
      print("Unknown database driver: " .. db_driver)
      return 1
   end

   db_query(query)

   db_query("CREATE INDEX k on sbtest(k)")

   print("Inserting " .. oltp_table_size .. " records into 'sbtest'")
   
   if (oltp_auto_inc) then
      db_bulk_insert_init("INSERT INTO sbtest(k, c, pad) VALUES")
   else
      db_bulk_insert_init("INSERT INTO sbtest(id, k, c, pad) VALUES")
   end

   for i = 1,oltp_table_size do
      if (oltp_auto_inc) then
	 db_bulk_insert_next("(0, ' ', 'qqqqqqqqqqwwwwwwwwwweeeeeeeeeerrrrrrrrrrtttttttttt')")
      else
	 db_bulk_insert_next("("..i..",0,' ','qqqqqqqqqqwwwwwwwwwweeeeeeeeeerrrrrrrrrrtttttttttt')")
      end
   end

   db_bulk_insert_done()

   return 0
end

function cleanup()
   print("Dropping table 'sbtest'...")
   db_query("DROP TABLE sbtest")
end

function thread_init(thread_id)
   set_vars()

   if (db_driver == "mysql" and mysql_table_engine == "myisam") then
      begin_stmt = db_prepare("LOCK TABLES sbtest READ")
      commit_stmt = db_prepare("UNLOCK TABLES")
   else
      begin_stmt = db_prepare("BEGIN")
      commit_stmt = db_prepare("COMMIT")
   end

   --query="select count(k) from sbtest where id< " .. selectivity .." "
   
   chunk=selectivity/chunks
   if (chunks*1>1)
   then 
    if (chunks_overlap_pct*1 > 0 and sb_rand(1, 100) <= chunks_overlap_pct*1)
    then
      --overlap
      print("overlap for thread" .. thread_id)
      low=chunk*thread_id
      high=chunk*(thread_id+2)
    else
     low=chunk*thread_id
     high=chunk*(thread_id+1)
    end
   else
     low=0
     high=selectivity
   end
   
   query="select count(k) from sbtest where id between " .. low .. " and "  .. high .." "

   query_for_update=query .. " for update"
   query_share_mode=query .. " lock in share mode"

   query_lock_exclusive="LOCK TABLE sbtest in exclusive mode";
   query_lock_share="LOCK TABLE sbtest in share mode";

   print ("query: " .. query)
   print ("query_ex: " .. query_lock_exclusive)
   print ("query_share: " .. query_lock_share)
         
   stmt=db_prepare(query)
   stmt_for_update=db_prepare(query_for_update)
   stmt_share_mode=db_prepare(query_share_mode)
   stmt_lock_exclusive=db_prepare(query_lock_exclusive)
   stmt_lock_share=db_prepare(query_lock_share)
   
   if (isolation_level ~= '' and  isolation_level ~=nil)
   then 
     --print ("set transaction isolation level " .. isolation_level)
     stmt_isolation_level=db_prepare("set transaction isolation level " .. isolation_level)
     rs=db_execute(stmt_isolation_level)
   end
 
   
end

function event(thread_id)
   local rs

   db_execute(begin_stmt)

   if (table_lock_mode=="exclusive")
   then 
     rs = db_execute(stmt_lock_exclusive)
   end 

   if (table_lock_mode=="share")
   then 
     rs = db_execute(stmt_lock_share)
   end 

   if (row_lock_mode=="no_lock")
   then 
     rs = db_execute(stmt)
     db_store_results(rs)
     db_free_results(rs)
   end

   if (row_lock_mode=="exclusive")
   then
     rs = db_execute(stmt_for_update)
     db_store_results(rs)
     db_free_results(rs)
   end

   if (row_lock_mode=="share")
   then
     rs = db_execute(stmt_share_mode)
     db_store_results(rs)
     db_free_results(rs)
   end

   db_execute(commit_stmt)
end

function set_vars()
   oltp_table_size = oltp_table_size or 10000
   oltp_range_size = oltp_range_size or 100
   debug = debug or nil

   if (debug )
   then
     print ("debug" )
   end
   
   if (oltp_auto_inc == 'off') then
      oltp_auto_inc = false
   else
      oltp_auto_inc = true
   end

   if (table_lock_mode=='' or table_lock_mode==nil)
   then 
     table_lock_mode="no_lock"
   end

   if (row_lock_mode=='' or row_lock_mode==nil)
   then 
     row_lock_mode="no_lock"
   end

   if (selectivity=='' or selectivity==nil)
   then 
     selectivity=oltp_table_size
   end

   if (chunks=='' or chunks==nil)
   then
     chunks=1
   end

   if (chunks_overlap_pct=='' or chunks_overlap_pct==nil)
   then
     chunks_overlap_pct=0
   end

   if (isolation_level ~= '' and  isolation_level ~=nil)
   then 
      if (isolation_level == "uncommitted")
      then 
        isolation_level="read uncommitted"
      elseif (isolation_level == "committed")
      then 
        isolation_level="read committed"
      elseif (isolation_level == "repeatable")
      then
        isolation_level="repeatable read"
      elseif (isolation_level == "serializable")
      then
         isolation_level="serializable"
      else
        print("Wrong isolation level: "..isolation_level)
        exit(1)
      end
      print ("isolation_level: " .. isolation_level)   
   end
   
   if (debug)
   then
     print ("chunks:          " .. chunks)
     print ("table_lock_mode: " .. table_lock_mode)
     print ("row_lock_mode:   " .. row_lock_mode)
     print ("selectivity:     " .. selectivity)
   end
end

function help()
set_vars()

print ([[

  isolation_level=<level>   level: uncommitted, committed, repeatable, serializable
  table_lock_mode=<mode>  (Default: no_lock)  mode: no_lock, share, exclusive
  row_lock_mode=<mode>  (Default: no_lock)    mode: no_lock, share, exclusive
  selectivity=<number of rows> number of rows to use for query (Default: max number of rows)
  chunks=<number of chunks> (Default: 1)
  chunks_overlap_pct=<% of overlaped chunks> (Default: 0)
           
       ]])
end
