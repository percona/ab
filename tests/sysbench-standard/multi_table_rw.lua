function prepare()
   local query
   local i

   set_vars()

   db_connect()

   for sbdb=1,dbs do

   db_name="sb"..sbdb

   db_query([[drop database if exists ]]..db_name) 
   db_query([[create database ]]..db_name) 
   
   db_query([[use ]]..db_name)
   print([[Creating db  ]]..db_name..[['...]])   

   for table=1,tables do

   print([[Creating table 'sbtest]]..table..[['...]])

   if (db_driver == "mysql") then
      query = [[
	    CREATE TABLE sbtest]]..table..[[ (
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

   db_query("CREATE INDEX k on sbtest"..table.."(k)")

   print("Inserting " .. oltp_table_size .. " records into 'sbtest"..table.."'")
   
   if (oltp_auto_inc) then
      db_bulk_insert_init("INSERT INTO sbtest"..table.."(k, c, pad) VALUES")
   else
      db_bulk_insert_init("INSERT INTO sbtest"..table.."(id, k, c, pad) VALUES")
   end

   for i = 1,oltp_table_size do
      if (oltp_auto_inc) then
	 db_bulk_insert_next("(0, ' ', 'qqqqqqqqqqwwwwwwwwwweeeeeeeeeerrrrrrrrrrtttttttttt')")
      else
	 db_bulk_insert_next("("..i..",0,' ','qqqqqqqqqqwwwwwwwwwweeeeeeeeeerrrrrrrrrrtttttttttt')")
      end
   end

   db_bulk_insert_done()
   print ("Done table sbtest"..table)
   end
   end

   return 0
end

function cleanup()
   for table=1,tables do
         
   print("Dropping table 'sbtest"..table.."'...")
   db_query("DROP TABLE sbtest"..table)
   end
end

function thread_init(thread_id)
   set_vars()

   idx=math.fmod(thread_id,tables)+1
   db_idx=math.fmod(thread_id,dbs)+1   

   print ("Init thread "..thread_id.. " for db sb"..db_idx.." table sbtest"..idx)

   db_query("use sb"..db_idx)
   point_stmt = db_prepare("SELECT id, k, c, pad from sbtest"..idx.." where id=?")
   point_params = {0}
   db_bind_param(point_stmt, point_params)


   if (only_ro == 0 ) then 
   update_nonidx_stmt = db_prepare("UPDATE sbtest"..idx.." SET c=? WHERE id=?")
   update_nonidx_params = {"", 0}
   db_bind_param(update_nonidx_stmt, update_nonidx_params)
   end

end

function event(thread_id)
   local rs
   local i

   point_params[1] = sb_rand(1, oltp_table_size)
   rs = db_execute(point_stmt)
   db_store_results(rs)
   db_free_results(rs)
   
   if (only_ro == 0 ) then
   update_nonidx_params[1] = sb_rand_str([[
###########-###########-###########-###########-###########-###########-###########-###########-###########-###########]])
   update_nonidx_params[2] = sb_rand(1, oltp_table_size)
   rs = db_execute(update_nonidx_stmt)
   end
   
end

function set_vars()
   oltp_table_size = oltp_table_size or 10000
   oltp_range_size = oltp_range_size or 100
   
   if (oltp_auto_inc == 'off') then
      oltp_auto_inc = false
   else
      oltp_auto_inc = true
   end
   
   if (only_ro=='' or only_ro==nill)                                                                              
   then                                                                                                                       
     only_ro=0     
   else
     only_ro=only_ro * 1
   end                
  
end
