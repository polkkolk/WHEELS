Dummy = script.Parent.Parent.Dummy
Clone = Dummy:Clone()

function Regen()
wait(5)
Dummy.Parent = nil
Clone.Parent = script.Parent.Parent
Dummy = Clone
Dummy:makeJoints()
Dummy.Torso.CFrame = script.Parent.CFrame + Vector3.new(0,2.7,0)
Clone = Dummy:Clone()
Dummy.Humanoid.Died:connect(Regen)
end

Dummy.Humanoid.Died:connect(Regen)