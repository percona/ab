function prepare()
   local query
   local i
   local j
   local loops
   local chunks

   oltp_auto_inc="off"

   set_vars()

   db_connect()

--   cleanup()

--   print("Creating table'".. mysql_table .. "' ENGINE:" .. mysql_table_engine .."...")

   print("Creating table '" .. oltp_table_name .. "' ENGINE:" .. mysql_table_engine .."...")

   if (db_driver == "mysql") then
      query = [[
                 CREATE TABLE IF NOT EXISTS phptest (
                  id int(10) unsigned NOT NULL auto_increment,
                  name varchar(64) NOT NULL default '',
                  email varchar(64) NOT NULL default '',
                  password varchar(64) NOT NULL default '',
                  dob date default NULL,
                  address varchar(128) NOT NULL default '',
                  city varchar(64) NOT NULL default '',
                  state_id tinyint(3) unsigned NOT NULL default '0',
                  zip varchar(8) NOT NULL default '',
                  country_id smallint(5) unsigned NOT NULL default '0',
                  PRIMARY KEY  (id)
                 ) /*! ENGINE = ]] .. mysql_table_engine .. " */"
   else
      print("Unknown database driver: " .. db_driver)
      return 1
   end



   db_query(query)

   db_query("CREATE INDEX email on phptest(email)")
   db_query("CREATE INDEX country_id on phptest(country_id,state_id,city)")

   print("Inserting " .. oltp_table_size .. " records into 'phptest'")
   
   if (oltp_auto_inc) then
      db_bulk_insert_init("INSERT INTO phptest(name, email, password, dob, address, city, state_id, zip, country_id) VALUES")
   else
      db_bulk_insert_init([[
                            INSERT INTO phptest(id, name, password, email, city, zip, dob,
                                                state_id,  country_id) VALUES
                          ]])
   end

   for i = 1, oltp_table_size do
      if (oltp_auto_inc) then
	 db_bulk_insert_next("(0,"..rand_varchar(64)..","..rand_varchar(64)..","..rand_email()..","..rand_varchar(64)..","..rand_varchar(8)..",NOW(),"..sb_rand(1,countrySize)..","..sb_rand(stateSize)..")")
      else
	 db_bulk_insert_next("("..get_autoinc()..","..rand_varchar(64)..","..rand_varchar(64)..","..rand_email()..","..rand_varchar(64)..","..rand_varchar(8)..",NOW(),"..sb_rand(1,countrySize)..","..sb_rand(1,stateSize)..")")
      end
   end
   db_bulk_insert_done()

   return 0
end


function cleanup()
   print("Dropping table 'phptest'...")
   db_query("DROP TABLE phptest")
end

function thread_init(thread_id)
   local query
   
   params={}   
   set_vars()

   if ( mrr == 'off') 
   then
     print ("Disabling mrr")
     db_query("set @@optimizer_use_mrr='disable'")
   end

   if ( cond_pushdown == 'off') 
   then
     print ("Disabling condition_pushdown")
     db_query("set @@engine_condition_pushdown=OFF")
   end

   begin_stmt = db_prepare("BEGIN")
   commit_stmt = db_prepare("COMMIT")


   if (db_driver == "mysql" and mysql_table_engine == "myisam") then
     begin_stmt = db_prepare("LOCK TABLES sbtest READ")
     commit_stmt = db_prepare("UNLOCK TABLES")
   else
     begin_stmt = db_prepare("BEGIN")
     commit_stmt = db_prepare("COMMIT")
   end
				 

   if (subtest == "READ_PK_POINT" )
   then 
     query= [[
               SELECT name FROM phptest WHERE id = ?
            ]]
     params = {0}
   elseif (subtest == "READ_KEY_POINT" )
   then
     query= [[
               SELECT name FROM phptest WHERE country_id = ?     
            ]]
      params = {0}
   elseif (subtest == "READ_KEY_POINT_NO_DATA" )
   then
     query= [[
               SELECT state_id FROM phptest WHERE country_id = ?
            ]]
     params = {0}
   elseif (subtest == "READ_KEY_POINT_LIMIT" )
   then
     query= [[
               SELECT name FROM phptest WHERE country_id = ? limit 5
            ]]
     params = {0}
   elseif (subtest == "READ_KEY_POINT_NO_DATA_LIMIT" )
   then
     query= [[
               SELECT state_id FROM phptest WHERE country_id = ? limit 5
            ]]
     params = {0}
   elseif (subtest == "READ_PK_POINT_INDEX" )
   then
     query= [[
               SELECT id FROM phptest WHERE id = ?
            ]]
     params = {0}
   elseif (subtest == "READ_PK_RANGE" )
   then
     query= [[
               SELECT min(dob) FROM phptest WHERE id between ? and ?
            ]]
     params = {0,0}
   elseif (subtest == "READ_PK_RANGE_INDEX" )
   then
     query= [[
               SELECT count(id) FROM phptest WHERE id between ? and ?     
            ]]
     params = {0,0}
   elseif (subtest == "READ_KEY_RANGE" )
   then
     query= [[
               SELECT name  FROM phptest WHERE country_id = ? and state_id between ? and ?
            ]]
     params = {"",0,0}
   elseif (subtest == "READ_KEY_RANGE_LIMIT" )
   then
     query= [[
               SELECT name  FROM phptest WHERE country_id = ? and state_id between ? and ? LIMIT 50
            ]]
     params = {"",0,0}
   elseif (subtest == "READ_KEY_RANGE_NO_DATA" )
   then
     query= [[
               SELECT city  FROM phptest WHERE country_id = ? and state_id between ? and ?
            ]]
     params = {"",0,0}
   elseif (subtest == "READ_KEY_RANGE_NO_DATA_LIMIT" )
   then
     query= [[
               SELECT city  FROM phptest WHERE country_id = ? and state_id between ? and ? LIMIT 50
            ]]
     params = {"",0,0}
   elseif (subtest == "READ_FTS" )
   then
     query= [[
               SELECT min(dob) FROM phptest
            ]]
   elseif (not subtest)
   then
     print ("ERROR: YOU HAVE TO SPECIFY SUBTEST: --subtest=<name>")
     os.exit(255)
   else
     print ("UNKNOWN SUBTEST=" .. subtest .. "!!!")
     os.exit(255)
   end  

   stmt = db_prepare(query)
   
   if (table.maxn(params)>0)
   then 
     db_bind_param(stmt, params)
   end
end

function event(thread_id)
   local rs
   local p1
   local p2

   if (trx_mode)
   then
     db_execute(begin_stmt)
   end

   if (subtest == "READ_PK_POINT" )
   then 
     params[1] = sb_rand(1, oltp_table_size)
               -- SELECT name FROM phptest WHERE id = ?
   elseif (subtest == "READ_KEY_POINT" )
   then
     params[1] = sb_rand(1, countrySize)
               -- SELECT name FROM phptest WHERE country_id = ?     
   elseif (subtest == "READ_KEY_POINT_NO_DATA" )
   then
     params[1] = sb_rand(1, countrySize)
--   SELECT state_id FROM phptest WHERE country_id = ?
   elseif (subtest == "READ_KEY_POINT_LIMIT" )
   then
     params[1] = sb_rand(1, countrySize)
               -- SELECT name FROM phptest WHERE country_id = ? limit 5
   elseif (subtest == "READ_KEY_POINT_NO_DATA_LIMIT" )
   then
     params[1] = sb_rand(1, countrySize)
               -- SELECT state_id FROM phptest WHERE country_id = ? limit 5
   elseif (subtest == "READ_PK_POINT_INDEX" )
   then
     params[1] = sb_rand(1, oltp_table_size)
               -- SELECT id FROM phptest WHERE id = ?
   elseif (subtest == "READ_PK_RANGE" )
   then

     p1=sb_rand(1, oltp_table_size-rangeDiapason)
     params[1] = p1
     params[2] = p1+rangeDiapason
               -- SELECT min(dob) FROM phptest WHERE id between ? and ?
   elseif (subtest == "READ_PK_RANGE_INDEX" )
   then

     p1=sb_rand(1, oltp_table_size-rangeDiapason)
   
     params[1] = p1
     params[2] = p1+rangeDiapason
               -- SELECT count(id) FROM phptest WHERE id between ? and ?     
   elseif (subtest == "READ_KEY_RANGE" )
   then
     p1=sb_rand(1, countrySize)
     p2=sb_rand(1, stateSize)
   
     params[1] = p1
     params[2] = p2
     params[3] = p2+10
               -- SELECT name  FROM phptest WHERE country_id = ? and state_id between ? and ?
   elseif (subtest == "READ_KEY_RANGE_LIMIT" )
   then
     p1=sb_rand(1, countrySize)
     p2=sb_rand(1, stateSize)
   
     params[1] = p1
     params[2] = p2
     params[3] = p2+10
               -- SELECT name  FROM phptest WHERE country_id = ? and state_id between ? and ? order by 1 LIMIT 50
   elseif (subtest == "READ_KEY_RANGE_NO_DATA" )
   then
     p1=sb_rand(1, countrySize)
     p2=sb_rand(1, stateSize)
   
     params[1] = p1
     params[2] = p2
     params[3] = p2+10
               -- SELECT city  FROM phptest WHERE country_id = ? and state_id between ? and ?
   elseif (subtest == "READ_KEY_RANGE_NO_DATA_LIMIT" )
   then
     params[1] = sb_rand(1, oltp_table_size)
               -- SELECT city  FROM phptest WHERE country_id = ? and state_id between ? and ? LIMIT 50
   elseif (subtest == "READ_FTS" )
   then
               -- SELECT min(dob) FROM phptest
   else
     print ("Error SUBTEST=" .. subtest .. "!!!")
   end  

   rs = db_execute(stmt)
   db_store_results(rs)
   db_free_results(rs)

   if (trx_mode)
   then
     db_execute(commit_stmt)
   end
end

function set_vars()

   countrySize= 200
   stateSize= 50
   rangeDiapason=100
   
   oltp_table_size = oltp_table_size or 10000

   autoid=0

   if (oltp_auto_inc == 'off') then
      oltp_auto_inc = false
   else
      oltp_auto_inc = true
   end

   if (trx_mode=='' or trx_mode==nill)
   then
     trx_mode=1
   end

   if (mrr=='' or mrr==nill)
   then 
     mrr='on'
   end

   if (cond_pushdown=='' or cond_pushdown==nill)
   then
     cond_pushdown='on'
   end

end

function rand_varchar(maxlen)
  local len
  len = sb_rand(5, maxlen);
  return "'" .. rand_string(len) .. "'"
end

function rand_string(length)

  local nps
  local rnd
  nps = ""

  for i = 0, length do
    if (sb_rand(1, 36) <= 26)
    then
      rnd= sb_rand(97, 122)
    else
      rnd= sb_rand(48, 57)
    end
    nps= nps .. string.char(rnd)
  end
  
  
  return nps
end

function rand_email()

   return "'".. rand_string(10) .. '@' .. rand_string(20) .. '.com' .. "'"
end

function get_autoinc()

  autoid=autoid+1
  return autoid
end

function help()
 
  set_vars()
  
  print ("mysql-db " .. mysql_db .. "mysql-table" .. mysql_table )

  print ("Usage information for phptest.lua :\n\n")

  print ("--subtest=<subtest name>")
  print ([[  Following subtests are implemeted: READ_KEY_POINT,READ_KEY_POINT_NO_DATA,READ_KEY_POINT_LIMIT,
                                     READ_KEY_POINT_NO_DATA_LIMIT,READ_PK_POINT,READ_PK_POINT_INDEX,
                                     READ_PK_RANGE,READ_PK_RANGE_INDEX,READ_KEY_RANGE,READ_KEY_RANGE_LIMIT,
                                     READ_KEY_RANGE_NO_DATA,READ_KEY_RANGE_NO_DATA_LIMIT,READ_FTS ]])
  print ("--mrr=[on|off] default:on")
  print ("--cond_pushdown=[on|off] default:on")
  print ("--trx-mode=[0|1] Enable/disable transaction mode (BEGIN/COMMIT|LOCK/UNLOCK) for query (default:1)")
  print ("--oltp-table-size=<number of rows> default:1000000")  
  print ("--oltp-table-name=<name of created table>")
  print ("--mysql-socket=<socket file>")
  print ("--mysql-user=<user>")
  print ("--mysql-port=<port>")
  print ("--mysql-host=<host>")
  print ("--mysql-db=<db>")
  print ("--mysql-table-engine=<engine>")
    
end