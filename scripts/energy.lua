energy = {}

-- Initializes the energy module (MUST BE CALLED IN OBJECT init() FUNCTION)
function energy.init()
  --capacity of internal energy storage
  energy.capacity = entity.configParameter("energyCapacity")
  if energy.capacity == nil then
    energy.capacity = 100
  end

  --current energy storage
  if storage.curEnergy == nil then
    storage.curEnergy = 0
  end

  --maximum amount of energy to push per tick (if 0, this object cannot send energy)
  energy.sendMax = entity.configParameter("energySendMax")
  if energy.sendMax == nil then
    energy.sendMax = 0
  end

  --frequency (in seconds) to push energy (maybe make this hard coded)
  energy.sendFreq = entity.configParameter("energysendFreq")
  if energy.sendFreq == nil then
    energy.sendFreq = 1
  end

  --timer variable that tracks the cooldown until next transmission pulse
  energy.sendTimer = energy.sendFreq

  --maximum range (in blocks) that this device will search for entities to connect to
  --NOTE: we may not want to make this configurable, since it will result in strange behavior if asymmetrical
  energy.linkRange = entity.configParameter("energyLinkRange")
  if energy.linkRange == nil then
    energy.linkRange = 10
  end

  --use this to run more initialization the first time main() is called (in energy.update())
  self.energyInitialized = false

  --frequency (in seconds) to perform LoS checks on connected entities
  energy.connectCheckFreq = 5

  --timer variable that tracks cooldown until next connection LoS check
  energy.connectCheckTimer = energy.connectCheckFreq

  --table to hold id's of connected entities (no point storing this since id's change on reload)
  energy.connections = {}

  --prevent looping
  energy.sourcesThisTick = {}
  energy.sourcesLastTick = {}
end

-- performs any unloading necessary when the object is removed (MUST BE CALLED IN OBJECT die() FUNCTION)
function energy.die()
  for entityId, v in pairs(energy.connections) do
    disconnect(entityId)
  end
end

-- Performs per-tick updates for energy module (MUST BE CALLED IN OBJECT main() FUNCTION)
function energy.update()
  if self.energyInitialized then
    --periodic energy transmission pulses
    if energy.sendMax > 0 then
      energy.sendTimer = energy.sendTimer - entity.dt()
      if energy.sendTimer <= 0 then
        energy.sendEnergy()
        energy.sendTimer = energy.sendTimer + energy.sendFreq
      end
    end

    --periodic connection checks
    energy.connectCheckTimer = energy.connectCheckTimer - entity.dt()
    if energy.connectCheckTimer <= 0 then
      energy.checkConnections()
      energy.connectCheckTimer = energy.connectCheckTimer + energy.connectCheckFreq
    end
  else
    energy.findConnections()
    self.energyInitialized = true
  end
end

-------------------------------------------------

-- Returns how much energy the object currently holds
function energy.getEnergy()
  return storage.curEnergy
end

-- sets the current energy pool (and provides a place to update animations, etc.)
function energy.setEnergy(amount)
  if amount ~= energy.getEnergy() then
    storage.curEnergy = amount
    onEnergyChange(amount)
  end
end

-- object hook called when energy amount is changed
if not onEnergyChange then
  function onEnergyChange(newAmount) end
end

-- returns the total amount of space in the object's energy storage
function energy.getCapacity()
  return energy.capacity
end

-- returns the amount of free space in the object's energy storage
function energy.getUnusedCapacity()
  return energy.capacity - energy.getEnergy()
end

-- Adds the specified amount of energy to the storage pool, to a maximum of <energy.capacity>
-- returns the total amount of energy accepted
function energy.receiveEnergy(amount, entityId)
  if (entityId) then
    world.logInfo("adding %d to sources list", entityId)
    energy.sourcesThisTick[entityId] = true
  else
    world.logInfo("YER DOIN IT RONG")
  end

  local newEnergy = energy.getEnergy() + amount
  if newEnergy <= energy.getCapacity() then
    energy.setEnergy(newEnergy)
    return amount
  else
    local acceptedEnergy = energy.getUnusedCapacity()
    energy.setEnergy(energy.getCapacity())
    return amount - acceptedEnergy
  end
