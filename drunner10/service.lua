-- drunner service configuration for ROCKETCHAT
-- based on https://raw.githubusercontent.com/RocketChat/Rocket.Chat/develop/docker-compose.yml
-- and https://github.com/docker-library/docs/tree/master/rocket.chat

rccontainer="drunner-${SERVICENAME}"
dbcontainer="drunner-${SERVICENAME}-mongodb"
dbvolume="drunner-${SERVICENAME}-database"
certvolume="drunner-${SERVICENAME}-certvolume"
network="drunner-${SERVICENAME}-network"

-- addconfig( VARIABLENAME, DEFAULTVALUE, DESCRIPTION )
addconfig("MODE","fake","LetsEncrypt mode: fake, staging, production")
addconfig("EMAIL","","LetsEncrypt email")
addconfig("DOMAIN","","Domain for the rocket.chat service")

-- overrideable.
sMode="${MODE}"
sEmail="${EMAIL}"
sDomain="${DOMAIN}"

function start_mongo()
    -- fire up the mongodb server.
    result=docker("run",
    "--name",dbcontainer,
    "--network=" .. network ,
    "-v", dbvolume .. ":/data/db",
    "-d","mongo:3.2",
    "--smallfiles",
    "--oplogSize","128",
    "--replSet","rs0")

    if result~=0 then
      print("Failed to start mongodb.")
      os.exit(1)
    end

-- Wait for port 27017 to come up in dbcontainer (30s timeout on the given network)
    if not dockerwait(dbcontainer, "27017") then
      print("Mongodb didn't respond in the expected timeframe.")
      os.exit(1)
    end

    -- run the mongo replica config
    result=docker("run","--rm",
    "--network=" .. network ,
    "mongo:3.2",
    "mongo",dbcontainer .. "/rocketchat","--eval",
    "rs.initiate({ _id: 'rs0', members: [ { _id: 0, host: 'localhost:27017' } ]})"
    )

    if result~=0 then
      print("Mongodb replica init failed")
      os.exit(1)
    end

end

function start_rocketchat()
    -- and rocketchat on port 3000
    result=docker("run",
    "--name",rccontainer,
    "--network=" .. network ,
    "--env","MONGO_URL=mongodb://" .. dbcontainer .. ":27017/rocketchat",
    "--env","MONGO_OPLOG_URL=mongodb://" .. dbcontainer .. ":27017/local",
    "-d","rocket.chat")

    if result~=0 then
      print("Failed to start rocketchat on port ${PORT}.")
      os.exit(1)
    end

    if not dockerwait(rccontainer, "3000") then
      print("Rocketchat didn't respond in the expected timeframe.")
      os.exit(1)
    end

end

function start()
   if (dockerrunning(dbcontainer)) then
      print("rocketchat is already running.")
   else
      start_mongo()
      start_rocketchat()
      
      -- use dRunner's built-in proxy to expose rocket.chat over SSL (port 443) on host.
      -- disable timeouts because rocket.chat keeps websockets open for ages.
      proxyenable(sDomain,rccontainer,3000,network,sEmail,sMode,false)
   end
end

function stop()
   proxydisable()

   dockerstop(rccontainer)
   dockerstop(dbcontainer)
end

function uninstall()
   stop()
   docker("network","rm",network)
   -- we retain the database volume
end

function obliterate()
   stop()
   docker("network","rm",network)
   dockerdeletevolume(dbvolume)
end

-- install
function install()
   dockerpull("mongo:3.2")
   dockerpull("rocket.chat")
   dockercreatevolume(dbvolume)
   docker("network","create",network)
end

function backup()
   docker("pause",rccontainer)
   docker("pause",dbcontainer)

   dockerbackup(dbvolume)

   docker("unpause",dbcontainer)
   docker("unpause",rccontainer)
end

function restore()
   dockerpull("mongo:3.2")
   dockerpull("rocket.chat")
   dockerrestore(dbvolume)
   docker("network","create",network)

-- set mode to fake for safety!
   dconfig_set("MODE","fake")
end

function selftest()
   sDomain="travis"
   sEmail="j@842.be"
   sMode="fake"
   print("Starting...")
   start()
   print("Stopping...")
   stop()
   print("Self test complete.")
end

function help()
   return [[
   NAME
      ${SERVICENAME} - Run a rocket.chat server.
      Configure the HTTPS settings (Domain, LetsEncrypt email) before
      starting.

   SYNOPSIS
      ${SERVICENAME} help             - This help
      ${SERVICENAME} configure        - Configure domain, email, mode.
      ${SERVICENAME} start            - Start the service
      ${SERVICENAME} stop             - Stop it

   DESCRIPTION
      Built from ${IMAGENAME}.
   ]]
end
