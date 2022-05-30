Facter.add(:timezone) do
  has_weight 10
  confine :os do |os|
    os['name'] == 'Ubuntu'
  end
  setcode do
    Facter::Core::Execution.execute('/usr/bin/timedatectl show -p Timezone | /usr/bin/sed "s/Timezone=//"')
  end
end
