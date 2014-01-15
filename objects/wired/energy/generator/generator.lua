function init(virtual)
  if not virtual then
    energy.init()
    datawire.init()
    entity.setInteractive(true)
  end
end

function onInteraction(args)
  world.logInfo("HARD ENERGY RESET")
  world.objectQuery(entity.position(), 100, { callScript = "energy.setEnergy", callScriptArgs = { 0 }})
end

function main()
  energy.setEnergy(100) --unlimited generation for testing
  energy.update()
  datawire.update()
  energy.setEnergy(100) --unlimited generation for testing
end