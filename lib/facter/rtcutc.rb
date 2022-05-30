Facter.add(:rtcutc) do
  has_weight 10
  confine :os do |os|
    os['name'] == 'Ubuntu'
  end
  setcode do
    Facter::Core::Execution.execute('/usr/bin/timedatectl show -p LocalRTC | /usr/bin/sed "s/LocalRTC=//"') == 'no'
  end
end
