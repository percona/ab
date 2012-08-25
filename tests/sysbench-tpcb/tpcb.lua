function prepare()
   local query
   local i
   local j

   set_vars()

   db_connect()

   print("Preparing TPC-B database\n")
   print(" - database:     " .. mysql_db)
   print(" - engine:       " .. mysql_table_engine)
   print(" - trx_mode:     " .. ((trx_mode and "on") or "off"))
   print(" - scale factor: " .. tps)
   print()
   
   cleanup()

   if (db_driver == "mysql") then
      branches = [[
                    CREATE TABLE branches (bid int PRIMARY KEY, bbalance int, filler char(88))
                    /*! ENGINE = ]] .. mysql_table_engine .. " */"
      tellers = [[
                    CREATE TABLE tellers (tid int PRIMARY KEY, bid int, tbalance int, filler char(84))
                    /*! ENGINE = ]] .. mysql_table_engine .. " */"
      accounts = [[
                    CREATE TABLE accounts (aid int PRIMARY KEY, bid int, abalance int, filler char(84))
                    /*! ENGINE = ]] .. mysql_table_engine .. " */"
      history  = [[
                    CREATE TABLE history (tid int, bid int, aid int, delta int, mtime timestamp, filler char(22))
                    /*! ENGINE = ]] .. mysql_table_engine .. " */"
   else
      print("Unknown database driver: " .. db_driver)
      return 1
   end

   db_query(branches)
   db_query(tellers)
   db_query(accounts)
   db_query(history)

   if (trx_mode)
   then
     db_query("BEGIN")
   end

   print("Inserting " .. tps * nbranches .. " records to branches table.")
   print("Inserting " .. tps * ntellers .. " records to tellers table.")   
   print("Inserting " .. tps * naccounts .. " records to accounts table.")

   db_bulk_insert_init([[
                         INSERT INTO branches (bid, bbalance, filler) VALUES
                       ]])

   q=nbranches * tps;   
   for i = 0, q-1 do
      db_bulk_insert_next("("..(i+1)..", 0, REPEAT('b',88))")
   end
   db_bulk_insert_done()

   db_bulk_insert_init([[
                         INSERT INTO tellers (tid, bid, tbalance, filler) VALUES
                       ]])
   
   for i = 0, (ntellers * tps)-1 do
      db_bulk_insert_next("("..(i+1)..","..(i/ntellers+1)..", 0, REPEAT('t',84))")
   end
   db_bulk_insert_done()

   db_bulk_insert_init([[
                         INSERT INTO accounts (aid, bid, abalance, filler) VALUES
                       ]])
   
   q=naccounts * tps;
   for i = 0, q-1 do
      local j
      j=i+1
      db_bulk_insert_next("("..j..","..(i/naccounts+1)..", 0, REPEAT('c',84))")
   end
   db_bulk_insert_done()

   if (trx_mode)
   then
     db_query("COMMIT")
   end

   return 0
end


function cleanup()
   print("Dropping tables 'accounts, tellers, history, branches'...")
   db_query("DROP TABLE if exists accounts")
   db_query("DROP TABLE if exists tellers")   
   db_query("DROP TABLE if exists history")
   db_query("DROP TABLE if exists branches")   
end

function thread_init(thread_id)
   local query

   set_vars()

   begin_stmt = db_prepare("BEGIN")
   commit_stmt = db_prepare("COMMIT")
   
   query1="UPDATE accounts SET abalance = abalance + ? WHERE aid = ?"
   query2="SELECT abalance FROM accounts WHERE aid = ?"
   query3="UPDATE tellers SET tbalance = tbalance + ? WHERE tid = ?"
   query4="UPDATE branches SET bbalance = bbalance + ? WHERE bid = ?"
   query5="INSERT INTO history (tid,bid,aid,delta,mtime, filler) VALUES (?,?,?,?, NOW(),'aaaaaaaaaaaaaaaaaaaaaa')"

   params1 = {0,0}
   params2 = {0}
   params3 = {0,0}
   params4 = {0,0}   
   params5 = {0,0,0,0}   

   stmt1=db_prepare(query1)
   stmt2=db_prepare(query2)   
   stmt3=db_prepare(query3)   
   stmt4=db_prepare(query4)
   stmt5=db_prepare(query5)

   db_bind_param(stmt1, params1)
   db_bind_param(stmt2, params2)   
   db_bind_param(stmt3, params3)
   db_bind_param(stmt4, params4)
   db_bind_param(stmt5, params5)

end

function event(thread_id)
   local rs

   if (trx_mode)
   then
     db_execute(begin_stmt)
   end

   aid=sb_rand(1, naccounts * tps)
   bid=sb_rand(1, nbranches * tps)
   tid=sb_rand(1, ntellers * tps)
   delta=sb_rand(1, 1000)

   params1[1]=delta
   params1[2]=aid

   params2[1]=aid

   params3[1]=delta
   params3[2]=tid

   params4[1]=delta
   params4[2]=bid
   
   params5[1]=tid  
   params5[2]=bid
   params5[3]=aid  
   params5[4]=delta

   rs = db_execute(stmt1)
   db_store_results(rs)
   db_free_results(rs)

   rs = db_execute(stmt2)
   db_store_results(rs)
   db_free_results(rs)

   rs = db_execute(stmt3)
   db_store_results(rs)
   db_free_results(rs)

   rs = db_execute(stmt4)
   db_store_results(rs)
   db_free_results(rs)

   rs = db_execute(stmt5)
   db_store_results(rs)
   db_free_results(rs)

   if (trx_mode)
   then
     db_execute(commit_stmt)
   end
end

function set_vars()

--test constants
   nbranches=1
   ntellers=10
   naccounts=100000

-- scaling factor
   if (scale=='' or scale==nil)
   then 
     tps = 1
   else
     tps = scale
   end

--transaction mode 
   if (trx_mode and trx_mode~='off')
   then
     trx_mode=true
   else
     trx_mode=false
   end
end
