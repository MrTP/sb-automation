function init(virtual)
  if not virtual then
    energy.init()
    datawire.init()

    self.fuelValues = {
      coalore=2,
      uraniumore=4,
      uraniumrod=4,
      plutoniumore=6,
      plutoniumrod=6,
      solariumore=8,
      solariumrod=8
    }

    self.fuelMax = 50

    if storage.fuel == nil then
      storage.fuel = 0
    end

    self.fuelUseRate = 0.2

    local pos = entity.position()
    self.itemPickupArea = {
      {pos[1] + 1, pos[2] - 1},
      {pos[1] + 4, pos[2]}
    }
    self.dropPoint = {pos[1] + 2, pos[2] + 1}

    --used to track items we spit back out
    self.ignoreDropIds = {}

    entity.setInteractive(not entity.isInboundNodeConnected(0))
    updateAnimationState()
  end
end

function die()
  energy.die()
end

function onNodeConnectionChange()
  checkNodes()
end

function onInboundNodeChange(args)
  checkNodes()
end

function onInteraction(args)
  if not entity.isInboundNodeConnected(0) then
    if storage.state then
      storage.state = false
    elseif storage.fuel > 0 then
      storage.state = true
    end

    updateAnimationState()
  end
end

function updateAnimationState()
  if storage.state then
    entity.setAnimationState("generatorState", "on")
  else
    entity.setAnimationState("generatorState", "off")
  end

  entity.scaleGroup("fuelbar", {math.min(1, storage.fuel / self.fuelMax), 1})
end

function checkNodes()
  local isWired = entity.isInboundNodeConnected(0)
  if isWired then
    storage.state = entity.getInboundNodeLevel(0)
    updateAnimationState()
  end
  entity.setInteractive(not isWired)
end

--never accept energy from elsewhere
function onEnergyNeedsCheck(energyNeeds)
  energyNeeds[tostring(entity.id())] = 0
  return energyNeeds
end

--only send energy while generating (even if it's in the pool... could try revamping this later)
function onEnergySendCheck()
  if storage.state then
    return energy.getEnergy()
  else
    return 0
  end
end

function getFuelItems()
  local dropIds = world.itemDropQuery(self.itemPickupArea[1], self.itemPickupArea[2])
  for i, entityId in ipairs(dropIds) do
    if not self.ignoreDropIds[entityId] then
      local itemName = world.entityName(entityId)
      if self.fuelValues[itemName] then
        local item = world.takeItemDrop(entityId, entity.id())
        if item then
          if self.fuelValues[item[1]] then
            while item[2] > 0 and storage.fuel < self.fuelMax do
              storage.fuel = storage.fuel + self.fuelValues[item[1]]
              item[2] = item[2] - 1
            end
          end

          if item[2] > 0 then
            ejectItem(item)
          end
        end
      else
        self.ignoreDropIds[entityId] = true
      end
    end
  end
  updateAnimationState()
end

function ejectItem(item)
  local itemDropId
  if next(item[3]) == nil then
    itemDropId = world.spawnItem(item[1], self.dropPoint, item[2])
  else
    itemDropId = world.spawnItem(item[1], self.dropPoint, item[2], item[3])
  end
  self.ignoreDropIds[itemDropId] = true
end

function generate()
  local tickFuel = self.fuelUseRate * entity.dt()
  if storage.fuel >= tickFuel then
    storage.fuel = storage.fuel - tickFuel
    energy.addEnergy(tickFuel * energy.fuelEnergyConversion)
    return true
  else
    storage.state = false
    return false
  end
end 

function main()
  if storage.state then
    generate()
    updateAnimationState()
  end

  if storage.fuel < self.fuelMax then
    getFuelItems()
  end

  energy.update()
  datawire.update()
end