end

-- reduces the current energy pool by the specified amount, to a minimum of 0
function energy.removeEnergy(amount, entityId)
  energy.setEnergy(math.max(0, energy.getEnergy() - amount))
end

-- attempt to remove the specified amount of energy
-- @returns false if there is insufficient energy stored (and does not remove energy)
function energy.consumeEnergy(amount)
  if amount <= energy.getEnergy() then
    energy.removeEnergy(amount)
    return true
  else
    return false
  end
end

-------------------------------------------------

--Used to determine if it uses the energy system
function energy.usesEnergy()
  return true
end

-- returns true if object is a valid energy receiver
function energy.canReceiveEnergy()
  return energy.getUnusedCapacity() > 20
end

-- connects to the specified entity id
function energy.connect(entityId)
  energy.connections[entityId] = true
  world.callScriptedEntity(entityId, "energy.onConnect", entity.id())
end

-- callback for energy.connect
function energy.onConnect(entityId)
  energy.connections[entityId] = true
end

-- disconnects from the specified entity id
function energy.disconnect(entityId)
  world.callScriptedEntity(entityId, "energy.onDisconnect", entity.id())
  energy.connections[entityId] = nil
end

-- callback for energy.disconnect
function energy.onDisconnect(entityId)
  energy.connections[entityId] = nil
end

-- Returns a list of connected entity id's
function energy.getConnections()
  return self.energyConnections
end

-- finds and connects to entities within <energy.linkRange> blocks
function energy.findConnections()
  energy.connections = {}

  --find nearby energy devices within LoS
  local entityIds = world.objectQuery(entity.position(), energy.linkRange, { 
      withoutEntityId = entity.id(),
      inSightOf = entity.id(), 
      callScript = "energy.usesEnergy"
    })

  world.logInfo("%s %d found %d entities within range:", entity.configParameter("objectName"), entity.id(), #entityIds)
  world.logInfo(entityIds)

  --connect
  for i, entityId in ipairs(entityIds) do
    energy.connect(entityId)
  end
end

-- performs a LoS check to the given entity
function energy.checkLoS(entityId)
  --TODO
  return true
end

-- performs periodic LoS checks on connected entities
function energy.checkConnections()
  --TODO
end

-- comparator function for table sorting
function energy.compareNeeds(a, b)
  return a[2] < b[2]
end

-- pushes energy to connected entities. amount is divided between # of valid receivers
function energy.sendEnergy()
  world.logInfo("%s %d sending energy...", entity.configParameter("objectName"), entity.id())
  local energyNeeds = {}

  -- check energy needs for all connected entities
  for entityId, v in pairs(energy.connections) do
    if not energy.sourcesThisTick[entityId] and not energy.sourcesLastTick[entityId] then
      local thisEnergyNeed = world.callScriptedEntity(entityId, "energy.getUnusedCapacity")
      if thisEnergyNeed then
        energyNeeds[#energyNeeds + 1] = {entityId, thisEnergyNeed}
      end
    end
  end

  -- sort table of energy needs
  table.sort(energyNeeds, energy.compareNeeds)

  world.logInfo(energyNeeds)

  -- process list and distribute remainder evenly at each step
  local totalEnergyToSend = math.min(energy.getEnergy(), energy.sendMax)
  local remainingEnergyToSend = totalEnergyToSend
  while #energyNeeds > 0 do
    if energyNeeds[1][2] > 0 then
      local sendAmt = remainingEnergyToSend / #energyNeeds
      remainingEnergyToSend = remainingEnergyToSend - world.callScriptedEntity(energyNeeds[1][1], "energy.receiveEnergy", sendAmt, entity.id())
    end
    table.remove(energyNeeds, 1)
  end

  --remove the total amount of energy sent
  local totalSent = totalEnergyToSend - remainingEnergyToSend
  world.logInfo("%s %d successfully sent %d energy", entity.configParameter("objectName"), entity.id(), totalSent)
  energy.removeEnergy(totalSent)

  --reset anti-looping tables
  energy.sourcesLastTick = energy.sourcesThisTick
  energy.sourcesThisTick = {}
end