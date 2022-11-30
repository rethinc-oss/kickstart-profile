class puppet_profiles::role::server::web {
  include puppet_profiles::base
  include puppet_profiles::nginx
  include puppet_profiles::phpfpm
}
