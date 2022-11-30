class puppet_profiles::phpfpm (
#  Array[String] $versions                     = undef,
#  Hash[String, Array[String]] $modules = undef,
){
  @apt::ppa { 'ppa:ondrej/php': }
}
